// Serves the two values the client-side Supabase SDK needs to run in the
// browser. Both are DESIGNED to be public: the "anon" key is Supabase's
// publishable key (it can only do what your RLS policies allow — and
// allowed_emails has zero policies, so it grants no access to anything
// sensitive). Nothing secret is ever returned here. Kept as an endpoint
// (rather than hardcoded in the HTML) so every setting lives in one place:
// Vercel's Environment Variables.

const { getServerEnv } = require("../lib/env");

module.exports = (req, res) => {
  try {
    const env = getServerEnv();
    res.setHeader("Cache-Control", "no-store");
    res.status(200).json({
      supabaseUrl: env.supabaseUrl,
      supabaseAnonKey: env.supabaseAnonKey,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};
