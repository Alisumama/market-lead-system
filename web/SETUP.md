# Setup guide — private dashboard auth gate

This wraps an invite-only login in front of `dashboard.html` so it can be
published online without exposing lead data to anyone but you and the
colleagues you explicitly approve.

**How it works, in one paragraph:** the real `dashboard.html` (built daily by
`build_dashboard.py`) is uploaded by `deploy_dashboard.py` into a **private**
Supabase Storage bucket — not a public URL. A small server-side function on
Vercel (`web/api/dashboard.js`) is the *only* thing that can read that
bucket. Every request to it first verifies the visitor's session directly
against Supabase (not just "a cookie is present") and then checks their
email against the `allowed_emails` table. Both checks must pass before a
single byte of the HTML is read from storage, let alone sent to the browser.
Sign-in is email + password only. Public sign-up is disabled at the
Supabase project level, so nothing — not the UI, not a direct API call using
the public anon key — can ever create a new account by itself; only
`invite_colleague.py`, run by you, can do that.

Steps 1–6 happen in web browsers (Supabase, Vercel dashboards) — nobody but
you can click through those, so they're written as a checklist. Steps 7+
are commands you run locally.

---

## 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) → sign up / sign in → **New project**.
2. Pick any name (e.g. `bastak-leads`) and a strong database password (store
   it somewhere safe — you likely won't need it again, Supabase manages the
   connection for you).
3. Wait for provisioning (~2 min).

## 2. Run the allowlist schema

1. In the Supabase dashboard: **SQL Editor** → **New query**.
2. Paste the contents of [`web/supabase/schema.sql`](supabase/schema.sql) and click **Run**.
3. This creates the `allowed_emails` table with Row Level Security on and no
   policies — meaning nothing reachable from a browser can read or write it,
   only server-side code using the service role key.

## 3. Create the private storage bucket

1. **Storage** (left sidebar) → **New bucket**.
2. Name: `dashboard-private` (or pick your own name — if you do, set
   `SUPABASE_DASHBOARD_BUCKET` in `.env` to match).
3. **Leave "Public bucket" turned OFF.** This is the setting that keeps the
   file itself unreachable by direct URL — everything else in this system
   depends on that being off.

## 4. Disable public sign-up (the critical toggle)

