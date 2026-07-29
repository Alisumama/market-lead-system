/* Shared client-side helpers for login.html and set-password.html.
 *
 * IMPORTANT: nothing in this file, or anywhere in /public, ever sees real
 * lead data. This code's only job is to authenticate the browser with
 * Supabase and then hand the resulting session to our own server
 * (/api/session), which is the thing that actually decides what the
 * dashboard route is allowed to return. A person could read every line of
 * this file and still learn nothing about any lead.
 */

// -- Supabase client (config fetched from our own server, see api/public-config.js) --
//
// The client is created with a wrapped `fetch` so we can read the
// "Retry-After" response header on a 429. Supabase's SDK methods only ever
// surface `message` / `status` / `code` from a failed call — the raw HTTP
// header is otherwise thrown away — so this is the only way to show a real
// wait time instead of a made-up one. See friendlyAuthError() below.
let _lastRetryAfterSeconds = null;

function _trackingFetch(input, init) {
  return fetch(input, init).then((res) => {
    _lastRetryAfterSeconds = null;
    const header = res.headers.get("retry-after");
    if (header) {
      const seconds = parseInt(header, 10);
      if (Number.isFinite(seconds) && seconds > 0) _lastRetryAfterSeconds = seconds;
    }
    return res;
  });
}

// Feeds a retry-after value into the next friendlyAuthError() call when it
// was obtained some other way than a direct client-side Supabase call — e.g.
// a JSON field from one of our own /api/* endpoints, which does its own
// server-side Retry-After capture (see api/request-password-reset.js).
function primeRetryAfter(seconds) {
  _lastRetryAfterSeconds = Number.isFinite(seconds) && seconds > 0 ? seconds : null;
}

let _clientPromise = null;
function getSupabaseClient() {
  if (_clientPromise) return _clientPromise;
  _clientPromise = fetch("/api/public-config")
    .then((r) => {
      if (!r.ok) throw new Error("Could not load auth configuration.");
      return r.json();
    })
    .then(({ supabaseUrl, supabaseAnonKey }) => {
      if (!supabaseUrl || !supabaseAnonKey) {
        throw new Error(
          "Auth is not configured yet (missing SUPABASE_URL / SUPABASE_ANON_KEY)."
        );
      }
      // `supabase` global comes from the CDN <script> tag loaded on the page.
      return window.supabase.createClient(supabaseUrl, supabaseAnonKey, {
        global: { fetch: _trackingFetch },
      });
    });
  return _clientPromise;
}

// -- Hand a client-side Supabase session to our server so it can be verified
//    and stored as httpOnly cookies. This is the step that turns "the
//    browser proved who it is to Supabase" into "our server can now check
//    that on every request," which is what actually gates the dashboard. --
async function handoffSessionToServer(session) {
  const res = await fetch("/api/session", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      access_token: session.access_token,
      refresh_token: session.refresh_token,
    }),
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || "Could not establish a session with the server.");
  }
}

// -- Eye icon show/hide toggle for a password field --
function wireEyeToggle(inputEl, toggleBtnEl) {
  toggleBtnEl.addEventListener("click", () => {
    const showing = inputEl.type === "text";
    inputEl.type = showing ? "password" : "text";
    toggleBtnEl.setAttribute("aria-label", showing ? "Show password" : "Hide password");
    toggleBtnEl.classList.toggle("eye-open", !showing);
    toggleBtnEl.textContent = showing ? "\u{1F441}" : "\u{1F576}"; // eye / eye (dim)
  });
}

// -- Strong-password rules, checklist UI, and a simple strength meter --
const PASSWORD_RULES = [
  { key: "len", label: "At least 12 characters", test: (v) => v.length >= 12 },
  { key: "upper", label: "One uppercase letter (A-Z)", test: (v) => /[A-Z]/.test(v) },
  { key: "lower", label: "One lowercase letter (a-z)", test: (v) => /[a-z]/.test(v) },
  { key: "digit", label: "One number (0-9)", test: (v) => /[0-9]/.test(v) },
  { key: "special", label: "One special character (!@#$%^&* etc.)", test: (v) => /[^A-Za-z0-9]/.test(v) },
];
// Hard floor even if someone edits rules above: never accept under 8 chars.
const MIN_ABSOLUTE_LENGTH = 8;

