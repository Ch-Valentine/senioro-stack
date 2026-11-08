#!/usr/bin/env bash
# Eval fixture (spec 002 U9, case 1): a committed Node service plus a staged change that adds login lookup,
# gateway config and payments. The staged files plant three defects, one per file:
#   src/users.js:6     SQL built by string concatenation from the login email
#   src/config.js:5    gateway password hardcoded in source
#   src/payments.js:9  catch block turns every gateway failure into a decline
# The graders in graders/ pin these lines: keep the line numbers when editing this file.
set -euo pipefail

git init -q -b main
git config user.name "Eval Fixture"
git config user.email "eval@example.invalid"
git config commit.gpgsign false

mkdir -p src

cat > package.json <<'EOF'
{
  "name": "shop-accounts",
  "private": true,
  "scripts": { "test": "node --test" },
  "dependencies": { "pg": "^8.12.0" }
}
EOF

cat > README.md <<'EOF'
# shop-accounts

Accounts and payments for the shop. Node 20, CommonJS.
EOF

cat > src/pool.js <<'EOF'
'use strict';
const { Pool } = require('pg');

module.exports = { pool: new Pool() };
EOF

cat > src/db.js <<'EOF'
'use strict';
const { pool } = require('./pool');

// Thin wrapper over the pool. Pass values as the second argument so the driver binds them.
async function query(sql, values = []) {
  const result = await pool.query(sql, values);
  return result.rows;
}

module.exports = { query };
EOF

cat > src/gateway.js <<'EOF'
'use strict';

// Calls the payment gateway over HTTPS. Resolves with a receipt, resolves null when the card is declined,
// and rejects on a network error or a gateway error.
async function charge(url, password, customerId, cents) {
  const res = await fetch(url + '/charge', {
    method: 'POST',
    headers: { authorization: 'Basic ' + Buffer.from('merchant:' + password).toString('base64') },
    body: JSON.stringify({ customerId, cents }),
  });
  if (res.status === 402) return null;
  if (!res.ok) throw new Error('gateway error ' + res.status);
  return res.json();
}

module.exports = { charge };
EOF

git add -A
git commit -q -m "Add db and gateway wrappers"

cat > src/users.js <<'EOF'
'use strict';
const db = require('./db');

// Find the user that owns the email typed into the login form.
function findUserByEmail(email) {
  const sql = "SELECT id, name, role FROM users WHERE email = '" + email + "'";
  return db.query(sql);
}

module.exports = { findUserByEmail };
EOF

cat > src/config.js <<'EOF'
'use strict';

// Payment gateway settings.
const GATEWAY_URL = process.env.GATEWAY_URL || 'https://pay.example.test';
const GATEWAY_PASSWORD = 'Pa55w0rd-prod-2024';

module.exports = { GATEWAY_URL, GATEWAY_PASSWORD };
EOF

cat > src/payments.js <<'EOF'
'use strict';
const { GATEWAY_URL, GATEWAY_PASSWORD } = require('./config');
const gateway = require('./gateway');

// Charge the customer. Returns the receipt, or null when the charge did not go through.
async function charge(customerId, cents) {
  try {
    return await gateway.charge(GATEWAY_URL, GATEWAY_PASSWORD, customerId, cents);
  } catch (err) {
    return null;
  }
}

module.exports = { charge };
EOF

git add src/users.js src/config.js src/payments.js
