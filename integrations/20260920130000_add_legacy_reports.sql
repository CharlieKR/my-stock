-- One-time historical import. Contains daily observations, never monthly results.
begin;
create table reporting.legacy_reports (
  investment text not null check (investment in ('SOXL','HYXL')),
  business_date date not null,
  payload jsonb not null check (jsonb_typeof(payload)='object'),
  imported_at timestamptz not null default now(),
  primary key (investment,business_date)
);
alter table reporting.legacy_reports enable row level security;
grant select on reporting.legacy_reports to my_stock_reader;
create policy reader_legacy on reporting.legacy_reports for select to my_stock_reader using(true);
commit;
