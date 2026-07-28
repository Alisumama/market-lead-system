// THE gate. This is the only route that ever reads the real dashboard.html
// (from a private Supabase Storage bucket) and it only does so after two
// checks pass, both server-side:
//   1. verifySession()   -> is there a currently valid, Supabase-verified login?
//   2. isEmailAllowed()  -> is that email on the allowed_emails table right now?
// Fail either one and the response contains zero bytes of dashboard content
// — just a redirect or a plain "not authorized" page. There is no code path
// where the HTML with lead data is sent before both checks pass.

const { createClient } = require("@supabase/supabase-js");
const { getServerEnv } = require("../lib/env");
const { verifySession, isEmailAllowed } = require("../lib/auth");

function redirectToLogin(res) {
  res.writeHead(302, { Location: "/login", "Cache-Control": "no-store" });
  res.end();
}

function sendNotAuthorized(res, email) {
  res.writeHead(403, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
  res.end(`<!doctype html>
<html><head><meta charset="utf-8"><title>Not authorized</title>
<style>body{font-family:-apple-system,sans-serif;background:#eef3ea;color:#1b2320;
display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
.card{background:#fff;border-radius:12px;padding:32px;max-width:420px;text-align:center;
box-shadow:0 4px 24px rgba(27,35,32,.06)}
h1{font-size:18px}p{color:#5a6a5c;font-size:14px}
a{color:#1b7a2b;font-weight:600;text-decoration:none}</style></head>
<body><div class="card">
<h1>Not authorized</h1>
<p>${email ? "The account <b>" + email.replace(/[<>&]/g, "") + "</b> is" : "This account is"}
not on the approved list for this dashboard.</p>
<p>Contact your administrator if you believe this is a mistake.</p>
<p><a href="/login" id="signout-link">Sign out</a></p>
</div>
<script>
document.getElementById('signout-link').addEventListener('click', function(e){
  e.preventDefault();
  fetch('/api/logout', {method:'POST'}).finally(function(){ window.location.href = '/login'; });
});
</script>
</body></html>`);
}

const LOGOUT_SNIPPET = `
<div id="__auth_gate_bar" style="position:fixed;top:10px;right:14px;z-index:9999;">
  <button id="__auth_gate_logout" style="background:#1b7a2b;color:#fff;border:none;
    border-radius:8px;padding:8px 14px;font:600 12.5px -apple-system,sans-serif;
    cursor:pointer;box-shadow:0 2px 8px rgba(0,0,0,.15)">Log out</button>
</div>
<script>
(function(){
  var btn = document.getElementById('__auth_gate_logout');
  btn.addEventListener('click', function(){
    btn.disabled = true; btn.textContent = 'Signing out...';
    fetch('/api/public-config').then(function(r){ return r.json(); }).then(function(cfg){
      var s = document.createElement('script');
      s.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
      s.onload = function(){
        try {
          var client = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
          client.auth.signOut().catch(function(){});
        } catch (e) {}
        fetch('/api/logout', {method:'POST'}).finally(function(){ window.location.href = '/login'; });
      };
      s.onerror = function(){
        fetch('/api/logout', {method:'POST'}).finally(function(){ window.location.href = '/login'; });
      };
      document.body.appendChild(s);
    }).catch(function(){
      fetch('/api/logout', {method:'POST'}).finally(function(){ window.location.href = '/login'; });
    });
  });
})();
</script>
`;

function injectLogoutButton(html) {
  if (/<\/body>/i.test(html)) {
    return html.replace(/<\/body>/i, LOGOUT_SNIPPET + "</body>");
  }
  return html + LOGOUT_SNIPPET;
}

module.exports = async (req, res) => {
  let user;
  try {
    const result = await verifySession(req, res);
    user = result.user;
  } catch (err) {
    console.error("verifySession failed:", err.message);
    res.status(500).send("Auth check failed. Try again shortly.");
    return;
  }

  if (!user) {
    redirectToLogin(res);
    return;
  }

  const allowed = await isEmailAllowed(user.email);
  if (!allowed) {
    sendNotAuthorized(res, user.email);
    return;
  }

  // Both checks passed — only now do we touch the private file.
  try {
    const env = getServerEnv();
    const admin = createClient(env.supabaseUrl, env.supabaseServiceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await admin.storage
      .from(env.dashboardBucket)
      .download(env.dashboardPath);

    if (error || !data) {
      res.status(500).send(
        "Dashboard file not found in private storage yet. " +
          "Run build_dashboard.py and deploy_dashboard.py first."
      );
      return;
    }

    const arrayBuffer = await data.arrayBuffer();
    const html = Buffer.from(arrayBuffer).toString("utf-8");

    res.setHeader("Content-Type", "text/html; charset=utf-8");
    // Never let a browser or intermediary cache the authenticated response —
    // this matters most on a shared/public computer.
    res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate, private");
    res.status(200).send(injectLogoutButton(html));
  } catch (err) {
    console.error("Failed to load dashboard from storage:", err.message);
    res.status(500).send("Could not load the dashboard. Try again shortly.");
  }
};
