-- SentinelPay seed fixtures
-- Schema and demo data for local development.

CREATE TABLE IF NOT EXISTS users (
    id              SERIAL PRIMARY KEY,
    email           VARCHAR(255) UNIQUE NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,
    full_name       VARCHAR(255),
    role            VARCHAR(50) DEFAULT 'merchant',
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS accounts (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER REFERENCES users(id),
    account_number  VARCHAR(20) UNIQUE NOT NULL,
    currency        VARCHAR(3) DEFAULT 'NGN',
    balance         NUMERIC(18, 2) DEFAULT 0.00,
    status          VARCHAR(20) DEFAULT 'active',
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS transactions (
    id              SERIAL PRIMARY KEY,
    account_id      INTEGER REFERENCES accounts(id),
    reference       VARCHAR(64) UNIQUE NOT NULL,
    amount          NUMERIC(18, 2) NOT NULL,
    currency        VARCHAR(3) DEFAULT 'NGN',
    direction       VARCHAR(10) NOT NULL, -- 'credit' or 'debit'
    counterparty    VARCHAR(255),
    description     VARCHAR(500),
    status          VARCHAR(20) DEFAULT 'completed',
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS kyc_records (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER REFERENCES users(id),
    bvn             VARCHAR(11),
    nin             VARCHAR(11),
    document_url    VARCHAR(500),
    verification_status VARCHAR(20) DEFAULT 'pending',
    submitted_at    TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS webhooks (
    id              SERIAL PRIMARY KEY,
    user_id         INTEGER REFERENCES users(id),
    callback_url    VARCHAR(500) NOT NULL,
    event_type      VARCHAR(50),
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id          SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  VARCHAR(128) UNIQUE NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at  TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id
    ON refresh_tokens(user_id);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_at
    ON refresh_tokens(expires_at);