// Central place to read required server-side config and fail loudly (not
// silently serve broken auth) if something is missing from Vercel's
// Environment Variables. Never import this file from client-side code —
// SUPABASE_SERVICE_ROLE_KEY must never reach the browser.

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(
      `Missing required environment variable ${name}. Set it in the Vercel ` +
        `project's Environment Variables (see web/SETUP.md).`
    );
  }
  return value;
}

function getServerEnv() {
  return {
    supabaseUrl: required("SUPABASE_URL"),
    supabaseAnonKey: required("SUPABASE_ANON_KEY"),
    supabaseServiceRoleKey: required("SUPABASE_SERVICE_ROLE_KEY"),
    dashboardBucket: process.env.SUPABASE_DASHBOARD_BUCKET || "dashboard-private",
    dashboardPath: process.env.SUPABASE_DASHBOARD_PATH || "dashboard.html",
  };
}

module.exports = { getServerEnv, required };
