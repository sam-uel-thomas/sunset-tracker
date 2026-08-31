#!/bin/bash
# Verifies the solar math against two independent references.
#   Tests/run.sh            # both checks
#   Tests/run.sh --offline  # skip the USNO network check
set -euo pipefail
cd "$(dirname "$0")/.."

VENV="${VENV:-.venv}"
if [ ! -d "$VENV" ]; then
  echo "Creating $VENV..."
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q astral
fi

TIMES=$(mktemp -t solar_times).csv
swift run SolarCheck > "$TIMES"
echo "Computed $(( $(wc -l < "$TIMES") - 1 )) site-days."
echo

echo "== vs astral (independent implementation, offline) =="
"$VENV/bin/python" Tests/verify_solar.py "$TIMES"

if [ "${1:-}" != "--offline" ]; then
  echo
  echo "== vs US Naval Observatory (authoritative, network) =="
  "$VENV/bin/python" Tests/verify_against_usno.py "$TIMES"
fi
