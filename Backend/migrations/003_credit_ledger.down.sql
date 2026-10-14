drop table if exists credit_ledger;
drop table if exists credit_grants;
drop table if exists credit_accounts;
alter table generation_jobs drop column if exists credit_refunded;
alter table generation_jobs drop column if exists credit_cost;
