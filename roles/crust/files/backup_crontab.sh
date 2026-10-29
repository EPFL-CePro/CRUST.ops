#!/bin/bash
#
# Copies the Zammad backups to the NAS share.
# The backups themselves are made every day by the zammad-backup service
# (see BACKUP_TIME and HOLD_DAYS in the .env file); this script only exports them.
# Run by cron, see roles/crust/tasks/run.yml.

set -euo pipefail

STACK_DIR=/data/crust
DEST=/data/crust/NAS-backup
KEEP_DAYS=30

cd "$STACK_DIR"

if ! mountpoint -q "$DEST"; then
    echo "$(date -Is) $DEST is not mounted, nothing copied" >&2
    exit 1
fi

docker compose cp zammad-backup:/var/tmp/zammad/. "$DEST/"
find "$DEST" -type f -mtime +"$KEEP_DAYS" -delete

echo "$(date -Is) backups copied to $DEST"
