create extension if not exists citext;
create extension if not exists pgcrypto;

create table if not exists schema_migrations (
  version text primary key,
  checksum text not null,
  applied_at timestamptz not null default now()
);

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  email citext,
  full_name text not null default '',
  password_hash text,
  password_salt text,
  token_version bigint not null default 0,
  status text not null default 'active'
    check (status in ('active', 'suspended', 'deletion_pending')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists users_active_email_idx
  on users (email)
  where email is not null and deleted_at is null;

create table if not exists auth_identities (
  id bigint generated always as identity primary key,
  user_id uuid not null references users(id) on delete cascade,
  provider text not null check (provider in ('apple', 'google')),
  provider_subject text not null,
  provider_email citext,
  email_verified boolean not null default false,
  encrypted_refresh_token text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, provider_subject),
  unique (user_id, provider)
);

create index if not exists auth_identities_user_id_idx on auth_identities (user_id);

create table if not exists sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  refresh_token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  last_used_at timestamptz not null default now()
);

create index if not exists sessions_user_active_idx
  on sessions (user_id, expires_at)
  where revoked_at is null;

create table if not exists uploads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  storage_key text not null unique,
  purpose text not null default 'subject'
    check (purpose in ('subject', 'companion')),
  status text not null default 'pending'
    check (status in ('pending', 'uploaded', 'validated', 'rejected', 'deleted')),
  content_type text not null default 'image/jpeg',
  size_bytes bigint not null default 0 check (size_bytes >= 0),
  width integer check (width is null or width > 0),
  height integer check (height is null or height > 0),
  sha256 text,
  expires_at timestamptz,
  validated_at timestamptz,
  deleted_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists uploads_user_created_idx on uploads (user_id, created_at desc);
create index if not exists uploads_pending_expiry_idx on uploads (expires_at)
  where status = 'pending';

create table if not exists generation_jobs (
  id uuid primary key default gen_random_uuid(),
  public_id uuid not null unique default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  parent_job_id uuid references generation_jobs(id) on delete set null,
  subject_upload_id uuid references uploads(id) on delete restrict,
  companion_upload_id uuid references uploads(id) on delete restrict,
  kind text not null check (kind in ('image', 'video')),
  operation text not null check (operation in ('generate', 'reroll', 'video')),
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed', 'cancel_requested', 'cancelled', 'dead_letter')),
  progress smallint not null default 0 check (progress between 0 and 100),
  idempotency_key text,
  provider text,
  provider_request_id text,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 3 check (max_attempts between 1 and 10),
  available_at timestamptz not null default now(),
  lease_owner text,
  leased_until timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  error_code text,
  error_message text,
  estimated_cost_usd numeric(12,6) not null default 0,
  actual_cost_usd numeric(12,6),
  request_payload jsonb not null default '{}'::jsonb,
  response_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, operation, idempotency_key)
);

create index if not exists generation_jobs_user_history_idx
  on generation_jobs (user_id, created_at desc, id desc);
create index if not exists generation_jobs_claim_idx
  on generation_jobs (available_at, created_at)
  where status in ('pending', 'processing');
create index if not exists generation_jobs_parent_idx on generation_jobs (parent_job_id);
create index if not exists generation_jobs_subject_upload_idx on generation_jobs (subject_upload_id);
create index if not exists generation_jobs_companion_upload_idx on generation_jobs (companion_upload_id)
  where companion_upload_id is not null;
create unique index if not exists generation_jobs_provider_request_idx
  on generation_jobs (provider, provider_request_id)
  where provider_request_id is not null;

create table if not exists generation_results (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references generation_jobs(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  kind text not null check (kind in ('image', 'video', 'audio')),
  storage_key text not null unique,
  content_type text not null,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  width integer,
  height integer,
  duration_ms integer,
  sha256 text,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists generation_results_job_idx on generation_results (job_id);
create index if not exists generation_results_user_created_idx
  on generation_results (user_id, created_at desc)
  where deleted_at is null;

create table if not exists usage_counters (
  user_id uuid not null references users(id) on delete cascade,
  period_start date not null,
  image_generations integer not null default 0 check (image_generations >= 0),
  video_generations integer not null default 0 check (video_generations >= 0),
  estimated_cost_usd numeric(12,6) not null default 0 check (estimated_cost_usd >= 0),
  actual_cost_usd numeric(12,6) not null default 0 check (actual_cost_usd >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, period_start)
);

create table if not exists subscription_entitlements (
  user_id uuid primary key references users(id) on delete cascade,
  tier text not null default 'free' check (tier in ('free', 'creator', 'pro')),
  product_id text,
  original_transaction_id text unique,
  environment text check (environment is null or environment in ('Sandbox', 'Production', 'Xcode')),
  status text not null default 'inactive'
    check (status in ('inactive', 'active', 'grace_period', 'billing_retry', 'expired', 'revoked', 'refunded')),
  expires_at timestamptz,
  grace_period_expires_at timestamptz,
  last_transaction_id text,
  last_verified_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists app_store_transactions (
  transaction_id text primary key,
  original_transaction_id text not null,
  user_id uuid references users(id) on delete set null,
  app_account_token uuid,
  product_id text not null,
  environment text not null check (environment in ('Sandbox', 'Production', 'Xcode')),
  purchased_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  revocation_reason integer,
  is_upgraded boolean not null default false,
  signed_transaction text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists app_store_transactions_original_idx
  on app_store_transactions (original_transaction_id, expires_at desc);
create index if not exists app_store_transactions_user_idx
  on app_store_transactions (user_id, expires_at desc);

create table if not exists app_store_notifications (
  notification_uuid uuid primary key,
  notification_type text not null,
  subtype text,
  environment text,
  signed_date timestamptz,
  signed_payload text not null,
  processing_status text not null default 'received'
    check (processing_status in ('received', 'processed', 'failed')),
  error_message text,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);

create index if not exists app_store_notifications_unprocessed_idx
  on app_store_notifications (received_at)
  where processing_status in ('received', 'failed');

create table if not exists job_events (
  id bigint generated always as identity primary key,
  job_id uuid not null references generation_jobs(id) on delete cascade,
  event_type text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists job_events_job_created_idx on job_events (job_id, created_at);
