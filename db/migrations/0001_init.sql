-- 0001_init.sql
-- Initial schema for conversion jobs service with transactional outbox.
-- Includes improvements / fixes over proposed draft.

-- Enable UUID generator (pgcrypto provides gen_random_uuid())
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ========================
-- ENUMS (Note: adding new values requires ALTER TYPE ... ADD VALUE)
-- Consider lookup tables if frequent change is expected.
-- ========================
DO $$ BEGIN
    CREATE TYPE job_status_enum AS ENUM ('queued','in_progress','completed','failed','cancelled');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
    CREATE TYPE micro_order_status_enum AS ENUM ('pending','in_progress','done','failed','cancelled');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- ========================
-- Helper function to manage updated_at
-- ========================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;$$ LANGUAGE plpgsql;

-- ========================
-- conversion_jobs
-- ========================
CREATE TABLE IF NOT EXISTS conversion_jobs (
  job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id TEXT NOT NULL,
  source_currency CHAR(3) NOT NULL CHECK (source_currency ~ '^[A-Z]{3}$'),
  target_currency CHAR(3) NOT NULL CHECK (target_currency ~ '^[A-Z]{3}$'),
  source_amount NUMERIC(20,8) NOT NULL CHECK (source_amount > 0),
  status job_status_enum NOT NULL DEFAULT 'queued',
  idempotency_key TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes / constraints
CREATE INDEX IF NOT EXISTS idx_conversion_jobs_status ON conversion_jobs (status);
CREATE INDEX IF NOT EXISTS idx_conversion_jobs_client ON conversion_jobs (client_id);
CREATE INDEX IF NOT EXISTS idx_conversion_jobs_client_created_at ON conversion_jobs (client_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_conversion_jobs_idempotency_key ON conversion_jobs (idempotency_key) WHERE idempotency_key IS NOT NULL;

COMMENT ON TABLE conversion_jobs IS 'Canonical request/job record. Inserted with outbox row for reconciliation and status tracking.';

-- Trigger for updated_at
DO $$ BEGIN
  CREATE TRIGGER trg_conversion_jobs_updated_at BEFORE UPDATE ON conversion_jobs
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- ========================
-- outbox (transactional outbox table)
-- ========================
CREATE TABLE IF NOT EXISTS outbox (
  outbox_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  aggregate_type TEXT NOT NULL,
  aggregate_id UUID, -- optional, references a domain aggregate
  topic TEXT NOT NULL,
  payload JSONB NOT NULL,
  attempts INT NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error TEXT,
  locked_until TIMESTAMPTZ,
  locked_by TEXT,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_outbox_unsent_created ON outbox (created_at) WHERE processed_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_outbox_locked_until ON outbox (locked_until) WHERE processed_at IS NULL;
-- NOTE: Removed invalid partial index that referenced now() (volatile, cannot be in index predicate).
-- Replacement index supports queries filtering processed_at IS NULL and ordering / filtering by locked_until then created_at.
CREATE INDEX IF NOT EXISTS idx_outbox_unprocessed_lock ON outbox (locked_until, created_at) WHERE processed_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_outbox_topic_unsent ON outbox (topic, created_at) WHERE processed_at IS NULL;

COMMENT ON TABLE outbox IS 'Transactional outbox. Publisher claims unsent rows (processed_at IS NULL) via locked_until, sends to SQS, marks processed_at.';

-- ========================
-- micro_orders (execution splits)
-- ========================
CREATE TABLE IF NOT EXISTS micro_orders (
  micro_order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES conversion_jobs(job_id) ON DELETE CASCADE,
  notional NUMERIC(20,8) NOT NULL CHECK (notional > 0),
  status micro_order_status_enum NOT NULL DEFAULT 'pending',
  provider TEXT,
  attempts INT NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  provider_ref TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_micro_orders_job ON micro_orders (job_id);
CREATE INDEX IF NOT EXISTS idx_micro_orders_status ON micro_orders (status);
CREATE INDEX IF NOT EXISTS idx_micro_orders_job_status ON micro_orders (job_id, status);

COMMENT ON TABLE micro_orders IS 'Each micro-order is a slice of the parent conversion job. Updated as provider executions proceed.';

DO $$ BEGIN
  CREATE TRIGGER trg_micro_orders_updated_at BEFORE UPDATE ON micro_orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- ========================
-- trade_ledger (append-only executed trades)
-- ========================
CREATE TABLE IF NOT EXISTS trade_ledger (
  trade_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID REFERENCES conversion_jobs(job_id) ON DELETE SET NULL,
  micro_order_id UUID REFERENCES micro_orders(micro_order_id) ON DELETE SET NULL,
  provider TEXT NOT NULL,
  executed_notional NUMERIC(20,8) NOT NULL CHECK (executed_notional > 0),
  executed_amount_target NUMERIC(20,8) NOT NULL CHECK (executed_amount_target >= 0),
  rate NUMERIC(30,12) NOT NULL CHECK (rate > 0),
  fee NUMERIC(20,8) NOT NULL DEFAULT 0 CHECK (fee >= 0),
  provider_ref TEXT,
  executed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trade_ledger_job ON trade_ledger (job_id);
CREATE INDEX IF NOT EXISTS idx_trade_ledger_executed_at ON trade_ledger (executed_at);
CREATE UNIQUE INDEX IF NOT EXISTS ux_trade_ledger_provider_ref ON trade_ledger (provider, provider_ref) WHERE provider_ref IS NOT NULL;

COMMENT ON TABLE trade_ledger IS 'Immutable executed trade records. Append-only; corrections via new compensating rows.';

-- ========================
-- Notes:
-- * Future partitioning: convert trade_ledger to PARTITION BY RANGE (executed_at) if volume large.
-- * Consider moving enums to separate lookup tables for more agile status changes.
-- * If you rarely delete jobs, prefer ON DELETE RESTRICT to preserve referential integrity strictly.
-- * Add auditing (session_user, trace ids) via additional columns or separate audit table if needed.
