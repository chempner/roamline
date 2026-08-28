#!/bin/sh
set -eu

if [ "$(id -u)" = "0" ]; then
  mkdir -p /data/uploads
  if ! chown -R node:node /data; then
    echo "[roamline] Cannot make /data writable. Check the TrueNAS dataset ACL for the Roamline host path." >&2
    exit 1
  fi
  exec su-exec node:node "$@"
fi

mkdir -p /data/uploads
exec "$@"
