#!/bin/sh
# Release entrypoint: runs the app under Litestream replication when
# LITESTREAM_ENABLED=true (the DB is restored first if the volume is empty),
# otherwise starts the server directly. See docs/ROBUSTNESS_PLAN.md 8.4.
set -eu

if [ "${LITESTREAM_ENABLED:-false}" = "true" ]; then
  # Fresh volume (new machine / region move): restore the latest replica
  # before the app boots. No-op when the database file already exists.
  if [ ! -f "$DATABASE_PATH" ]; then
    echo "No database at $DATABASE_PATH — restoring from Litestream replica (if any)"
    litestream restore -if-replica-exists -config /app/litestream.yml "$DATABASE_PATH"
  fi

  exec litestream replicate -exec "/app/bin/server" -config /app/litestream.yml
else
  exec /app/bin/server
fi
