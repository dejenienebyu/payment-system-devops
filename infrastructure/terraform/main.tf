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

# ─── DATA: Get available AZs ──────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

# ─── SECURITY GROUP: App Server ───────────────────────────
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

# ─── SECURITY GROUP: Database ─────────────────────────────
resource "aws_security_group" "db_sg" {
  name        = "payment-db-sg"
  description = "Database firewall - only allow app server"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.payment_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "payment-db-sg"
    Project = "payment-system"
  }
}

# ─── DB SUBNET GROUP ──────────────────────────────────────
resource "aws_db_subnet_group" "payment_db_subnet" {
  name       = "payment-db-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name    = "payment-db-subnet-group"
    Project = "payment-system"
  }
}

# ─── DATA: Get default VPC subnets ────────────────────────
data "aws_subnets" "default" {
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# ─── RDS PostgreSQL ───────────────────────────────────────
resource "aws_db_instance" "payment_db" {
  identifier        = "payment-db"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "paymentdb"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.payment_db_subnet.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  # Free tier settings
  publicly_accessible = false
  skip_final_snapshot = true
  multi_az            = false

  tags = {
    Name    = "payment-db"
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
    yum install -y nodejs git postgresql15
    npm install -g pm2

    mkdir -p /home/ec2-user/payment-app
    cd /home/ec2-user/payment-app
    npm init -y
    npm install express pg

    cat > app.js << 'APPEOF'
const express = require('express');
const { Pool } = require('pg');
const app = express();
app.use(express.json());

const pool = new Pool({
  host: process.env.DB_HOST,
  database: 'paymentdb',
  user: process.env.DB_USER,
  password: process.env.DB_PASS,
  port: 5432,
  ssl: { rejectUnauthorized: false }
});

// Create table on startup
async function initDB() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS transactions (
        id VARCHAR(50) PRIMARY KEY,
        amount DECIMAL(10,2) NOT NULL,
        currency VARCHAR(3) NOT NULL,
        description TEXT,
        status VARCHAR(20) DEFAULT 'success',
        created_at TIMESTAMP DEFAULT NOW()
      )
    `);
    console.log('✅ Database connected and table ready');
  } catch (err) {
    console.error('DB init error:', err.message);
  }
}
initDB();

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'payment-api',
    version: '2.0.0',
    database: 'PostgreSQL RDS',
    timestamp: new Date().toISOString(),
    server: 'AWS EC2 - eu-north-1 - Terraform managed'
  });
});

app.get('/transactions', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM transactions ORDER BY created_at DESC'
    );
    res.json({ count: result.rows.length, transactions: result.rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/pay', async (req, res) => {
  const { amount, currency, description } = req.body;
  if (!amount || !currency) {
    return res.status(400).json({ error: 'amount and currency are required' });
  }
  try {
    const id = 'txn_' + Date.now();
    await pool.query(
      'INSERT INTO transactions (id, amount, currency, description) VALUES ($1, $2, $3, $4)',
      [id, amount, currency, description || 'Payment']
    );
    const result = await pool.query(
      'SELECT * FROM transactions WHERE id = $1', [id]
    );
    console.log('💳 Payment saved to DB: ' + currency + ' ' + amount);
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(3000, () => {
  console.log('✅ Payment API v2.0 running on port 3000 with PostgreSQL');
});
APPEOF

    # Write DB credentials from environment
    cat > /home/ec2-user/payment-app/.env << ENVEOF
DB_HOST=${aws_db_instance.payment_db.address}
DB_USER=${var.db_username}
DB_PASS=${var.db_password}
ENVEOF

    chown -R ec2-user:ec2-user /home/ec2-user/payment-app

    # Start with PM2 using env file
    sudo -u ec2-user pm2 start /home/ec2-user/payment-app/app.js \
      --name payment-api \
      --env-file /home/ec2-user/payment-app/.env \
      -- --env production
    sudo -u ec2-user pm2 save
    sudo env PATH=\$PATH:/usr/bin pm2 startup systemd -u ec2-user --hp /home/ec2-user
  SCRIPT

  tags = {
    Name    = "payment-app-server"
    Project = "payment-system"
  }
}
