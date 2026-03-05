const express = require('express');
const app = express();
app.use(express.json());

const transactions = [];

app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'payment-api',
    timestamp: new Date().toISOString(),
    server: 'AWS EC2 - us-east-1'
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
  console.log(`💳 Payment processed: ${currency} ${amount}`);
  res.status(201).json(transaction);
});

app.listen(3000, () => {
  console.log('✅ Payment API running on port 3000');
});
