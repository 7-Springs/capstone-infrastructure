#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

test_backend() {
  if [[ "$RUN_BACKEND" != "1" ]]; then
    section "Skipping backend tests"
    return
  fi

  section "Backend tests"
  run npm --prefix "$BACKEND_DIR" ci --cache "$NPM_CACHE_DIR" --prefer-offline
  run npm --prefix "$BACKEND_DIR" run prisma:generate
  run npm --prefix "$BACKEND_DIR" run build
  (
    cd "$BACKEND_DIR"
    printf '+ TEST_DATABASE_URL=%s npm run test:e2e\n' "$TEST_DATABASE_URL"
    TEST_DATABASE_URL="$TEST_DATABASE_URL" npm run test:e2e
  )
}

test_frontend() {
  if [[ "$RUN_FRONTEND" != "1" ]]; then
    section "Skipping frontend tests"
    return
  fi

  if [[ "$RUN_JEST" == "1" ]]; then
    section "Frontend Jest tests"
    run npm --prefix "$FRONTEND_DIR" ci --cache "$NPM_CACHE_DIR" --prefer-offline
    run npm --prefix "$FRONTEND_DIR" test -- --runInBand
  elif [[ "$RUN_FRONTEND_BUILD" == "1" || ( "$SKIP_PLAYWRIGHT" != "1" && "$RUN_PLAYWRIGHT" == "1" ) ]]; then
    run npm --prefix "$FRONTEND_DIR" ci --cache "$NPM_CACHE_DIR" --prefer-offline
  fi

  if [[ "$RUN_FRONTEND_BUILD" == "1" ]]; then
    section "Frontend build"
    run npm --prefix "$FRONTEND_DIR" run build
  fi

  if [[ "$SKIP_PLAYWRIGHT" == "1" || "$RUN_PLAYWRIGHT" != "1" ]]; then
    printf 'Skipping Playwright because SKIP_PLAYWRIGHT=%s and RUN_PLAYWRIGHT=%s\n' "$SKIP_PLAYWRIGHT" "$RUN_PLAYWRIGHT"
  else
    section "Playwright tests"
    (
      cd "$FRONTEND_DIR"
      if [[ "$INSTALL_PLAYWRIGHT" == "1" ]]; then
        if [[ "$PLAYWRIGHT_WITH_DEPS" == "1" ]]; then
          printf '+ npx playwright install --with-deps chromium\n'
          npx playwright install --with-deps chromium
        else
          printf '+ npx playwright install chromium\n'
          npx playwright install chromium
        fi
      fi
      printf '+ npx playwright test\n'
      npx playwright test
    )
  fi
}

main() {
  require_dir "$BACKEND_DIR"
  require_dir "$FRONTEND_DIR"

  ensure_pushed "$BACKEND_DIR" "Backend"
  ensure_pushed "$FRONTEND_DIR" "Frontend"
  test_backend
  test_frontend

  section "Done"
  printf 'Capstone tests passed.\n'
}

main "$@"
