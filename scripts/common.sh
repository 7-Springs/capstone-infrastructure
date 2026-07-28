#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="${BACKEND_DIR:-$ROOT_DIR/capstone-backend}"
FRONTEND_DIR="${FRONTEND_DIR:-$ROOT_DIR/capstone-frontend}"

DEPLOY_HOST="${DEPLOY_HOST:-98.95.137.137}"
DEPLOY_USER="${DEPLOY_USER:-admin}"
DEPLOY_KEY="${DEPLOY_KEY:-$HOME/Desktop/LightsailDefaultKey-us-east-1.pem}"
REMOTE_BACKEND_DIR="${REMOTE_BACKEND_DIR:-~/src/capstone-backend}"
REMOTE_FRONTEND_DIR="${REMOTE_FRONTEND_DIR:-~/src/capstone-frontend}"
FRONTEND_WEB_ROOT="${FRONTEND_WEB_ROOT:-/var/www/capstone-frontend/browser}"
UPLOAD_MAX_BODY_SIZE="${UPLOAD_MAX_BODY_SIZE:-25M}"
NPM_CACHE_DIR="${NPM_CACHE_DIR:-$HOME/.npm-cache}"
PREBUILT_FRONTEND_DIR="${PREBUILT_FRONTEND_DIR:-}"

TEST_DATABASE_URL="${TEST_DATABASE_URL:-postgresql://capstone_test:capstone_test@localhost:5432/capstone_test?schema=public}"
RUN_BACKEND="${RUN_BACKEND:-1}"
RUN_FRONTEND="${RUN_FRONTEND:-1}"
RUN_JEST="${RUN_JEST:-1}"
RUN_FRONTEND_BUILD="${RUN_FRONTEND_BUILD:-1}"
RUN_PLAYWRIGHT="${RUN_PLAYWRIGHT:-1}"
SKIP_PLAYWRIGHT="${SKIP_PLAYWRIGHT:-0}"
INSTALL_PLAYWRIGHT="${INSTALL_PLAYWRIGHT:-1}"
PLAYWRIGHT_WITH_DEPS="${PLAYWRIGHT_WITH_DEPS:-0}"
SKIP_DEPLOY="${SKIP_DEPLOY:-0}"
LOCAL_DEPLOY="${LOCAL_DEPLOY:-}"
SERVER_GIT_REF="${SERVER_GIT_REF:-origin/main}"
VERIFY_PUSHED="${VERIFY_PUSHED:-0}"

KEY_COPY=""

cleanup_key_copy() {
  if [[ -n "$KEY_COPY" && -f "$KEY_COPY" ]]; then
    rm -f "$KEY_COPY"
  fi
}

section() {
  printf '\n==> %s\n' "$1"
}

run() {
  printf '+ %s\n' "$*"
  "$@"
}

require_dir() {
  if [[ ! -d "$1" ]]; then
    printf 'Missing required directory: %s\n' "$1" >&2
    exit 1
  fi
}

resolve_deploy_mode() {
  if [[ -n "$LOCAL_DEPLOY" ]]; then
    return
  fi

  if [[ ! -f "$DEPLOY_KEY" && -d "$BACKEND_DIR/.git" && -d "$FRONTEND_DIR/.git" ]]; then
    LOCAL_DEPLOY=1
    return
  fi

  LOCAL_DEPLOY=0
}

prepare_key() {
  if [[ ! -f "$DEPLOY_KEY" ]]; then
    printf 'Deploy key not found: %s\n' "$DEPLOY_KEY" >&2
    printf 'If you are running this on the server, rerun with LOCAL_DEPLOY=1 or from a checkout that has local backend/frontend repos.\n' >&2
    exit 1
  fi

  KEY_COPY="$(mktemp /tmp/capstone-deploy-key.XXXXXX.pem)"
  cp "$DEPLOY_KEY" "$KEY_COPY"
  chmod 600 "$KEY_COPY"
}

ensure_pushed() {
  local repo_dir="$1"
  local label="$2"

  if [[ "$VERIFY_PUSHED" != "1" ]]; then
    return
  fi

  section "Checking $label git state"
  run git -C "$repo_dir" fetch origin main

  local head
  local upstream
  head="$(git -C "$repo_dir" rev-parse HEAD)"
  upstream="$(git -C "$repo_dir" rev-parse origin/main)"

  if [[ "$head" != "$upstream" ]]; then
    printf '%s HEAD is not pushed to origin/main.\n' "$label" >&2
    printf 'Local:  %s\nRemote: %s\n' "$head" "$upstream" >&2
    printf 'Commit and push first, then rerun this deploy.\n' >&2
    exit 1
  fi
}
