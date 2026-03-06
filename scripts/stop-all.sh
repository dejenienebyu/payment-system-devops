#!/bin/bash

echo "🛑 Stopping all Payment System AWS resources..."
echo "Region: eu-north-1"
echo "=================================="

# ─── STOP EKS NODE GROUP (most expensive) ────────────────
echo ""
echo "⏳ Scaling down EKS nodes to 0..."
aws eks update-nodegroup-config \
    --cluster-name payment-cluster \
    --nodegroup-name payment-nodes \
    --scaling-config minSize=0,maxSize=4,desiredSize=0 \
    --region eu-north-1

echo "✅ EKS nodes scaling down (takes 3-5 mins)"

# ─── STOP EC2 INSTANCE ───────────────────────────────────
echo ""
echo "⏳ Stopping EC2 instance..."
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=payment-app-server" \
              "Name=instance-state-name,Values=running" \
    --region eu-north-1 \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
    aws ec2 stop-instances \
        --instance-ids $INSTANCE_ID \
        --region eu-north-1
    echo "✅ EC2 stopped: $INSTANCE_ID"
else
    echo "⚠️  No running EC2 found"
fi

# ─── STOP RDS ─────────────────────────────────────────────
echo ""
echo "⏳ Stopping RDS database..."
aws rds stop-db-instance \
    --db-instance-identifier payment-db \
    --region eu-north-1 2>/dev/null

if [ $? -eq 0 ]; then
    echo "✅ RDS stopping (takes 3-5 mins)"
else
    echo "⚠️  RDS might already be stopped"
fi

# ─── SUMMARY ─────────────────────────────────────────────
echo ""
echo "=================================="
echo "🛑 SHUTDOWN COMPLETE"
echo "=================================="
echo "💰 Resources stopped (saving money):"
echo "   • EKS nodes    → scaled to 0"
echo "   • EC2 server   → stopped"
echo "   • RDS database → stopped"
echo ""
echo "📌 Still running (minimal cost):"
echo "   • EKS Control Plane (~$0.10/hr)"
echo "   • S3 bucket (pennies/month)"
echo "   • ECR images (pennies/month)"
echo ""
echo "▶️  To restart everything: ./scripts/start-all.sh"
