-- 0002_accounts_ledger.sql
-- Adds accounts & ledger_entries for double-entry accounting and enriches conversion_jobs.

BEGIN;

-- Enum for ledger entry direction
DO $$ BEGIN
    CREATE TYPE entry_type_enum AS ENUM ('debit','credit');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Accounts table (one per user per currency)
CREATE TABLE IF NOT EXISTS accounts (
  account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  currency CHAR(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  balance NUMERIC(20,8) NOT NULL DEFAULT 0 CHECK (balance >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, currency)
);

-- Reuse existing updated_at trigger function
DO $$ BEGIN
  CREATE TRIGGER trg_accounts_updated_at BEFORE UPDATE ON accounts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_accounts_user ON accounts(user_id);

-- Ledger entries (double-entry). We store positive amount + entry_type.
CREATE TABLE IF NOT EXISTS ledger_entries (
  entry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID REFERENCES conversion_jobs(job_id) ON DELETE SET NULL,
  account_id UUID NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
  entry_type entry_type_enum NOT NULL,
  amount NUMERIC(20,8) NOT NULL CHECK (amount > 0),
  currency CHAR(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ledger_account ON ledger_entries(account_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ledger_job ON ledger_entries(job_id);
CREATE INDEX IF NOT EXISTS idx_ledger_currency ON ledger_entries(currency);

COMMENT ON TABLE accounts IS 'Per-user per-currency balances. Enforced unique(user_id,currency).';
COMMENT ON TABLE ledger_entries IS 'Double-entry accounting movements. Positive amount tagged by debit/credit.';

-- Enrich conversion_jobs with execution details if not present
DO $$ BEGIN ALTER TABLE conversion_jobs ADD COLUMN target_amount NUMERIC(20,8); EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE conversion_jobs ADD COLUMN rate NUMERIC(30,12); EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE conversion_jobs ADD COLUMN fee NUMERIC(20,8); EXCEPTION WHEN duplicate_column THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE conversion_jobs ADD COLUMN completed_at TIMESTAMPTZ; EXCEPTION WHEN duplicate_column THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_conversion_jobs_completed_at ON conversion_jobs(completed_at);

COMMIT;
