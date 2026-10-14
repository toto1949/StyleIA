create table if not exists rate_limit_windows (
  scope text not null,
  subject_hash text not null check (length(subject_hash) = 64),
  window_start timestamptz not null,
  request_count integer not null default 1 check (request_count > 0),
  expires_at timestamptz not null,
  primary key (scope, subject_hash, window_start)
);

create index if not exists rate_limit_windows_expiry_idx
  on rate_limit_windows (expires_at);
