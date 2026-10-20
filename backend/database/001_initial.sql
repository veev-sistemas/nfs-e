BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(trim(name)) > 0),
  document varchar(14) NOT NULL UNIQUE CHECK (document ~ '^[0-9]{14}$'),
  created_at timestamptz NOT NULL DEFAULT now()
);
-- Provisionamento administrativo: nunca disponibilizar a chave no navegador.
CREATE TABLE api_keys (
  token_hash text PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES companies(id),
  active boolean NOT NULL DEFAULT true
);
CREATE TABLE fiscal_defaults (
  company_id uuid PRIMARY KEY REFERENCES companies(id),
  settings jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(settings) = 'object'),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  name text NOT NULL CHECK (length(trim(name)) > 0),
  document text NOT NULL CHECK (document ~ '^([0-9]{11}|[0-9]{14})$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, document),
  UNIQUE (company_id, id)
);
CREATE TABLE drafts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id),
  customer_id uuid NOT NULL,
  amount_cents bigint NOT NULL CHECK (amount_cents > 0),
  settings_snapshot jsonb NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status = 'draft'),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (company_id, customer_id) REFERENCES customers(company_id, id)
);
CREATE INDEX drafts_company_created ON drafts(company_id, created_at DESC);
COMMIT;
