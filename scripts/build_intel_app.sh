#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${(%):-%N}")" && pwd)"
exec "$SCRIPT_DIR/build_app.sh" --arch x86_64 "$@"
