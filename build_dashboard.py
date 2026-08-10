"""
build_dashboard.py — generate a self-contained dashboard.html from intel.db.

Shows FRESH leads under STRICT freshness: only items whose ARTICLE was
published within the last FRESH_DAYS days (published_date >= cutoff). The
scrape/discovery date is never a freshness signal, and items with an
unknown/missing published_date are excluded from the view entirely.

The output is a single static HTML file (all CSS/JS/data inlined) so it opens
directly from disk — no server, no internet. Regenerated as the final step of
run_daily.bat.

Usage:
    python build_dashboard.py
"""

import base64
import json
import sqlite3
from datetime import date, datetime, timedelta
from pathlib import Path

from init_db import DB_PATH, ensure_columns

OUT_PATH = Path(__file__).with_name("dashboard.html")
LOGO_PATH = Path(__file__).with_name("assets") / "bastak-logo.png"
FRESH_DAYS = 90


def logo_img_tag() -> str:
    """Return an <img> with the logo embedded as a base64 data URI so the
    dashboard stays fully self-contained (the logo survives even if the HTML
    is emailed/copied without the assets/ folder). Empty string if missing."""
    if not LOGO_PATH.exists():
        print(f"  WARNING: logo not found at {LOGO_PATH} — header will show no logo.")
        return ""
    b64 = base64.b64encode(LOGO_PATH.read_bytes()).decode("ascii")
    return ('<span class="logo-chip">'
            f'<img src="data:image/png;base64,{b64}" alt="Bastak Instruments logo">'
            '</span>')


def source_category(source_type: str) -> str:
    st = (source_type or "").lower()
    if st == "linkedin":
        return "LinkedIn"
    if st == "google_alert" or "googlealert" in st:
        return "Google Alert"
    return "News"


RELEVANCE_CUTOFF = 3   # items scoring below this (or is_relevant=false) are hidden


def load_rows(conn: sqlite3.Connection, cutoff: str) -> list[dict]:
    conn.row_factory = sqlite3.Row
    # Only REAL leads: classifier judged relevant AND score >= RELEVANCE_CUTOFF.
    # (Raw items stay in intel.db; we just do not surface the noise here.)
    # STRICT freshness: an item is fresh ONLY if its ARTICLE was PUBLISHED within
    # the window (published_date >= cutoff). The scrape/discovery date is never a
    # freshness signal — a 2024/2025 article scraped today is still old news and
    # must not appear. Items with an unknown/missing published_date are excluded
    # from the fresh view entirely.
    rows = conn.execute(
        """SELECT score, is_relevant, company, ai_country, country, project_type,
                  published_date, ai_summary, summary, url, source_type, source_name,
                  collected_at
           FROM items
           WHERE is_relevant = 1 AND score >= ?
             AND published_date IS NOT NULL AND published_date != ''
             AND published_date >= ?""",
        (RELEVANCE_CUTOFF, cutoff),
    ).fetchall()

    out = []
    for r in rows:
        pub = r["published_date"] or ""
        found = (r["collected_at"] or "")[:10]      # YYYY-MM-DD we first saw it (info only)
        out.append({
            "score": r["score"] if r["score"] is not None else 0,
            "company": (r["company"] or "").strip(),
            # Use ONLY the classifier's country. A deliberate blank from the
            # model ("no single project country is clear") must stay blank —
            # falling back to the raw collector-supplied country reintroduced
            # wrong tags (e.g. multi-country WDS rows showing as "Tajikistan").
            "country": (r["ai_country"] or "").strip(),
            "project_type": (r["project_type"] or "").strip(),
            "published_date": pub,             # always populated (unknown dates excluded)
            "found": found,                    # scrape date — shown for reference, NOT freshness
            "summary": (r["ai_summary"] or r["summary"] or "").strip(),
            "url": (r["url"] or "").strip(),
            "source_cat": source_category(r["source_type"]),
        })
    return out


