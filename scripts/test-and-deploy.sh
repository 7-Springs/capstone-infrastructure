#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERIFY_PUSHED="${VERIFY_PUSHED:-1}" "$SCRIPT_DIR/test.sh"
"$SCRIPT_DIR/deploy.sh"
