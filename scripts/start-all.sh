#!/bin/bash

echo "▶️  Starting all Payment System AWS resources..."
echo "Region: eu-north-1"
echo "=================================="

# ─── START RDS FIRST (takes longest) ─────────────────────
echo ""
echo "⏳ Starting RDS database..."
aws rds start-db-instance \
    --db-instance-identifier payment-db \
    --region eu-north-1 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ RDS starting (takes 3-5 mins)"
else
    echo "⚠️  RDS might already be running"
fi

# ─── START EC2 ────────────────────────────────────────────
echo ""
echo "⏳ Starting EC2 instance..."
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=payment-app-server" \
              "Name=instance-state-name,Values=stopped" \
    --region eu-north-1 \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
    aws ec2 start-instances \
        --instance-ids $INSTANCE_ID \
        --region eu-north-1
    echo "✅ EC2 starting: $INSTANCE_ID"
else
    echo "⚠️  No stopped EC2 found (might already be running)"
fi

# ─── START EKS NODES ──────────────────────────────────────
echo ""
echo "⏳ Scaling up EKS nodes to 2..."
aws eks update-nodegroup-config \
    --cluster-name payment-cluster \
    --nodegroup-name payment-nodes \
    --scaling-config minSize=1,maxSize=4,desiredSize=2 \
    --region eu-north-1

echo "✅ EKS nodes scaling up (takes 3-5 mins)"

# ─── WAIT FOR RDS ─────────────────────────────────────────
echo ""
echo "⏳ Waiting for RDS to be available..."
aws rds wait db-instance-available \
    --db-instance-identifier payment-db \
    --region eu-north-1
echo "✅ RDS is ready!"

# ─── WAIT FOR EC2 ─────────────────────────────────────────
echo ""
echo "⏳ Waiting for EC2 to be running..."
aws ec2 wait instance-running \
    --instance-ids $INSTANCE_ID \
    --region eu-north-1 2>/dev/null
echo "✅ EC2 is running!"

# ─── GET NEW EC2 IP (changes after restart) ───────────────
echo ""
NEW_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --region eu-north-1 \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)
echo "📡 New EC2 IP: $NEW_IP"

# ─── WAIT FOR EKS NODES ───────────────────────────────────
echo ""
echo "⏳ Waiting for EKS nodes to be ready..."
sleep 60
kubectl get nodes
kubectl get pods

# ─── SUMMARY ─────────────────────────────────────────────
echo ""
echo "=================================="
echo "✅ ALL SYSTEMS UP"
echo "=================================="
echo "🌍 Services running:"
echo "   • EC2 API:  http://$NEW_IP:3000/health"
echo "   • RDS:      payment-db.cng6kmc8ygsv.eu-north-1.rds.amazonaws.com"
echo ""

LB_URL=$(kubectl get service payment-api-service \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -n "$LB_URL" ]; then
    echo "   • K8s LB:   http://$LB_URL/health"
fi

echo ""
echo "🛑 To stop everything: ./scripts/stop-all.sh"
