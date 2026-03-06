const express = require('express');
const { Pool } = require('pg');
require('dotenv').config();

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

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'payment-api',
    version: '3.0.0',
    database: 'PostgreSQL RDS',
    deployment: 'GitHub Actions CI/CD ⚙️',
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

app.delete('/transactions', async (req, res) => {
  try {
    await pool.query('DELETE FROM transactions');
    res.json({ message: 'All transactions cleared' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(3000, () => {
  console.log('✅ Payment API v3.0 running - Deployed by GitHub Actions');
});
