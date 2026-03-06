#!/bin/bash

echo "📊 Payment System Status"
echo "Region: eu-north-1"
echo "=================================="

# ─── EC2 ──────────────────────────────────────────────────
echo ""
echo "🖥️  EC2 Instance:"
aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=payment-app-server" \
    --region eu-north-1 \
    --query "Reservations[0].Instances[0].[State.Name,PublicIpAddress,InstanceType]" \
    --output table

# ─── RDS ──────────────────────────────────────────────────
echo ""
echo "🗄️  RDS Database:"
aws rds describe-db-instances \
    --db-instance-identifier payment-db \
    --region eu-north-1 \
    --query "DBInstances[0].[DBInstanceStatus,Endpoint.Address]" \
    --output table

# ─── EKS ──────────────────────────────────────────────────
echo ""
echo "☸️  EKS Node Group:"
aws eks describe-nodegroup \
    --cluster-name payment-cluster \
    --nodegroup-name payment-nodes \
    --region eu-north-1 \
    --query "nodegroup.scalingConfig" \
    --output table

# ─── KUBERNETES PODS ──────────────────────────────────────
echo ""
echo "🐳 Kubernetes Pods:"
kubectl get pods 2>/dev/null || echo "⚠️  kubectl not connected"

# ─── LOAD BALANCER ────────────────────────────────────────
echo ""
echo "🌍 Load Balancer:"
kubectl get service payment-api-service 2>/dev/null || echo "⚠️  No service found"

# ─── QUICK HEALTH CHECK ───────────────────────────────────
echo ""
echo "💓 Health Checks:"

EC2_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=payment-app-server" \
              "Name=instance-state-name,Values=running" \
    --region eu-north-1 \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

if [ -n "$EC2_IP" ] && [ "$EC2_IP" != "None" ]; then
    EC2_HEALTH=$(curl -s --max-time 5 http://$EC2_IP:3000/health \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'])" 2>/dev/null)
    echo "   EC2 API: ${EC2_HEALTH:-unreachable} ($EC2_IP)"
else
    echo "   EC2 API: stopped"
fi

LB_URL=$(kubectl get service payment-api-service \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -n "$LB_URL" ]; then
    LB_HEALTH=$(curl -s --max-time 5 http://$LB_URL/health \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['status'])" 2>/dev/null)
    echo "   K8s LB:  ${LB_HEALTH:-unreachable}"
    echo "   LB URL:  http://$LB_URL"
fi

echo ""
echo "=================================="
echo "💰 Cost tip: run ./scripts/stop-all.sh when not studying!"
echo "=================================="
