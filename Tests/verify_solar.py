#!/usr/bin/env python3
"""Diffs SolarCheck's output against `astral`, an independent implementation.

    swift run SolarCheck > /tmp/swift_times.csv
    python3 Tests/verify_solar.py /tmp/swift_times.csv

astral keys each event to a UTC calendar date, so for western longitudes its
"sunset on the 5th" is the previous local evening. We therefore compare each
computed time against astral's value for the day before, of, and after, and take
the nearest - that isolates numerical error from calendar convention.
"""
import csv, datetime, sys
from astral import Observer
from astral.sun import sunrise, sunset, golden_hour, SunDirection

UTC = datetime.timezone.utc
DAY = datetime.timedelta(days=1)
TOLERANCE = 90  # seconds

def parse(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None

def nearest(fn, obs, date, mine):
    best = None
    for offset in (-1, 0, 1):
        try:
            theirs = fn(obs, date + offset * DAY)
        except ValueError:
            continue  # Sun never reaches that altitude on that day.
        delta = abs((mine - theirs).total_seconds())
        if best is None or delta < best:
            best = delta
    return best

EVENTS = {
    "sunrise":    lambda o, d: sunrise(o, d, tzinfo=UTC),
    "sunset":     lambda o, d: sunset(o, d, tzinfo=UTC),
    "golden_set": lambda o, d: golden_hour(o, d, SunDirection.SETTING, tzinfo=UTC)[0],
}

rows = list(csv.DictReader(open(sys.argv[1])))
diffs = {k: [] for k in EVENTS}
failures = []

for r in rows:
    obs = Observer(latitude=float(r["lat"]), longitude=float(r["lon"]), elevation=0)
    date = datetime.date.fromisoformat(r["date"])
    for key, fn in EVENTS.items():
        mine = parse(r[key])
        if mine is None:
            continue
        delta = nearest(fn, obs, date, mine)
        if delta is None:
            continue
        diffs[key].append(delta)
        if delta > TOLERANCE:
            failures.append((r["site"], r["date"], key, delta))

print(f"compared {len(rows)} site-days against astral\n")
for key, values in diffs.items():
    if not values:
        continue
    values.sort()
    print(f"  {key:11s} n={len(values):4d}  "
          f"median={values[len(values)//2]:5.1f}s  "
          f"p95={values[int(len(values)*0.95)]:5.1f}s  "
          f"max={values[-1]:6.1f}s")
print()

if failures:
    print(f"{len(failures)} of {sum(len(v) for v in diffs.values())} comparisons exceed {TOLERANCE}s:")
    for f in failures[:20]:
        print(f"  {f[0]:14s} {f[1]} {f[2]:11s} delta={f[3]:.0f}s")
    sys.exit(1)
print(f"PASS - all {sum(len(v) for v in diffs.values())} comparisons within {TOLERANCE}s of astral")
