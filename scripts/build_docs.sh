#!/usr/bin/env bash
# Regenerate the static dbt docs site under docs/index.html.
# Run from the project root. Requires the local key-pair profile in
# ~/.dbt/profiles.yml (see docs/auth_setup.md).
#
# Usage:  ./scripts/build_docs.sh
#
# GitHub Pages serves docs/index.html as the site root; commit the regenerated
# file and push to publish.

set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d .venv ]; then
    echo "ERROR: .venv not found — see README 'Reproduce' section to set up." >&2
    exit 1
fi

source .venv/bin/activate

dbt deps
dbt docs generate --static
# We DO want the full catalog (column types per model) — it requires a live
# Snowflake connection at session start, so this script needs the local
# key-pair profile. The catalog query takes ~10s.

cp target/static_index.html docs/index.html
echo "Docs regenerated → docs/index.html ($(wc -c < docs/index.html | awk '{print $1/1024 " KB"}'))"
echo
echo "Next: git add docs/index.html && git commit -m '...' && git push"
