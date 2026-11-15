-- Defense in depth for SceneMe's server-only database.
--
-- The iOS client never queries these tables through Supabase Data APIs.
-- Migration 004 revokes all table and sequence privileges from Supabase's
-- anon/authenticated roles. Enabling RLS with no client policies prevents a
-- future privilege grant from exposing rows accidentally. The Render backend
-- connects as the database owner and therefore continues to operate normally.

alter table public.schema_migrations enable row level security;
alter table public.users enable row level security;
alter table public.auth_identities enable row level security;
alter table public.sessions enable row level security;
alter table public.uploads enable row level security;
alter table public.generation_jobs enable row level security;
alter table public.generation_results enable row level security;
alter table public.usage_counters enable row level security;
alter table public.subscription_entitlements enable row level security;
alter table public.app_store_transactions enable row level security;
alter table public.app_store_notifications enable row level security;
alter table public.job_events enable row level security;
alter table public.rate_limit_windows enable row level security;
alter table public.credit_accounts enable row level security;
alter table public.credit_grants enable row level security;
alter table public.credit_ledger enable row level security;
