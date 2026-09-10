#!/bin/sh
# Backward-compatible developer shortcut. The root installer owns collision safety.
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd)
exec "$ROOT/install.sh" --claude "$@"