HTML_TEMPLATE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Bastak Market Intelligence — Fresh Leads</title>
<style>
  :root{
    --green:#32a337; --green-deep:#1b7a2b; --ink:#1b2320; --page:#eef3ea; --card:#ffffff;
    /* content column geometry — shared by the header and the main wrapper so the
       logo's left edge lines up exactly with the cards/table left edge at any width */
    --content-max:1320px; --content-pad:32px;
  }
  *{box-sizing:border-box}
  html,body{margin:0}
  body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
       background:var(--page);color:var(--ink);font-size:14px;line-height:1.5;
       -webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}

  /* ---- sticky frosted header (3-col grid; title truly centered on the page) ---- */
  header.top{position:sticky;top:0;z-index:100;
       background:rgba(244,246,244,0.55);
       -webkit-backdrop-filter:blur(12px);backdrop-filter:blur(12px);
       border-bottom:2px solid var(--green)}
  /* inner grid shares the SAME centered max-width + horizontal padding as .wrap,
     so the logo tile's left edge aligns with the stat cards/table left edge */
  .header-inner{max-width:var(--content-max);margin:0 auto;padding:12px var(--content-pad);
       display:grid;grid-template-columns:1fr auto 1fr;align-items:center;gap:12px}
  /* no min-width:0 -> the 1fr logo column sizes to the logo's content and never squeezes it */
  .brand{justify-self:start;display:flex;align-items:center}
  /* transparent-background logo: no white tile needed on the light frosted header */
  .logo-chip{display:flex;align-items:center;flex:none}
  .logo-chip img{height:90px;width:auto;display:block}
  .sys-title{font-size:24px;font-weight:500;color:#2a352c;letter-spacing:.2px;
       text-align:center;white-space:nowrap}
  header.top .right{justify-self:end;display:flex;align-items:center;gap:16px}
  .meta{text-align:right;line-height:1.3}
  .meta-label{font-size:11px;color:#9aa39b}
  .meta-time{font-size:13px;color:#4a544c;font-weight:500}
  .reload-btn{background:var(--green);color:#fff;border:none;border-radius:8px;padding:8px 16px;
       font:inherit;font-weight:500;font-size:13px;cursor:pointer;display:flex;align-items:center;
       gap:7px;transition:background .15s, transform .15s}
  .reload-btn:hover{background:#2b9030}
  .reload-btn:active{transform:translateY(1px)}
  .reload-btn svg{width:15px;height:15px}

  .wrap{max-width:var(--content-max);margin:0 auto;padding:22px var(--content-pad) 30px}

  /* ---- stat cards ---- */
  .stats{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-bottom:18px}
  .stat{background:var(--card);border:.5px solid #e2e7e2;border-radius:8px;padding:13px 15px;
       border-left:3px solid var(--accent,#c9d3ca)}
  .stat .n{font-size:25px;font-weight:500;color:var(--green-deep);line-height:1.1;
       font-variant-numeric:tabular-nums}
  .stat .l{font-size:11px;color:#7a847c;text-transform:uppercase;letter-spacing:.6px;margin-top:5px}
  .stat.st-new{--accent:#32a337} .stat.st-fresh{--accent:#9ac36f} .stat.st-shown{--accent:#c9d3ca}
  .stat.st-hi{--accent:#32a337}

  /* ---- filter bar ---- */
  .controls{background:var(--card);border:.5px solid #e2e7e2;border-radius:10px;padding:14px 16px;
       display:flex;gap:14px;flex-wrap:wrap;align-items:flex-end;margin-bottom:18px}
  .ctrl{display:flex;flex-direction:column;gap:6px}
  .ctrl.push{margin-left:auto}
  .ctrl label{font-size:11px;color:#7a847c;font-weight:600;text-transform:uppercase;letter-spacing:.4px}
  select,input[type=range],input[type=date]{font:inherit}
  select,input[type=date]{padding:8px 10px;border:.5px solid #cdd5cd;border-radius:7px;background:#fff;
       color:var(--ink);transition:border-color .15s, box-shadow .15s}
  select{min-width:160px}
  select:focus,input[type=date]:focus{outline:none;border-color:var(--green);
       box-shadow:0 0 0 3px rgba(50,163,55,.15)}
  input[type=range]{accent-color:var(--green);cursor:pointer;width:150px}
  .srcbox{display:flex;gap:14px}
  .srcbox label{display:flex;align-items:center;gap:6px;font-size:13px;color:var(--ink);font-weight:500}
  .srcbox input{accent-color:var(--green)}
  .rangeval{font-weight:700;color:var(--green-deep)}
  .dl-btn{background:var(--green-deep);color:#fff;border:none;border-radius:8px;padding:9px 16px;
       font:inherit;font-weight:500;cursor:pointer;display:flex;align-items:center;gap:7px;
       transition:background .15s, transform .15s}
  .dl-btn:hover{background:#166323}
  .dl-btn:active{transform:translateY(1px)}
  .dl-btn:disabled{background:#9aa39b;cursor:not-allowed}
  .dl-btn svg{width:15px;height:15px}
  .icon-btn{background:var(--green-deep);color:#fff;border:none;border-radius:8px;
       width:38px;height:38px;flex:none;display:flex;align-items:center;justify-content:center;
       cursor:pointer;transition:background .15s, transform .15s}
  .icon-btn:hover{background:#166323}
  .icon-btn:active{transform:translateY(1px)}
  .icon-btn svg{width:18px;height:18px}

  .count{margin:0 2px 10px;color:#7a847c;font-size:13px}

  /* ---- table ---- */
  .tablecard{background:var(--card);border:.5px solid #e2e7e2;border-radius:10px;overflow:hidden}
  .tablescroll{overflow-x:auto}
  table{width:100%;border-collapse:collapse;background:var(--card)}
  thead th{background:#eef3ee;color:#5a6a5c;text-align:left;padding:10px 14px;
       font-size:11px;font-weight:600;letter-spacing:.5px;text-transform:uppercase;
       white-space:nowrap;user-select:none}
  thead th.sortable{cursor:pointer}
  thead th.sortable:hover{color:var(--green-deep)}
  thead th.sortable::after{content:" \2195";opacity:.45;font-size:10px}
  thead th.sorted-asc::after{content:" \2191";opacity:1;color:var(--green-deep)}
  thead th.sorted-desc::after{content:" \2193";opacity:1;color:var(--green-deep)}
  tbody td{padding:12px 14px;border-top:1px solid #f0f4ef;vertical-align:top}
  tbody tr{transition:background .12s ease}
  tbody tr:nth-child(even){background:#fafcf9}
  tbody tr:hover{background:#f2f7f1}
  .score{display:inline-block;min-width:26px;text-align:center;font-weight:600;color:#fff;
       border-radius:6px;padding:3px 7px;font-size:12.5px}
  .sc-hi{background:#2e9e34} .sc-good{background:#7aa854} .sc-mid{background:#c9a83a} .sc-low{background:#9aa39b}
  /* rows fade in when the page changes (not on hover/sort of the same page) */
  tbody tr.pgin{animation:rowin .15s ease both}
  @keyframes rowin{from{opacity:0}to{opacity:1}}
  .company{font-weight:600;color:var(--ink)}
  .newbadge{display:inline-block;background:#e5f3e7;color:#1b7a2b;font-size:10px;font-weight:700;
       border-radius:20px;padding:2px 8px;margin-left:8px;vertical-align:middle;letter-spacing:.3px}
  .ptype{display:inline-block;background:#f0f3ef;color:#5a6a5c;border-radius:20px;padding:3px 10px;
       font-size:12px;white-space:nowrap}
  .summary{color:#41524c;max-width:540px;line-height:1.5}
  .date{white-space:nowrap;color:#41544c;font-variant-numeric:tabular-nums}
  .found{white-space:nowrap;color:#8a938c;font-variant-numeric:tabular-nums;font-size:13px}
  a.src{color:var(--green-deep);display:inline-flex;align-items:center;text-decoration:none}
  a.src:hover{color:#166323}
  a.src svg{width:16px;height:16px}
  .empty{padding:44px;text-align:center;color:#7a847c}

  /* ---- pagination bar (inside the table card, below the table) ---- */
  .pagebar{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;
       padding:12px 16px;border-top:1px solid #f0f4ef;background:var(--card)}
  .pagebar-left{display:flex;align-items:center;gap:18px;flex-wrap:wrap}
  .showing{color:#7a847c;font-size:13px;font-variant-numeric:tabular-nums;
       transition:opacity .18s ease}
  .showing.fading{opacity:0}
  .rpp{display:flex;align-items:center;gap:7px;font-size:12px;color:#7a847c}
  .rpp select{min-width:0;padding:5px 8px;font-size:12.5px;border-radius:6px}
  .pager{display:flex;align-items:center;gap:6px;flex-wrap:wrap}
  .pgbtn{min-width:32px;height:32px;padding:0 9px;background:#fff;color:var(--ink);
       border:.5px solid #cdd5cd;border-radius:7px;font:inherit;font-size:13px;font-weight:500;
       cursor:pointer;display:inline-flex;align-items:center;justify-content:center;
       font-variant-numeric:tabular-nums;
       transition:background .12s ease, border-color .12s ease, color .12s ease}
  .pgbtn:hover:not(:disabled):not(.active){background:#f2f7f1;border-color:var(--green)}
  .pgbtn.active{background:var(--green);border-color:var(--green);color:#fff;cursor:default}
  .pgbtn:disabled{color:#c2cac3;cursor:not-allowed}
  .pgbtn:focus-visible{outline:2px solid var(--green-deep);outline-offset:2px}
  .pgbtn svg{width:14px;height:14px}
  .pgap{padding:0 2px;color:#9aa39b;user-select:none}

  /* Honour the OS "reduce motion" setting: keep every state change, drop the
     animation. Nothing below is decorative-only — each maps to a transition
     declared above. */
  @media (prefers-reduced-motion: reduce){
    tbody tr.pgin{animation:none}
    tbody tr,.showing,.pgbtn,.reload-btn,.dl-btn,.icon-btn{transition:none}
  }

  /* ---- footer ---- */
  .foot{text-align:center;color:#9aa39b;font-size:12px;padding:22px 20px 34px}
</style>
</head>
<body>
<header class="top">
  <div class="header-inner">
  <div class="brand">
    __LOGO_IMG__
  </div>
  <span class="sys-title">Market Intelligence System</span>
  <div class="right">
    <div class="meta">
      <div class="meta-label">Last updated</div>
      <div class="meta-time">__GENERATED__</div>
    </div>
    <button class="reload-btn" onclick="location.reload(true)"
            title="Reload this page from disk to show the latest generated data (run the daily pipeline / build_dashboard.py to refresh the data itself).">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
      Reload
    </button>
  </div>
  </div>
</header>

<div class="wrap">
  <div class="stats">
    <div class="stat st-new"><div class="n" id="stat-new">__NEW_COUNT__</div><div class="l">New &le; 10 days</div></div>
    <div class="stat st-fresh"><div class="n" id="stat-fresh">__FRESH_COUNT__</div><div class="l">Fresh leads</div></div>
    <div class="stat st-shown"><div class="n" id="stat-shown">0</div><div class="l">Shown</div></div>
    <div class="stat st-hi"><div class="n" id="stat-hi">0</div><div class="l">Score &ge; 7</div></div>
  </div>

  <div class="controls">
    <div class="ctrl">
      <label for="f-country">Country</label>
      <select id="f-country"><option value="">All countries</option></select>
    </div>
    <div class="ctrl">
      <label for="f-score">Minimum score: <span class="rangeval" id="score-val">0</span></label>
      <input type="range" id="f-score" min="0" max="10" step="1" value="0">
    </div>
    <div class="ctrl">
      <label>Source type</label>
      <div class="srcbox">
        <label><input type="checkbox" class="f-src" value="News" checked> News</label>
        <label><input type="checkbox" class="f-src" value="Google Alert" checked> Google Alert</label>
        <label><input type="checkbox" class="f-src" value="LinkedIn" checked> LinkedIn</label>
      </div>
    </div>
    <div class="ctrl push">
      <label for="f-start">From</label>
      <input type="date" id="f-start">
    </div>
    <div class="ctrl">
      <label for="f-end">To</label>
      <input type="date" id="f-end">
    </div>
    <div class="ctrl">
      <label>&nbsp;</label>
      <button class="icon-btn" id="f-reload" title="Reload results for the selected date range and filters.">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
      </button>
    </div>
    <div class="ctrl">
      <label>&nbsp;</label>
      <button class="dl-btn" id="f-dl" title="Export the currently filtered leads within the chosen date range to an Excel file.">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
        Excel
      </button>
    </div>
  </div>

  <div class="count" id="count-line"></div>

  <div class="tablecard">
    <div class="tablescroll">
      <table>
        <thead>
          <tr>
            <th class="sortable" data-key="score">Score</th>
            <th>Company</th>
            <th>Country</th>
            <th>Project Type</th>
            <th class="sortable" data-key="published_date">Published Date</th>
            <th class="sortable" data-key="found" title="Date this lead was discovered / collected into the system.">Found</th>
            <th>Summary</th>
            <th>Source</th>
          </tr>
        </thead>
        <tbody id="tbody"></tbody>
      </table>
    </div>
    <div class="empty" id="empty" style="display:none">No leads match the current filters.</div>

    <div class="pagebar" id="pagebar">
      <div class="pagebar-left">
        <span class="showing" id="showing" aria-live="polite"></span>
        <span class="rpp">
          <label for="f-rpp">Rows per page</label>
          <select id="f-rpp" title="How many leads to show per page.">
            <option value="10" selected>10</option>
            <option value="25">25</option>
            <option value="50">50</option>
          </select>
        </span>
      </div>
      <nav class="pager" id="pager" aria-label="Pagination"></nav>
    </div>
  </div>

  <footer class="foot">Fresh window: last __FRESH_DAYS__ days &middot; published since __CUTOFF__</footer>
</div>

<script>
const DATA = __DATA_JSON__;
const RECENT_SINCE = "__RECENT_SINCE__";   // items PUBLISHED on/after this date are "new" (10d)
let sortKey = "published_date";  // default: newest PUBLISHED first
let sortDir = -1;                // -1 desc, 1 asc
let page = 1;                    // 1-based, always relative to the CURRENT filtered set
let perPage = 10;                // rows per page (10 / 25 / 50)

// Respect the OS "reduce motion" setting for the JS-driven transitions too.
const REDUCE_MOTION = window.matchMedia
  && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

// -- populate country dropdown --
const countries = [...new Set(DATA.map(d => d.country).filter(Boolean))].sort();
const csel = document.getElementById("f-country");
for (const c of countries){ const o=document.createElement("option"); o.value=c; o.textContent=c; csel.appendChild(o); }

// External-link icon for source cells (green via currentColor).
const EXT_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>';

// Chevrons for the prev/next pagination arrows.
const CHEV_L = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>';
const CHEV_R = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>';

// 8+ green, 7 mid-green, 5-6 amber, <5 gray
function scoreClass(s){ return s>=8 ? "sc-hi" : (s>=7 ? "sc-good" : (s>=5 ? "sc-mid" : "sc-low")); }

function activeSources(){
  return [...document.querySelectorAll(".f-src")].filter(c=>c.checked).map(c=>c.value);
}

function sortRows(rows){
  const key = sortKey;
  rows.sort((a,b)=>{
    let pa = key==="score" ? a.score : (a[key]||"");
    let pb = key==="score" ? b.score : (b[key]||"");
    let cmp = pa<pb ? -1 : (pa>pb ? 1 : 0);
    cmp *= sortDir;
    if (cmp!==0) return cmp;
    // tie-breakers, always most-useful-first: newest discovery, then top score
    if (key!=="found"){
      const fa=a.found||"", fb=b.found||"";
      if (fa!==fb) return fa<fb ? 1 : -1;     // newest found first
    }
    return b.score - a.score;                 // highest score first
  });
  return rows;
}

// The current filter + sort selection, WITHOUT pagination applied. The stat
// cards, the count line and the Excel export all describe this full set — only
// the table body is paged.
function filteredRows(){
  const minScore = +document.getElementById("f-score").value;
  const country = document.getElementById("f-country").value;
  const srcs = activeSources();
  const start = document.getElementById("f-start").value;
  const end = document.getElementById("f-end").value;

  let rows = DATA.filter(d=>{
    if (d.score < minScore) return false;
    if (country && d.country !== country) return false;
    if (!srcs.includes(d.source_cat)) return false;
    if (start && d.published_date < start) return false;
    if (end && d.published_date > end) return false;
    return true;
  });
  return sortRows(rows);
}

function render(){
  const rows = filteredRows();
  const total = rows.length;
  const pages = Math.max(1, Math.ceil(total / perPage));
  // Clamp: the filtered set can shrink under us (e.g. a stricter filter while
  // sitting on page 9), so never render an out-of-range page.
  if (page > pages) page = pages;
  if (page < 1) page = 1;
  const from = (page - 1) * perPage;
  const pageRows = rows.slice(from, from + perPage);

  const tb = document.getElementById("tbody");
  tb.innerHTML = "";
  for (const d of pageRows){
    const tr = document.createElement("tr");
    tr.className = "pgin";
    const isNew = d.published_date && d.published_date >= RECENT_SINCE;  // published within 10 days
    if (isNew) tr.classList.add("isnew");

    const sc = document.createElement("td");
    const badge = document.createElement("span");
    badge.className = "score " + scoreClass(d.score);
    badge.textContent = d.score>0 ? d.score : "—";
    sc.appendChild(badge); tr.appendChild(sc);

    const co = document.createElement("td");
    co.className="company"; co.textContent = d.company || "—";
    if (isNew){ const b=document.createElement("span"); b.className="newbadge"; b.textContent="NEW"; co.appendChild(b); }
    tr.appendChild(co);

    const cy = document.createElement("td");
    cy.textContent = d.country || "—"; tr.appendChild(cy);

    const pt = document.createElement("td");
    if (d.project_type && d.project_type!=="none"){
      const sp=document.createElement("span"); sp.className="ptype";
      sp.textContent=d.project_type; pt.appendChild(sp);
    } else { pt.textContent="—"; }
    tr.appendChild(pt);

    const dt = document.createElement("td");
    dt.className = "date";
    dt.textContent = d.published_date;
    tr.appendChild(dt);

    const fd = document.createElement("td");
    fd.className = "found";
    fd.textContent = d.found || "—";
    tr.appendChild(fd);

    const su = document.createElement("td");
    su.className="summary"; su.textContent = d.summary || "—"; tr.appendChild(su);

    const ln = document.createElement("td");
    if (d.url){
      const a=document.createElement("a"); a.className="src"; a.href=d.url;
      a.target="_blank"; a.rel="noopener"; a.title="Open source"; a.innerHTML=EXT_ICON; ln.appendChild(a);
    } else { ln.textContent="—"; }
    tr.appendChild(ln);

    tb.appendChild(tr);
  }

  document.getElementById("empty").style.display = total? "none":"block";
  document.getElementById("stat-shown").textContent = total;
  document.getElementById("stat-hi").textContent = rows.filter(d=>d.score>=7).length;
  document.getElementById("count-line").textContent =
     total + " lead" + (total===1?"":"s") + " shown";

  updateShowing(total ? from + 1 : 0, from + pageRows.length, total);
  renderPager(pages);

  // header sort indicators
  document.querySelectorAll("thead th.sortable").forEach(th=>{
    th.classList.remove("sorted-asc","sorted-desc");
    if (th.dataset.key===sortKey) th.classList.add(sortDir<0?"sorted-desc":"sorted-asc");
  });
}

/* ---------------------------------------------------------------------------
   Pagination controls. Entirely client-side over the already-embedded DATA —
   no network calls, so the file stays portable and works offline.
--------------------------------------------------------------------------- */

// "Showing X-Y of N", faded out and back so the number change is noticeable
// without moving anything on the page.
function updateShowing(x, y, n){
  const el = document.getElementById("showing");
  const text = n
    ? ("Showing " + x + "–" + y + " of " + n + " lead" + (n===1?"":"s"))
    : "No leads to show";
  if (el.textContent === text) return;          // nothing changed, don't blink
  if (REDUCE_MOTION){ el.textContent = text; return; }
  el.classList.add("fading");
  setTimeout(()=>{ el.textContent = text; el.classList.remove("fading"); }, 180);
}

// Which page numbers to show. Up to 7 pages: all of them. Beyond that:
// first, last, the current page and its neighbours, with an ellipsis per gap.
function pageList(cur, pages){
  if (pages <= 7) return Array.from({length:pages}, (_,i)=>i+1);
  const out = [1];
  const lo = Math.max(2, cur-1), hi = Math.min(pages-1, cur+1);
  if (lo > 2) out.push("…");
  for (let i=lo; i<=hi; i++) out.push(i);
  if (hi < pages-1) out.push("…");
  out.push(pages);
  return out;
}

function renderPager(pages){
  const nav = document.getElementById("pager");
  nav.innerHTML = "";
  const mk = (html, opt)=>{
    const b = document.createElement("button");
    b.type = "button";                          // real button: keyboard + focus-visible
    b.className = "pgbtn" + (opt.active ? " active" : "");
    b.innerHTML = html;
    if (opt.label) b.setAttribute("aria-label", opt.label);
    if (opt.active) b.setAttribute("aria-current", "page");
    if (opt.disabled) b.disabled = true;
    if (!opt.disabled && !opt.active && opt.go)
      b.addEventListener("click", ()=>{ page = opt.go; render(); });
    return b;
  };
  nav.appendChild(mk(CHEV_L, {disabled: page<=1,     go: page-1, label:"Previous page"}));
  for (const p of pageList(page, pages)){
    if (p === "…"){
      const s = document.createElement("span");
      s.className = "pgap"; s.textContent = "…"; s.setAttribute("aria-hidden","true");
      nav.appendChild(s);
      continue;
    }
    nav.appendChild(mk(String(p), {active: p===page, go: p, label:"Page "+p}));
  }
  nav.appendChild(mk(CHEV_R, {disabled: page>=pages, go: page+1, label:"Next page"}));
}

// Any change to the FILTERED SET starts again at page 1 — staying on page 7 of
// a set that just shrank to 2 pages is disorienting. Re-sorting counts too.
function refilter(){ page = 1; render(); }

// events
document.getElementById("f-score").addEventListener("input", e=>{
  document.getElementById("score-val").textContent = e.target.value; refilter();
});
document.getElementById("f-country").addEventListener("change", refilter);
document.querySelectorAll(".f-src").forEach(c=>c.addEventListener("change", refilter));
document.getElementById("f-reload").addEventListener("click", refilter);
document.getElementById("f-rpp").addEventListener("change", e=>{
  perPage = +e.target.value || 10; refilter();
});
document.querySelectorAll("thead th.sortable").forEach(th=>{
  th.addEventListener("click", ()=>{
    const k = th.dataset.key;
    if (sortKey===k){ sortDir *= -1; } else { sortKey=k; sortDir=-1; }
    refilter();
  });
});

/* =====================================================================
   Excel export — self-contained, offline, zero-dependency .xlsx writer.
   Builds an OOXML (SpreadsheetML) workbook and packages it as a STORE
   (uncompressed) ZIP entirely in the browser. Header row is styled via
   xl/styles.xml (Bastak green fill #32a337, bold white font) — a level of
   cell styling the free SheetJS community build cannot produce.
   ===================================================================== */
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n=0;n<256;n++){ let c=n; for(let k=0;k<8;k++) c=(c&1)?(0xEDB88320^(c>>>1)):(c>>>1); t[n]=c>>>0; }
  return t;
})();
function crc32(bytes){
  let c = 0xFFFFFFFF;
  for (let i=0;i<bytes.length;i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c>>>8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}
function colLetter(n){ let s=""; while(n>0){ const m=(n-1)%26; s=String.fromCharCode(65+m)+s; n=Math.floor((n-1)/26); } return s; }
function xmlEsc(s){
  return String(s).replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;" }[c]))
                  .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, "");
}
function zipStore(files){
  const enc = new TextEncoder();
  const u16 = v => [v&0xFF,(v>>8)&0xFF];
  const u32 = v => [v&0xFF,(v>>8)&0xFF,(v>>16)&0xFF,(v>>24)&0xFF];
  const chunks=[]; const central=[]; let offset=0;
  for (const f of files){
    const nameBytes = enc.encode(f.name);
    const crc = crc32(f.data), size = f.data.length;
    const local = [].concat(
      u32(0x04034b50), u16(20), u16(0), u16(0), u16(0), u16(0),
      u32(crc), u32(size), u32(size), u16(nameBytes.length), u16(0));
    chunks.push(new Uint8Array(local), nameBytes, f.data);
    central.push({nameBytes, crc, size, offset});
    offset += local.length + nameBytes.length + size;
  }
  const cdir=[]; let cdirSize=0;
  for (const c of central){
    const h = [].concat(
      u32(0x02014b50), u16(20), u16(20), u16(0), u16(0), u16(0), u16(0),
      u32(c.crc), u32(c.size), u32(c.size), u16(c.nameBytes.length),
      u16(0), u16(0), u16(0), u16(0), u32(0), u32(c.offset));
    const arr = new Uint8Array(h.length + c.nameBytes.length);
    arr.set(h,0); arr.set(c.nameBytes, h.length);
    cdir.push(arr); cdirSize += arr.length;
  }
  const eocd = new Uint8Array([].concat(
    u32(0x06054b50), u16(0), u16(0), u16(central.length), u16(central.length),
    u32(cdirSize), u32(offset), u16(0)));
  return new Blob([...chunks, ...cdir, eocd],
    {type:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"});
}
function buildXlsx(headers, rows){
  const enc = new TextEncoder();
  const contentTypes =
`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>`;
  const rels =
`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>`;
  const workbook =
`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="Leads" sheetId="1" r:id="rId1"/></sheets>
</workbook>`;
  const wbRels =
`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>`;
  // fillId 2 = Bastak green solid; fontId 1 = bold white. cellXfs index 1 = styled header.
  const styles =
`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF32A337"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center"/></xf></cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>`;
  let sheetRows = "";
  let hcells = "";
  headers.forEach((h,i)=>{
    hcells += `<c r="${colLetter(i+1)}1" t="inlineStr" s="1"><is><t xml:space="preserve">${xmlEsc(h)}</t></is></c>`;
  });
  sheetRows += `<row r="1">${hcells}</row>`;
  rows.forEach((row, ri)=>{
    const r = ri+2; let cells="";
    row.forEach((cell,ci)=>{
      const ref = colLetter(ci+1)+r;
      if (cell && typeof cell==="object" && cell.t==="n" && cell.v!=null && cell.v!==""){
        cells += `<c r="${ref}"><v>${cell.v}</v></c>`;
      } else {
        const v = (cell && typeof cell==="object") ? (cell.v!=null?cell.v:"") : (cell!=null?cell:"");
        cells += `<c r="${ref}" t="inlineStr"><is><t xml:space="preserve">${xmlEsc(v)}</t></is></c>`;
      }
    });
    sheetRows += `<row r="${r}">${cells}</row>`;
  });
  const dim = `A1:${colLetter(headers.length)}${rows.length+1}`;
  const cols = `<cols><col min="1" max="1" width="8"/><col min="2" max="2" width="28"/><col min="3" max="3" width="16"/><col min="4" max="4" width="22"/><col min="5" max="5" width="15"/><col min="6" max="6" width="62"/><col min="7" max="7" width="42"/></cols>`;
  const sheet =
`<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="${dim}"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>${cols}<sheetData>${sheetRows}</sheetData></worksheet>`;
  return zipStore([
    {name:"[Content_Types].xml",        data: enc.encode(contentTypes)},
    {name:"_rels/.rels",                data: enc.encode(rels)},
    {name:"xl/workbook.xml",            data: enc.encode(workbook)},
    {name:"xl/_rels/workbook.xml.rels", data: enc.encode(wbRels)},
    {name:"xl/styles.xml",              data: enc.encode(styles)},
    {name:"xl/worksheets/sheet1.xml",   data: enc.encode(sheet)},
  ]);
}

// Rows matching every active filter AND within the chosen published-date range.
function exportRows(){
  const minScore = +document.getElementById("f-score").value;
  const country = document.getElementById("f-country").value;
  const srcs = activeSources();
  const start = document.getElementById("f-start").value;
  const end = document.getElementById("f-end").value;
  const rows = DATA.filter(d=>{
    if (d.score < minScore) return false;
    if (country && d.country !== country) return false;
    if (!srcs.includes(d.source_cat)) return false;
    if (start && d.published_date < start) return false;
    if (end && d.published_date > end) return false;
    return true;
  });
  sortRows(rows);
  return rows;
}
function downloadExcel(){
  const rows = exportRows();
  if (!rows.length){ alert("No leads match the current filters and date range."); return; }
  const headers = ["Score","Company","Country","Project Type","Published Date","Summary","Source URL"];
  const data = rows.map(d=>[
    {v: d.score||0, t:"n"},
    d.company || "",
    d.country || "",
    (d.project_type && d.project_type!=="none") ? d.project_type : "",
    d.published_date || "",
    d.summary || "",
    d.url || "",
  ]);
  const blob = buildXlsx(headers, data);
  const start = document.getElementById("f-start").value || "start";
  const end = document.getElementById("f-end").value || "end";
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `leads_${start}_to_${end}.xlsx`;
  document.body.appendChild(a); a.click();
  setTimeout(()=>{ URL.revokeObjectURL(a.href); a.remove(); }, 1500);
}
document.getElementById("f-dl").addEventListener("click", downloadExcel);

// Prefill the date pickers with the full span of published dates.
(function initDates(){
  const dated = DATA.map(d=>d.published_date).filter(Boolean).sort();
  if (dated.length){
    document.getElementById("f-start").value = dated[0];
    document.getElementById("f-end").value = dated[dated.length-1];
  }
})();

render();  // default: published_date, newest first
</script>
</body>
</html>
"""


def main() -> None:
    if not Path(DB_PATH).exists():
        raise SystemExit("intel.db not found — run collect.py first.")
    conn = sqlite3.connect(DB_PATH)
    ensure_columns(conn)

    cutoff = (date.today() - timedelta(days=FRESH_DAYS)).isoformat()
    rows = load_rows(conn, cutoff)
    conn.close()

    fresh_count = len(rows)
    # "New" = PUBLISHED within the last 10 days (never the scrape date).
    recent_since = (date.today() - timedelta(days=10)).isoformat()
    new_count = sum(1 for r in rows if r["published_date"] >= recent_since)

    data_json = json.dumps(rows, ensure_ascii=False).replace("</", "<\\/")
    generated = datetime.now().strftime("%Y-%m-%d %H:%M")

    html = (HTML_TEMPLATE
            .replace("__LOGO_IMG__", logo_img_tag())
            .replace("__DATA_JSON__", data_json)
            .replace("__GENERATED__", generated)
            .replace("__FRESH_COUNT__", str(fresh_count))
            .replace("__NEW_COUNT__", str(new_count))
            .replace("__RECENT_SINCE__", recent_since)
            .replace("__FRESH_DAYS__", str(FRESH_DAYS))
            .replace("__CUTOFF__", cutoff))
    OUT_PATH.write_text(html, encoding="utf-8")

    pub_dates = sorted(r["published_date"] for r in rows)
    prng = f"{pub_dates[0]} .. {pub_dates[-1]}" if pub_dates else "n/a"
    print(f"Wrote {OUT_PATH.name}")
    print(f"  fresh leads (published within last {FRESH_DAYS}d, since {cutoff}): {fresh_count}")
    print(f"  new (published in last 10 days, since {recent_since}): {new_count}")
    print(f"  published-date range shown: {prng}")


if __name__ == "__main__":
    main()
