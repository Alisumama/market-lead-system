// POST { email } -> triggers a Supabase password-reset email, but ONLY for
// the exact email address passed in, and only after confirming it's on the
// allowed_emails allowlist. This exists so the "Forgot password?" flow can
// tell the user plainly whether their email is even eligible, instead of
// Supabase's default (deliberately vague, anti-enumeration) "if that email
// exists, a link was sent" response. See web/SETUP.md and the code review
// notes in login.html for the trade-off this makes.

const { createClient } = require("@supabase/supabase-js");
const { getServerEnv } = require("../lib/env");
const { isEmailAllowed } = require("../lib/auth");

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, reason: "error", message: "Method not allowed" });
    return;
  }

  const rawEmail = req.body && req.body.email;
  if (typeof rawEmail !== "string" || !EMAIL_RE.test(rawEmail.trim())) {
    res.status(400).json({ ok: false, reason: "error", message: "A valid email is required" });
    return;
  }
  const email = rawEmail.trim().toLowerCase();

  let allowed;
  try {
    allowed = await isEmailAllowed(email);
  } catch (err) {
    res.status(500).json({ ok: false, reason: "error", message: "Could not check access. Try again shortly." });
    return;
  }

  if (!allowed) {
    // Deliberately explicit per product decision: this trades a small
    // amount of user-enumeration resistance for clarity, on the reasoning
    // that this is an invite-only tool with a handful of named colleagues,
    // not a public consumer signup surface. This endpoint has no rate limit
    // of its own — see the note passed back to the caller.
    res.status(200).json({ ok: false, reason: "not_allowed", email });
    return;
  }

  try {
    const env = getServerEnv();

    // Same trick as the browser client (web/public/assets/auth.js): wrap
    // fetch so we can read the "Retry-After" header on a 429. The SDK
    // itself throws that away, so this is the only way to tell the caller
    // an accurate wait time instead of a guessed one. Scoped to this one
    // request (a local variable, not module-level state) since a
    // serverless function instance can interleave concurrent invocations.
    let retryAfterSeconds = null;
    const trackingFetch = (input, init) =>
      fetch(input, init).then((r) => {
        const header = r.headers.get("retry-after");
        if (header) {
          const seconds = parseInt(header, 10);
          if (Number.isFinite(seconds) && seconds > 0) retryAfterSeconds = seconds;
        }
        return r;
      });

    const supabase = createClient(env.supabaseUrl, env.supabaseAnonKey, {
      global: { fetch: trackingFetch },
    });
    // Vercel always terminates HTTPS in front of the function, so this is
    // always the site's real public origin.
    const siteUrl = `https://${req.headers.host}`;

    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${siteUrl}/set-password`,
    });

    if (error) {
      const rateLimited =
        error.status === 429 ||
        error.code === "over_email_send_rate_limit" ||
        error.code === "over_request_rate_limit";
      res.status(rateLimited ? 429 : 500).json({
        ok: false,
        reason: rateLimited ? "rate_limited" : "error",
        code: error.code,
        message: error.message,
        retryAfterSeconds: rateLimited ? retryAfterSeconds : undefined,
      });
      return;
    }
  } catch (err) {
    res.status(500).json({ ok: false, reason: "error", message: "Could not send the reset email. Try again shortly." });
    return;
  }

  res.status(200).json({ ok: true, email });
};
