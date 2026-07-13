-- ============================================================================
-- TIGER WALLET — Supabase PostgreSQL Schema
-- Run this entire file in the Supabase SQL Editor (Project -> SQL Editor -> New Query)
-- ============================================================================

-- Enable UUID generation (usually already enabled on Supabase, safe to re-run)
create extension if not exists "uuid-ossp";

-- ----------------------------------------------------------------------------
-- TABLE: users
-- One row per authenticated user. id maps 1:1 to auth.users.id
-- ----------------------------------------------------------------------------
create table if not exists public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  budget_threshold numeric(12, 2) not null default 1000.00,
  parent_personality text not null default 'Strict', -- 'Strict' | 'Skeptical' | 'Passive-Aggressive' etc.
  created_at timestamptz not null default now()
);

comment on table public.users is 'Extended profile data for each Tiger Wallet user, one-to-one with auth.users';

-- ----------------------------------------------------------------------------
-- TABLE: transactions
-- Every spend/save entry logged by the user, later annotated by the AI.
-- ----------------------------------------------------------------------------
create table if not exists public.transactions (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.users (id) on delete cascade,
  amount numeric(12, 2) not null,
  category text not null,
  timestamp timestamptz not null default now(),
  ai_feedback text, -- nullable: filled in asynchronously after the Groq call returns
  created_at timestamptz not null default now()
);

comment on table public.transactions is 'Individual transactions; ai_feedback is populated after the Groq critique completes';

-- Helpful index for the "monthly spend" aggregate query the app runs constantly
create index if not exists idx_transactions_user_timestamp
  on public.transactions (user_id, timestamp desc);

-- ----------------------------------------------------------------------------
-- FUNCTION + TRIGGER: auto-create a `public.users` row whenever someone signs up
-- This means the app never has to manually INSERT into `users` after signup.
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, budget_threshold, parent_personality)
  values (new.id, 1000.00, 'Strict')
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================================
-- ROW LEVEL SECURITY
-- Every user may only ever read/write their own rows. This is critical:
-- without RLS, any authenticated user could query another user's financial data.
-- ============================================================================

alter table public.users enable row level security;
alter table public.transactions enable row level security;

-- ----- users policies -----

drop policy if exists "Users can view own profile" on public.users;
create policy "Users can view own profile"
  on public.users for select
  using (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.users;
create policy "Users can update own profile"
  on public.users for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Insert is normally handled by the trigger (security definer), but keep a
-- policy in place in case the client ever needs to upsert its own row.
drop policy if exists "Users can insert own profile" on public.users;
create policy "Users can insert own profile"
  on public.users for insert
  with check (auth.uid() = id);

-- ----- transactions policies -----

drop policy if exists "Users can view own transactions" on public.transactions;
create policy "Users can view own transactions"
  on public.transactions for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own transactions" on public.transactions;
create policy "Users can insert own transactions"
  on public.transactions for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own transactions" on public.transactions;
create policy "Users can update own transactions"
  on public.transactions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete own transactions" on public.transactions;
create policy "Users can delete own transactions"
  on public.transactions for delete
  using (auth.uid() = user_id);

-- ============================================================================
-- REALTIME
-- Enable realtime replication on transactions so the Flutter app can subscribe
-- and catch the ai_feedback UPDATE the instant Groq's critique lands.
-- ============================================================================
alter publication supabase_realtime add table public.transactions;
