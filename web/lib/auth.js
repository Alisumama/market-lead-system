// Server-side session verification. This is the part that actually enforces
// "no dashboard bytes without a valid, allow-listed login" — everything here
// runs on Vercel's server, never in the browser.

const { createClient } = require("@supabase/supabase-js");
const cookie = require("cookie");
const { getServerEnv } = require("./env");

const ACCESS_COOKIE = "sb-access-token";
const REFRESH_COOKIE = "sb-refresh-token";

// Cookie flags: httpOnly (JS can't read it -> can't be exfiltrated by XSS),
// Secure (never sent over plain HTTP), SameSite=Lax (sent on normal
// top-level navigation, which is what loading the dashboard is).
function cookieOptions(maxAgeSeconds) {
  return {
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    path: "/",
    maxAge: maxAgeSeconds,
  };
}

function setSessionCookies(res, session) {
  const headers = [
    cookie.serialize(ACCESS_COOKIE, session.access_token, cookieOptions(60 * 60)), // 1h
    cookie.serialize(REFRESH_COOKIE, session.refresh_token, cookieOptions(60 * 60 * 24 * 30)), // 30d
  ];
  res.setHeader("Set-Cookie", headers);
}

function clearSessionCookies(res) {
  const headers = [
    cookie.serialize(ACCESS_COOKIE, "", cookieOptions(0)),
    cookie.serialize(REFRESH_COOKIE, "", cookieOptions(0)),
  ];
  res.setHeader("Set-Cookie", headers);
}

function readCookies(req) {
  return cookie.parse(req.headers.cookie || "");
}

/**
 * Verifies the caller's session strictly server-side against Supabase (this
 * is a real JWT verification round-trip, not just "the cookie exists").
 * Transparently refreshes an expired access token using the refresh token
 * and re-issues cookies when that happens.
 *
 * Returns { user, refreshedSession } on success, or { user: null } if there
 * is no valid session at all.
 */
async function verifySession(req, res) {
  const env = getServerEnv();
  const cookies = readCookies(req);
  const accessToken = cookies[ACCESS_COOKIE];
  const refreshToken = cookies[REFRESH_COOKIE];

  if (!accessToken && !refreshToken) {
    return { user: null };
  }

  // anon-key client is intentional here: getUser(jwt) asks Supabase's auth
  // server to validate the token, it does not just trust local claims.
  const supabase = createClient(env.supabaseUrl, env.supabaseAnonKey);

  if (accessToken) {
    const { data, error } = await supabase.auth.getUser(accessToken);
    if (!error && data && data.user) {
      return { user: data.user };
    }
  }

  // Access token missing/expired — try the refresh token once.
  if (refreshToken) {
    const { data, error } = await supabase.auth.refreshSession({ refresh_token: refreshToken });
    if (!error && data && data.session && data.user) {
      setSessionCookies(res, data.session);
      return { user: data.user, refreshedSession: data.session };
    }
  }

  return { user: null };
}

/**
 * Second, independent layer of defense: even a genuinely logged-in Supabase
 * user only gets dashboard access if their email is on the allowed_emails
 * table. This is checked with the SERVICE ROLE key (server-only secret) so
 * it can never be bypassed by client-side Row Level Security tricks, and so
 * revoking someone is "delete one row" without touching their auth account.
 */
async function isEmailAllowed(email) {
  if (!email) return false;
  const env = getServerEnv();
  const admin = createClient(env.supabaseUrl, env.supabaseServiceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await admin
    .from("allowed_emails")
    .select("email")
    .eq("email", email.toLowerCase())
    .maybeSingle();

  if (error) {
    // Fail closed: a DB error must never be treated as "allowed".
    console.error("allowed_emails lookup failed:", error.message);
    return false;
  }
  return !!data;
}

module.exports = {
  setSessionCookies,
  clearSessionCookies,
  readCookies,
  verifySession,
  isEmailAllowed,
  ACCESS_COOKIE,
  REFRESH_COOKIE,
};
