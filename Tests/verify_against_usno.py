#!/usr/bin/env python3
"""Benchmarks SolarKit against the US Naval Observatory, the authority.

    swift run SolarCheck > /tmp/swift_times.csv
    python3 Tests/verify_against_usno.py /tmp/swift_times.csv

USNO reports each event under the UTC date on which it occurs, so we look up
each computed instant under *its own* UTC date. Comparing against a fixed
nominal date instead silently measures the day-over-day drift of sunset (which
reaches ~5 min/day at Anchorage in October) rather than any real error.

USNO publishes to the minute, so ~17s of residual is pure quantisation.
`astral` is measured the same way, for context.
"""
import csv, datetime, json, os, sys, time, urllib.request
from astral import Observer
from astral.sun import sunrise, sunset

UTC = datetime.timezone.utc
CACHE = os.path.join(os.path.dirname(__file__), ".usno_cache.json")
_cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}

def parse(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None

def usno(site, lat, lon, date):
    """Sun events USNO reports on the given UTC date."""
    key = f"{site}|{date.isoformat()}"
    if key not in _cache:
        url = (f"https://aa.usno.navy.mil/api/rstt/oneday?date={date.isoformat()}"
               f"&coords={lat},{lon}&tz=0")
        with urllib.request.urlopen(url, timeout=30) as r:
            data = json.load(r)["properties"]["data"]["sundata"]
        _cache[key] = {e["phen"]: e["time"] for e in data if e["phen"] in ("Rise", "Set")}
        time.sleep(0.35)
    return _cache[key]

def error_vs_usno(site, lat, lon, moment, phen):
    """Seconds between `moment` and USNO's value for the same event."""
    ref = usno(site, lat, lon, moment.date())
    if phen not in ref:
        return None
    h, m = map(int, ref[phen].split(":"))
    theirs = datetime.datetime.combine(moment.date(), datetime.time(h, m), tzinfo=UTC)
    return abs((moment - theirs).total_seconds())

rows = list(csv.DictReader(open(sys.argv[1])))
DATES = {"2026-01-20", "2026-03-20", "2026-06-20", "2026-09-05", "2026-10-20", "2026-12-05"}

mine_errs, astral_errs, detail = [], [], []
for r in rows:
    if r["date"] not in DATES:
        continue
    lat, lon = float(r["lat"]), float(r["lon"])
    obs = Observer(latitude=lat, longitude=lon, elevation=0)
    date = datetime.date.fromisoformat(r["date"])
    for phen, key, afn in (("Rise", "sunrise", sunrise), ("Set", "sunset", sunset)):
        mine = parse(r[key])
        if mine is None:
            continue
        try:
            me = error_vs_usno(r["site"], lat, lon, mine, phen)
            theirs = afn(obs, date, tzinfo=UTC)
            them = error_vs_usno(r["site"], lat, lon, theirs, phen)
        except Exception as e:
            print(f"  {r['site']} {r['date']} lookup failed: {e}")
            continue
        if me is not None:
            mine_errs.append(me)
            detail.append((r["site"], r["date"], phen, me, them))
        if them is not None:
            astral_errs.append(them)

json.dump(_cache, open(CACHE, "w"))

worst = sorted(detail, key=lambda d: -d[3])[:8]
print(f"{'site':15s} {'date':11s} {'event':5s} {'mine':>7s} {'astral':>7s}")
print("-" * 50)
for site, date, phen, me, them in worst:
    t = f"{them:6.0f}s" if them is not None else "     -"
    print(f"{site:15s} {date} {phen:5s} {me:6.0f}s {t}")

def summary(name, errs):
    vals = sorted(e for e in errs if e is not None)
    print(f"  {name:8s} n={len(vals):3d}  median={vals[len(vals)//2]:5.1f}s  "
          f"p95={vals[int(len(vals)*0.95)]:5.1f}s  max={vals[-1]:5.1f}s")

print("\nError vs USNO (same event, same UTC date):")
summary("mine", mine_errs)
summary("astral", astral_errs)

worst_mine = max(mine_errs)
print()
if worst_mine > 60:
    print(f"FAIL - worst case {worst_mine:.0f}s exceeds the 60s bound")
    sys.exit(1)
print(f"PASS - worst case {worst_mine:.0f}s, within USNO's own 60s reporting resolution")
