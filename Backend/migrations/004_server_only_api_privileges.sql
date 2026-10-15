-- SceneMe is a server-only PostgreSQL application. The iOS app never
-- accesses SceneMe tables through Supabase's anon/authenticated API keys.
-- Prevent public Supabase API roles from accessing raw user, subscription and
-- generated media metadata. PostgreSQL CI may not define these roles.
do $sceneme_access$
declare
  client_role text;
begin
  foreach client_role in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = client_role) then
      execute format('revoke all privileges on all tables in schema public from %I', client_role);
      execute format('revoke all privileges on all sequences in schema public from %I', client_role);
      execute format('alter default privileges in schema public revoke all privileges on tables from %I', client_role);
      execute format('alter default privileges in schema public revoke all privileges on sequences from %I', client_role);
    end if;
  end loop;
end
$sceneme_access$;
