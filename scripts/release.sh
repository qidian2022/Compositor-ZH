#!/bin/sh
# Build the independent Chinese preview; no upstream signing or updater credentials.
set -eu
cd "$(dirname "$0")/.."
exec python3 localization/package.py "$@"
