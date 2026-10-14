alter table generation_jobs
  add column if not exists credit_cost integer not null default 0 check (credit_cost >= 0),
  add column if not exists credit_refunded boolean not null default false;

create table if not exists credit_accounts (
  user_id uuid primary key references users(id) on delete cascade,
  balance integer not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists credit_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  grant_key text not null,
  source_type text not null check (source_type in ('starter', 'subscription', 'adjustment')),
  tier text not null check (tier in ('free', 'creator', 'pro')),
  amount integer not null check (amount > 0),
  product_id text,
  transaction_id text,
  grant_period_start timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, grant_key)
);

create index if not exists credit_grants_user_created_idx
  on credit_grants (user_id, created_at desc);

create table if not exists credit_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  grant_id uuid references credit_grants(id) on delete set null,
  job_public_id uuid,
  event_type text not null check (event_type in ('grant', 'debit', 'refund', 'adjustment')),
  operation text,
  amount integer not null check (amount <> 0),
  balance_after integer not null check (balance_after >= 0),
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create index if not exists credit_ledger_user_created_idx
  on credit_ledger (user_id, created_at desc);
create index if not exists credit_ledger_job_idx
  on credit_ledger (job_public_id) where job_public_id is not null;

comment on table credit_grants is
  'Non-expiring SceneMe allowance grants. Subscription products issue one grant per subscription month.';
