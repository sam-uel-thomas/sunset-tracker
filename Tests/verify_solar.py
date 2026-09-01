#!/usr/bin/env python3
"""Diffs SolarCheck's output against `astral`, an independent implementation.

    swift run SolarCheck > /tmp/swift_times.csv
    python3 Tests/verify_solar.py /tmp/swift_times.csv

Two things this harness has to be careful about, both of which produced
convincing-looking wrong answers before being handled:

1. astral keys each event to a UTC calendar date, so for western longitudes its
   "sunset on the 5th" is the previous local evening. Each computed time is
   therefore compared against astral's value for the day before, of, and after,
   and the nearest is taken — that isolates numerical error from calendar
   convention.

2. A crossing time is only well determined if the sun passes the target
   altitude steeply. Golden hour (+6°) is the only target meaningfully above
   the horizon, and at high latitude on a short day the sun grazes it: dt/d(alt)
   blows up and two correct implementations can differ by many minutes. Sunrise
   and sunset do not have this problem at these latitudes, so those are what the
   exit status is based on. Golden hour is reported for information.
"""
import csv, datetime, sys
from astral import Observer
from astral.sun import sunrise, sunset, golden_hour, noon, elevation, SunDirection

UTC = datetime.timezone.utc
DAY = datetime.timedelta(days=1)

TOLERANCE = 90          # seconds; USNO itself only publishes to the minute
GRAZING_MARGIN = 3.0    # degrees of headroom above the target altitude
GOLDEN_ALTITUDE = 6.0

EVENTS = {
    "sunrise":    lambda o, d: sunrise(o, d, tzinfo=UTC),
    "sunset":     lambda o, d: sunset(o, d, tzinfo=UTC),
    "golden_set": lambda o, d: golden_hour(o, d, SunDirection.SETTING, tzinfo=UTC)[0],
}
# Only these decide pass/fail. See note 2 above.
GATED = {"sunrise", "sunset"}


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


def peak_elevation(obs, date):
    """The sun's altitude at solar noon: its headroom above any lower target."""
    try:
        return elevation(obs, noon(obs, date, tzinfo=UTC))
    except Exception:
        return None


rows = list(csv.DictReader(open(sys.argv[1])))
diffs = {k: [] for k in EVENTS}
failures = []
grazing = []

for r in rows:
    obs = Observer(latitude=float(r["lat"]), longitude=float(r["lon"]), elevation=0)
    date = datetime.date.fromisoformat(r["date"])
    peak = peak_elevation(obs, date)

    for key, fn in EVENTS.items():
        mine = parse(r[key])
        if mine is None:
            continue
        delta = nearest(fn, obs, date, mine)
        if delta is None:
            continue

        if key == "golden_set" and peak is not None and peak - GOLDEN_ALTITUDE < GRAZING_MARGIN:
            grazing.append((r["site"], r["date"], peak, delta))
            continue

        diffs[key].append(delta)
        if key in GATED and delta > TOLERANCE:
            failures.append((r["site"], r["date"], key, delta))

print(f"compared {len(rows)} site-days against astral\n")
for key, values in diffs.items():
    if not values:
        continue
    values.sort()
    mark = "" if key in GATED else "   (informational)"
    print(f"  {key:11s} n={len(values):4d}  "
          f"median={values[len(values)//2]:5.1f}s  "
          f"p95={values[int(len(values) * 0.95)]:5.1f}s  "
          f"max={values[-1]:6.1f}s{mark}")
print()

if grazing:
    worst = max(g[3] for g in grazing)
    print(f"excluded {len(grazing)} grazing golden-hour days — peak sun within "
          f"{GRAZING_MARGIN:g}° of {GOLDEN_ALTITUDE:g}°, so the crossing time is "
          f"ill-conditioned (worst spread {worst:.0f}s):")
    for site, date, peak, delta in sorted(grazing, key=lambda g: -g[3])[:5]:
        print(f"    {site:14s} {date}  peak {peak:.1f}°  spread {delta:.0f}s")
    print()

gated_n = sum(len(diffs[k]) for k in GATED)
if failures:
    print(f"FAIL — {len(failures)} of {gated_n} sunrise/sunset comparisons exceed {TOLERANCE}s:")
    for site, date, key, delta in failures[:20]:
        print(f"    {site:14s} {date} {key:11s} delta={delta:.0f}s")
    sys.exit(1)

worst = max((max(diffs[k]) for k in GATED if diffs[k]), default=0)
print(f"PASS — all {gated_n} sunrise/sunset comparisons within {TOLERANCE}s "
      f"(worst {worst:.0f}s)")