1. **Authentication** → **Sign In / Providers** (or **Authentication →
   Settings**, depending on the Supabase UI version you're on) → find **"Allow
   new users to sign up"** and turn it **OFF**.
2. This is the setting that actually stops self-registration — not just the
   absence of a signup button in the UI. The public `anon` key ships in the
   browser by design (that's how Supabase auth works), so without this
   toggle off, anyone could still call Supabase's sign-up API directly and
   create an account even though the login page never offers that option.
   With it off, the only way an account can ever be created is
   `invite_colleague.py`, run by you.

## 5. Set your site's redirect URLs

1. **Authentication → URL Configuration**.
2. **Site URL**: your eventual Vercel URL, e.g. `https://bastak-leads.vercel.app`
   (you'll get the exact URL in step 7 — you can come back and fix this
   after deploying once; it's fine to put a placeholder for now).
3. **Redirect URLs**: add `https://<your-site>/login` and
   `https://<your-site>/set-password` (both the invite-acceptance and
   password-reset links land on `/set-password`).

## 6. Get your API keys

**Settings → API**. You need three values:

| Value | Where | Used by |
|---|---|---|
| Project URL | "Project URL" | everything |
| `anon` `public` key | "Project API keys" | the browser (login page) — safe to expose |
| `service_role` key | "Project API keys" (click to reveal) | server-only — Vercel functions, `invite_colleague.py`, `deploy_dashboard.py`. **Never put this anywhere a browser can read it.** |

Add to your project's **`.env`** (repo root, already git-ignored):

```
SUPABASE_URL=https://<your-project-ref>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<the service_role key>
```

(`SUPABASE_ANON_KEY` is *not* needed in `.env` — the Vercel deployment gets
it directly as a Vercel environment variable in step 7, since that's what
serves it to the browser.)

---

## 7. Deploy to Vercel

From the `web/` folder:

```sh
cd web
npm install
npx vercel login          # first time only
npx vercel link           # creates/links a Vercel project for this folder
```

Set the environment variables Vercel needs (server-side only — none of these
end up in browser-visible code):

```sh
npx vercel env add SUPABASE_URL
npx vercel env add SUPABASE_ANON_KEY
npx vercel env add SUPABASE_SERVICE_ROLE_KEY
```

(You can also set these in the Vercel dashboard: **Project → Settings →
Environment Variables** — same effect, some people find the UI easier.)

Deploy:

```sh
npx vercel deploy --prod
```

Vercel prints your live URL (e.g. `https://bastak-leads.vercel.app`). Go
back to Supabase (**Authentication → URL Configuration**, step 5) and put
the *real* URL in **Site URL** and the two **Redirect URLs** now if you used
a placeholder earlier.

## 8. Invite yourself and colleagues

Back in the repo root (not `web/`):

```sh
pip install -r requirements.txt        # picks up the new `supabase` package
python invite_colleague.py you@example.com --label "Admin"
python invite_colleague.py colleague@example.com --label "Bob - Sales"
```

Each person gets an email with a link to `/set-password` where they choose
their own password. That's the only way in — there's no "Sign up" button
anywhere for them to find.

Check who currently has access any time:

```sh
python invite_colleague.py --list
```

Revoke access (does not delete their Supabase account — just blocks the
dashboard for them; re-inviting later is instant):

```sh
python invite_colleague.py --revoke colleague@example.com
```

## 9. Publish the dashboard

```sh
python build_dashboard.py
python deploy_dashboard.py
```

`run_daily.bat` already runs both of these as its last two steps, so once
this is set up, publishing happens automatically on your existing schedule
— you don't need to re-run this manually going forward.

## 10. Test it

1. Open your Vercel URL in an incognito/private window.
2. You should land on `/login` — **not** the dashboard, and View Source on
   this page should show no lead data of any kind (it's just a login form:
   email, password, and a "Forgot password?" link — nothing else).
3. Sign in with an invited account. You should now see the real dashboard,
   with a **Log out** button in the top-right corner.
4. Try a non-invited email (or just remove yourself temporarily with
   `--revoke` and try again) — you should get a clear "not authorized" page,
   never the dashboard.
5. Log out, then try navigating directly back to the site — you should be
   sent to `/login` again, not shown a cached copy of the dashboard.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| "Dashboard file not found in private storage yet" | Run `deploy_dashboard.py` at least once, and confirm the bucket name in Supabase matches `SUPABASE_DASHBOARD_BUCKET` (default `dashboard-private`). |
| "This is an invite-only system and that email hasn't been given access" for someone you *did* invite | They need to accept the invite email (set a password) at least once before they can sign in — an invite creates the account but Supabase still requires that first step. |
| Reset-password link says "invalid or has expired" | Links are single-use and time-limited (default ~1 hour) — have them click "Forgot password?" again for a fresh one. |
| Env var errors on Vercel | Re-check `vercel env ls` — all three (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`) must be set for the **Production** environment, then redeploy (`npx vercel deploy --prod`) so the new values take effect. |

## What's public vs. private, at a glance

| Lives where | Contains lead data? |
|---|---|
| `web/public/*.html`, `web/public/assets/*` (deployed to Vercel, in this git repo) | No — just the login UI (email, password, forgot-password) and the set-password page, zero dashboard content |
| `web/api/*.js` (deployed to Vercel, in this git repo) | No — server logic only, reads the private file but never embeds it in source |
| Supabase Storage bucket `dashboard-private` | **Yes** — but the bucket is private; only the service-role key (server-side only) can read it |
| `.env`, `intel.db`, `leads.xlsx` (your machine) | Yes — never committed (already git-ignored), never uploaded anywhere except the one deliberate `deploy_dashboard.py` call into the private bucket |
