#!/bin/bash
# Payment System Configuration
export EC2_IP="13.50.7.86"
export LB_URL="a2d671e5e73944b719a134d0e26b1e0d-955143240.eu-north-1.elb.amazonaws.com"
export AWS_REGION="eu-north-1"
export CLUSTER_NAME="payment-cluster"
export DB_HOST="payment-db.cng6kmc8ygsv.eu-north-1.rds.amazonaws.com"

echo "✅ Config loaded!"
echo "   EC2:  http://$EC2_IP:3000"
echo "   K8s:  http://$LB_URL"