function evaluatePassword(value) {
  const results = PASSWORD_RULES.map((rule) => ({ ...rule, passed: rule.test(value) }));
  const passedCount = results.filter((r) => r.passed).length;
  const allPassed = passedCount === results.length && value.length >= MIN_ABSOLUTE_LENGTH;

  let strength = "weak";
  if (allPassed && value.length >= 16) strength = "strong";
  else if (passedCount >= 4) strength = "medium";

  return { results, allPassed, strength };
}

/**
 * Wires live validation on a password field: updates a checklist, a
 * strength meter, and calls onValidityChange(bool) so the caller can
 * enable/disable a submit button. Returns a function you can call to
 * re-read current validity (e.g. right before submit).
 */
function wirePasswordStrength({ inputEl, checklistEl, meterEl, onValidityChange }) {
  checklistEl.innerHTML = PASSWORD_RULES.map(
    (r) => `<li data-rule="${r.key}" class="rule pending">${r.label}</li>`
  ).join("");

  function render() {
    const { results, allPassed, strength } = evaluatePassword(inputEl.value);
    results.forEach((r) => {
      const li = checklistEl.querySelector(`[data-rule="${r.key}"]`);
      if (!li) return;
      li.classList.toggle("pass", r.passed);
      li.classList.toggle("pending", !r.passed);
      li.textContent = (r.passed ? "✓ " : "✗ ") + r.label;
    });
    if (meterEl) {
      meterEl.className = "strength-meter strength-" + strength;
      meterEl.textContent = inputEl.value ? "Strength: " + strength : "";
    }
    if (onValidityChange) onValidityChange(allPassed);
    return allPassed;
  }

  inputEl.addEventListener("input", render);
  render();
  return render;
}

// -- Turn a wait time in seconds into "45 seconds" / "12 minutes" / "2 hours" --
function formatWaitTime(seconds) {
  if (seconds < 90) return `${seconds} second${seconds === 1 ? "" : "s"}`;
  const minutes = Math.ceil(seconds / 60);
  if (minutes < 90) return `${minutes} minute${minutes === 1 ? "" : "s"}`;
  const hours = Math.ceil(minutes / 60);
  return `${hours} hour${hours === 1 ? "" : "s"}`;
}

// -- Friendly, non-enumerating error copy for the login/reset/set-password forms.
//
// Matches on `.status` / `.code` first — the stable, documented fields
// Supabase's SDK attaches to every auth error — rather than English message
// text. Message-text matching is why rate limits used to get misread as
// "incorrect password": a wording mismatch or ordering issue in the regex
// chain would silently fall through to the wrong branch. Status/code can't
// drift like that, so rate limiting is checked FIRST, deterministically, and
// can never be shadowed by a credentials-shaped message.
function friendlyAuthError(error) {
  const status = error && error.status;
  const code = error && error.code;
  const msg = (error && error.message) || "";

  const isRateLimited =
    status === 429 ||
    code === "over_request_rate_limit" ||
    code === "over_email_send_rate_limit" ||
    code === "over_sms_send_rate_limit" ||
    /rate limit/i.test(msg);

  if (isRateLimited) {
    const wait = _lastRetryAfterSeconds
      ? `Please wait about ${formatWaitTime(_lastRetryAfterSeconds)} before trying again.`
      : null;
    if (code === "over_email_send_rate_limit") {
      // Supabase's default email-sending limits are the tightest (built-in
      // email sending — see web/SETUP.md — is roughly a handful per hour),
      // so this is the one most likely to actually get hit day-to-day.
      return (
        "Too many reset/invite emails have been requested for this address recently. " +
        (wait || "Please wait about an hour before requesting another.")
      );
    }
    return "Too many attempts. " + (wait || "Please wait a few minutes and try again.");
  }

  if (code === "invalid_credentials" || /invalid login credentials/i.test(msg)) {
    return "Incorrect email or password.";
  }
  if (
    code === "signup_disabled" ||
    code === "email_address_not_authorized" ||
    code === "user_banned" ||
    /signups? not allowed|user not allowed|not authorized/i.test(msg)
  ) {
    return "This is an invite-only system and that email hasn't been given access. Contact your administrator.";
  }
  if (code === "email_not_confirmed" || /email not confirmed/i.test(msg)) {
    return "That account hasn't accepted its invite yet — check for the invite email.";
  }
  return msg || "Something went wrong. Please try again.";
}
