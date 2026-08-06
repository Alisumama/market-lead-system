-- Run this once in the Supabase project's SQL editor (Dashboard -> SQL Editor -> New query).
--
-- This table is the human-editable allowlist: "which emails may currently see
-- the dashboard." It is deliberately separate from Supabase's own
-- auth.users table so that:
--   - revoking someone is one DELETE here, no need to touch their account
--   - you can see/manage the whole approved list in one place
--   - it's checked on every dashboard request as a second, independent gate
--     on top of Supabase Auth itself (see web/SETUP.md, step "Disable public
--     signups", for the first gate).
create table if not exists public.allowed_emails (
  email       text primary key,        -- always stored lowercase, see check below
  label       text,                    -- optional: "Bob - Sales" etc, for your own notes
  added_at    timestamptz not null default now(),
  constraint allowed_emails_lowercase check (email = lower(email))
);

-- Row Level Security ON with NO policies defined = nobody using the public
-- "anon" or "authenticated" API keys can read or write this table at all,
-- from the browser, no matter who they're logged in as. Only server-side
-- code using the SERVICE ROLE key (never shipped to the browser) can touch
-- it — which is exactly what web/lib/auth.js and invite_colleague.py do.
alter table public.allowed_emails enable row level security;

-- Seed with your initial approved colleagues. Edit this list, or just use
-- `python invite_colleague.py <email>` afterwards (it inserts here AND sends
-- the Supabase invite in one step, which is the safer way to add people day
-- to day since it can't leave one half of the setup incomplete).
-- insert into public.allowed_emails (email, label) values
--   ('you@example.com', 'Admin'),
--   ('colleague@example.com', 'Colleague');
