terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "payment-system-tfstate-557809209084-eu"
    key    = "phase2/terraform.tfstate"
    region = "eu-north-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── SECURITY GROUP ───────────────────────────────────────
resource "aws_security_group" "payment_sg" {
  name        = "payment-app-sg"
  description = "Payment app firewall - Terraform managed"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "payment-app-sg"
    Project = "payment-system"
  }
}

# ─── EC2 INSTANCE ─────────────────────────────────────────
resource "aws_instance" "payment_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.payment_sg.id]

  user_data = <<-SCRIPT
    #!/bin/bash
    yum update -y
    curl -fsSL https://rpm.nodesource.com/setup_16.x | bash -
    yum install -y nodejs git
    npm install -g pm2

    mkdir -p /home/ec2-user/payment-app
    cd /home/ec2-user/payment-app
    npm init -y
    npm install express

    cat > app.js << 'APPEOF'
const express = require('express');
const app = express();
app.use(express.json());

const transactions = [];

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'payment-api',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    server: 'AWS EC2 - eu-north-1 - Terraform managed'
  });
});

app.get('/transactions', (req, res) => {
  res.json({ count: transactions.length, transactions });
});

app.post('/pay', (req, res) => {
  const { amount, currency, description } = req.body;
  if (!amount || !currency) {
    return res.status(400).json({ error: 'amount and currency are required' });
  }
  const transaction = {
    id: 'txn_' + Date.now(),
    amount,
    currency,
    description: description || 'Payment',
    status: 'success',
    timestamp: new Date().toISOString()
  };
  transactions.push(transaction);
  console.log('Payment processed: ' + currency + ' ' + amount);
  res.status(201).json(transaction);
});

app.listen(3000, () => {
  console.log('Payment API running on port 3000');
});
APPEOF

    chown -R ec2-user:ec2-user /home/ec2-user/payment-app
    sudo -u ec2-user pm2 start /home/ec2-user/payment-app/app.js --name payment-api
    sudo -u ec2-user pm2 save
    sudo env PATH=\$PATH:/usr/bin pm2 startup systemd -u ec2-user --hp /home/ec2-user
  SCRIPT

  tags = {
    Name    = "payment-app-server"
    Project = "payment-system"
  }
}
