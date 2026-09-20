-- Additive My Stock reporting storage. Does not alter trading tables or cron.
begin;
create schema if not exists reporting;
revoke all on schema reporting from public, anon, authenticated;
create table reporting.publication_batches (
  revision bigint generated always as identity primary key,
  investment text not null check (investment in ('SOXL','HYXL')),
  portfolio_id text not null,
  business_date date not null,
  stage text not null check (stage in ('plan','execution','settled','closed')),
  captured_at timestamptz not null,
  content_hash text not null,
  payload jsonb not null check (jsonb_typeof(payload)='object'),
  created_at timestamptz not null default now(),
  unique (investment,portfolio_id,business_date,stage,content_hash)
);
create index on reporting.publication_batches(investment,portfolio_id,business_date,stage,captured_at desc);
alter table reporting.publication_batches enable row level security;
create table reporting.fx_rates (
  rate_date date primary key,
  usd_krw numeric(24,10) not null check(usd_krw>0),
  provider text not null,
  available_at timestamptz not null,
  updated_at timestamptz not null default now()
);
alter table reporting.fx_rates enable row level security;
do $$ begin
  if not exists(select 1 from pg_roles where rolname='my_stock_reader') then
    create role my_stock_reader login nosuperuser nocreatedb nocreaterole noinherit;
  end if;
  if not exists(select 1 from pg_roles where rolname='my_stock_fx_writer') then
    create role my_stock_fx_writer login nosuperuser nocreatedb nocreaterole noinherit;
  end if;
end $$;
grant usage on schema reporting to my_stock_reader, my_stock_fx_writer;
grant select on reporting.publication_batches, reporting.fx_rates to my_stock_reader;
create policy reader_batches on reporting.publication_batches for select to my_stock_reader using(true);
create policy reader_fx on reporting.fx_rates for select to my_stock_reader using(true);
grant select,insert,update on reporting.fx_rates to my_stock_fx_writer;
create policy writer_fx on reporting.fx_rates for all to my_stock_fx_writer using(true) with check(true);
-- Writer RPC exposes no read API and accepts only the reporting contract.
create or replace function public.my_stock_publish(batch jsonb) returns bigint
language plpgsql security definer set search_path='' as $$
declare result bigint; previous jsonb;
begin
  if batch->>'schemaVersion' is distinct from '2'
     or coalesce(batch->>'portfolioId','')=''
     or jsonb_typeof(batch->'cashEvents') is distinct from 'array'
     or jsonb_typeof(batch->'details') is distinct from 'array' then
    raise exception 'Invalid reporting batch';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(concat(batch->>'investment',batch->>'portfolioId',batch->>'date',batch->>'stage')));
  select payload,revision into previous,result from reporting.publication_batches
    where investment=batch->>'investment' and portfolio_id=batch->>'portfolioId'
      and business_date=(batch->>'date')::date and stage=batch->>'stage'
    order by captured_at desc,revision desc limit 1;
  if previous - 'capturedAt' = batch - 'capturedAt' then return result; end if;
  insert into reporting.publication_batches(investment,portfolio_id,business_date,stage,captured_at,content_hash,payload)
  values(batch->>'investment',batch->>'portfolioId',(batch->>'date')::date,batch->>'stage',
    (batch->>'capturedAt')::timestamptz,md5(batch::text),batch)
  on conflict(investment,portfolio_id,business_date,stage,content_hash)
  do update set content_hash=excluded.content_hash
  returning revision into result;
  return result;
end $$;
revoke all on function public.my_stock_publish(jsonb) from public,anon,authenticated;
grant execute on function public.my_stock_publish(jsonb) to service_role;
commit;
