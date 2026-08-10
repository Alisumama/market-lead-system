"""
collect_worldbank.py — RETIRED. Intentionally does nothing.

The World Bank WDS *document* API (https://search.worldbank.org/api/v2/wds)
was dropped as a lead source on 2026-08-05. It is deliberately NOT wired into
run_daily.bat any more.

Why it was retired
------------------
WDS indexes the Bank's document archive, not live project pipelines. It has
effectively no recent milling content:

    query                                    matches
    "food security" OR grain OR wheat ...    199,274
    milling terms + bare "milling"             5,580
    milling phrases only                         891
    milling phrases, last 90 days                  0

Sorted newest-first, the newest document matching a milling-specific query is
from 2012-08-01; the rest are 1976-1981. So the only way this endpoint ever
produced volume was via broad terms like "food security", which pulled in
multi-country regional reports at ~100 docs/run against a ~1,200/day classify
capacity. Those rows also carried raw, non-project country strings
("Tajikistan", "World", "Western and Central Africa"), which surfaced as wrong
country tags on the dashboard.

Tightening the query does not rescue it — a correctly-scoped query returns ~0
recent documents. There is nothing to collect here.

The ~97 WDS rows already in intel.db were left in place on purpose (not
deleted); they simply stopped growing when this collector went inert.

Use instead
-----------
collect_worldbank_procurement.py — the procurement-notices API. Those are
actual tenders ("Supply and installation of milling equipment"), already
milling-scoped, and they write clean two-letter country codes.

If you ever need to revive this, restore it as a real collector only after
re-probing the API; do not reintroduce broad standalone terms
("food security", "grain", "wheat", "agriculture").
"""


def main() -> None:
    print("collect_worldbank.py is retired (WDS has no recent milling docs) — "
          "no action taken. See the module docstring; use "
          "collect_worldbank_procurement.py instead.")


if __name__ == "__main__":
    main()
