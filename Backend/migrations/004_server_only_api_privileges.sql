-- SceneMe API is the only database client. Its iOS app never connects to
-- Supabase PostgREST or sends an anon/authenticated Supabase key. Do not expose
-- customer profiles, credentials, media metadata, or purchase records to
-- public Supabase API roles.
--
-- Keep server-side migrations / the direct Postgres connection available.
-- This is intentionally a privilege lockdown, not an RLS policy replacement:
-- enabling RLS without an appropriate owner/access policy can break clients.
revoke all privileges on all tables in schema public from anon, authenticated;
revoke all privileges on all sequences in schema public from anon, authenticated;

-- Future migrations should not automatically grant public client access.
alter default privileges for role postgres in schema public
  revoke all privileges on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all privileges on sequences from anon, authenticated;
