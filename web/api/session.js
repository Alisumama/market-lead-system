// POST { access_token, refresh_token } -> verifies the access token really
// is valid against Supabase (never trust what the client claims), then
// stores both as httpOnly cookies. This is the hinge between "the browser
// authenticated with Supabase" and "our server can enforce that on every
// request to /api/dashboard."

const { createClient } = require("@supabase/supabase-js");
const { getServerEnv } = require("../lib/env");
const { setSessionCookies } = require("../lib/auth");

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const { access_token, refresh_token } = req.body || {};
  if (!access_token || !refresh_token) {
    res.status(400).json({ error: "access_token and refresh_token are required" });
    return;
  }

  try {
    const env = getServerEnv();
    const supabase = createClient(env.supabaseUrl, env.supabaseAnonKey);
    const { data, error } = await supabase.auth.getUser(access_token);
    if (error || !data || !data.user) {
      res.status(401).json({ error: "Invalid session" });
      return;
    }

    setSessionCookies(res, { access_token, refresh_token });
    res.status(200).json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};
