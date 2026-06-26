#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKEND_DIR="${BACKEND_DIR:-$ROOT_DIR/capstone-backend}"
FRONTEND_DIR="${FRONTEND_DIR:-$ROOT_DIR/capstone-frontend}"

DEPLOY_HOST="${DEPLOY_HOST:-18.209.136.92}"
DEPLOY_USER="${DEPLOY_USER:-admin}"
DEPLOY_KEY="${DEPLOY_KEY:-$HOME/Desktop/LightsailDefaultKey-us-east-1.pem}"
REMOTE_BACKEND_DIR="${REMOTE_BACKEND_DIR:-~/src/capstone-backend}"
REMOTE_FRONTEND_DIR="${REMOTE_FRONTEND_DIR:-~/src/capstone-frontend}"
FRONTEND_WEB_ROOT="${FRONTEND_WEB_ROOT:-/var/www/capstone-frontend/browser}"

TEST_DATABASE_URL="${TEST_DATABASE_URL:-postgresql://capstone_test:capstone_test@localhost:5432/capstone_test?schema=public}"
RUN_PLAYWRIGHT="${RUN_PLAYWRIGHT:-1}"
SKIP_DEPLOY="${SKIP_DEPLOY:-0}"
SERVER_GIT_REF="${SERVER_GIT_REF:-origin/main}"

KEY_COPY=""

cleanup() {
  if [[ -n "$KEY_COPY" && -f "$KEY_COPY" ]]; then
    rm -f "$KEY_COPY"
  fi
}
trap cleanup EXIT

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

prepare_key() {
  if [[ ! -f "$DEPLOY_KEY" ]]; then
    printf 'Deploy key not found: %s\n' "$DEPLOY_KEY" >&2
    exit 1
  fi

  KEY_COPY="$(mktemp /tmp/capstone-deploy-key.XXXXXX.pem)"
  cp "$DEPLOY_KEY" "$KEY_COPY"
  chmod 600 "$KEY_COPY"
}

ensure_pushed() {
  local repo_dir="$1"
  local label="$2"

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

test_backend() {
  section "Backend tests"
  run npm --prefix "$BACKEND_DIR" run build
  (
    cd "$BACKEND_DIR"
    printf '+ TEST_DATABASE_URL=%s npm run test:e2e\n' "$TEST_DATABASE_URL"
    TEST_DATABASE_URL="$TEST_DATABASE_URL" npm run test:e2e
  )
}

test_frontend() {
  section "Frontend tests"
  run npm --prefix "$FRONTEND_DIR" test -- --runInBand
  run npm --prefix "$FRONTEND_DIR" run build

  if [[ "$RUN_PLAYWRIGHT" == "1" ]]; then
    section "Playwright tests"
    (
      cd "$FRONTEND_DIR"
      printf '+ npx playwright test\n'
      npx playwright test
    )
  else
    printf 'Skipping Playwright because RUN_PLAYWRIGHT=%s\n' "$RUN_PLAYWRIGHT"
  fi
}

deploy_server() {
  if [[ "$SKIP_DEPLOY" == "1" ]]; then
    section "Skipping deploy"
    printf 'Verification passed. SKIP_DEPLOY=1, so production was not changed.\n'
    return
  fi

  prepare_key

  section "Deploying to $DEPLOY_USER@$DEPLOY_HOST"
  ssh -i "$KEY_COPY" \
    -o BatchMode=yes \
    -o ConnectTimeout=30 \
    -o ServerAliveInterval=10 \
    -o StrictHostKeyChecking=no \
    "$DEPLOY_USER@$DEPLOY_HOST" \
    "set -Eeuo pipefail
      cd $REMOTE_BACKEND_DIR
      git fetch origin main
      git reset --hard $SERVER_GIT_REF
      npm ci
      npm run prisma:generate
      npm run prisma:deploy
      npm run build
      pm2 reload ecosystem.config.cjs --update-env
      pm2 save

      cd $REMOTE_FRONTEND_DIR
      git fetch origin main
      git reset --hard $SERVER_GIT_REF
      npm ci
      npm run build
      sudo mkdir -p $FRONTEND_WEB_ROOT
      sudo rsync -av --delete dist/capstone-frontend/browser/ $FRONTEND_WEB_ROOT/"
}

smoke_check() {
  if [[ "$SKIP_DEPLOY" == "1" ]]; then
    return
  fi

  section "Smoke checks"
  run curl -I https://app.capstone-dev.ddns.net
  run curl -I https://api.capstone-dev.ddns.net/health
}

main() {
  require_dir "$BACKEND_DIR"
  require_dir "$FRONTEND_DIR"

  ensure_pushed "$BACKEND_DIR" "Backend"
  ensure_pushed "$FRONTEND_DIR" "Frontend"
  test_backend
  test_frontend
  deploy_server
  smoke_check

  section "Done"
  printf 'Capstone tests passed and deployment completed.\n'
}

main "$@"
