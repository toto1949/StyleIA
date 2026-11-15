-- Keep relocatable extensions outside the API-exposed public schema.
create schema if not exists extensions;
alter extension citext set schema extensions;
