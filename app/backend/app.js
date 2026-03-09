const express = require('express');
const { Pool } = require('pg');
const client = require('prom-client');
require('dotenv').config();

const app = express();
app.use(express.json());

// ─── PROMETHEUS METRICS ───────────────────────────────────
const register = new client.Registry();
client.collectDefaultMetrics({ register });

// Custom payment metrics
const paymentCounter = new client.Counter({
  name: 'payment_transactions_total',
  help: 'Total number of payment transactions',
  labelNames: ['currency', 'status'],
  registers: [register]
});

const paymentAmount = new client.Histogram({
  name: 'payment_amount_usd',
  help: 'Payment transaction amounts',
  buckets: [10, 50, 100, 500, 1000, 5000],
  registers: [register]
});

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_ms',
  help: 'HTTP request duration in milliseconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [5, 10, 25, 50, 100, 250, 500],
  registers: [register]
});

const dbConnectionGauge = new client.Gauge({
  name: 'db_connections_active',
  help: 'Active database connections',
  registers: [register]
});

// ─── DATABASE ─────────────────────────────────────────────
const pool = new Pool({
  host: process.env.DB_HOST,
  database: 'paymentdb',
  user: process.env.DB_USER,
  password: process.env.DB_PASS,
  port: 5432,
  ssl: { rejectUnauthorized: false }
});

// Track DB connections
pool.on('connect', () => dbConnectionGauge.inc());
pool.on('remove', () => dbConnectionGauge.dec());

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
    console.error('❌ DB init error:', err.message);
  }
}
initDB();

// ─── MIDDLEWARE: track request duration ───────────────────
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    httpRequestDuration
      .labels(req.method, req.path, res.statusCode)
      .observe(duration);
  });
  next();
});

// ─── ROUTES ───────────────────────────────────────────────
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'payment-api',
    version: '4.0.0',
    database: 'PostgreSQL RDS',
    deployment: 'GitHub Actions CI/CD ⚙️',
    monitoring: 'Prometheus + Grafana 📊',
    timestamp: new Date().toISOString(),
    server: 'AWS EKS - eu-north-1'
  });
});

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
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

    // Record metrics
    paymentCounter.labels(currency, 'success').inc();
    paymentAmount.observe(parseFloat(amount));

    console.log('💳 Payment saved: ' + currency + ' ' + amount);
    res.status(201).json(result.rows[0]);
  } catch (err) {
    paymentCounter.labels(currency || 'unknown', 'failed').inc();
    res.status(500).json({ error: err.message });
  }
});

app.delete('/transactions', async (req, res) => {
  try {
    await pool.query('DELETE FROM transactions');
    res.json({ message: 'All transactions cleared' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(3000, () => {
  console.log('✅ Payment API v4.0 running - Prometheus metrics enabled 📊');
});
