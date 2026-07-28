// Clears the session cookies. This alone is enough to cut off access to
// /api/dashboard (no cookie -> verifySession() returns no user), independent
// of whatever the client-side Supabase SDK does with its own local storage.

const { clearSessionCookies } = require("../lib/auth");

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }
  clearSessionCookies(res);
  res.status(200).json({ ok: true });
};
