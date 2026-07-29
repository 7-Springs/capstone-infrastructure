#!/usr/bin/env bash
set -Eeuo pipefail

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_JOB="${JENKINS_JOB:-capstone-frontend-ci}"
JENKINS_OUTPUT="${JENKINS_OUTPUT:-/home/fenixfire/Desktop/jenkins-output.txt}"
JENKINS_AUTH_FILE="${JENKINS_AUTH_FILE:-$HOME/.capstone-jenkins-auth}"

usage() {
  cat <<'EOF'
Usage: jenkins-capstone-ci.sh <command> [build-number]

Commands:
  trigger          Start the capstone-frontend-ci pipeline.
  status           Show recent build statuses.
  fetch [build]    Save console output for build, or lastBuild when omitted.
  wait [build]     Poll until build, or lastBuild when omitted, finishes.

Auth:
  Set JENKINS_AUTH="user:api-token" or create ~/.capstone-jenkins-auth.
EOF
}

auth() {
  if [[ -n "${JENKINS_AUTH:-}" ]]; then
    printf '%s' "$JENKINS_AUTH"
    return
  fi

  if [[ -f "$JENKINS_AUTH_FILE" ]]; then
    sed -n '1p' "$JENKINS_AUTH_FILE"
    return
  fi

  printf 'Missing Jenkins auth. Set JENKINS_AUTH or create %s.\n' "$JENKINS_AUTH_FILE" >&2
  exit 1
}

api_json() {
  curl -g -fsS -u "$(auth)" "$@"
}

api_post() {
  local url="$1"
  local response_file
  response_file="$(mktemp)"

  local http_status
  http_status="$(curl -sS -o "$response_file" -w '%{http_code}' -u "$(auth)" -X POST "$url")"

  if [[ "$http_status" == "403" ]]; then
    local crumb_json
    crumb_json="$(api_json "$JENKINS_URL/crumbIssuer/api/json")"
    local crumb_field
    local crumb
    crumb_field="$(printf '%s' "$crumb_json" | node -pe 'const data=JSON.parse(require("fs").readFileSync(0,"utf8")); data.crumbRequestField')"
    crumb="$(printf '%s' "$crumb_json" | node -pe 'const data=JSON.parse(require("fs").readFileSync(0,"utf8")); data.crumb')"
    http_status="$(curl -sS -o "$response_file" -w '%{http_code}' -u "$(auth)" -H "$crumb_field: $crumb" -X POST "$url")"
  fi

  if [[ "$http_status" != "200" && "$http_status" != "201" && "$http_status" != "302" ]]; then
    printf 'Jenkins POST failed with HTTP %s.\n' "$http_status" >&2
    sed -n '1,120p' "$response_file" >&2
    rm -f "$response_file"
    exit 1
  fi

  rm -f "$response_file"
}

job_url() {
  printf '%s/job/%s' "$JENKINS_URL" "$JENKINS_JOB"
}

build_json() {
  local build="$1"
  api_json "$(job_url)/$build/api/json?tree=number,building,result,url"
}

json_value() {
  local key="$1"
  node -pe "const data=JSON.parse(require('fs').readFileSync(0,'utf8')); const value=data['$key']; value === null || value === undefined ? '' : value"
}

last_build_number() {
  api_json "$(job_url)/api/json?tree=lastBuild[number]" | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).lastBuild.number'
}

trigger() {
  api_post "$(job_url)/build"
  printf 'Triggered %s.\n' "$JENKINS_JOB"
  status
}

status() {
  local json
  json="$(api_json "$(job_url)/api/json?tree=lastBuild[number,building,result,url],lastCompletedBuild[number,result,url],builds[number,building,result,url]{0,8}")"
  printf '%s' "$json" | node -e '
    const fs = require("fs");
    const data = JSON.parse(fs.readFileSync(0, "utf8"));
    for (const build of data.builds ?? []) {
      const state = build.building ? "RUNNING" : build.result;
      console.log(`#${build.number} ${state} ${build.url}`);
    }
  '
}

fetch_console() {
  local build="${1:-lastBuild}"
  api_json "$(job_url)/$build/consoleText" -o "$JENKINS_OUTPUT"
  printf 'Saved %s console output to %s.\n' "$build" "$JENKINS_OUTPUT"
  tail -n 40 "$JENKINS_OUTPUT"
}

wait_for_build() {
  local build="${1:-}"
  if [[ -z "$build" ]]; then
    build="$(last_build_number)"
  fi

  printf 'Waiting for %s #%s...\n' "$JENKINS_JOB" "$build"
  while true; do
    local json
    json="$(build_json "$build")"
    local building
    local result
    building="$(printf '%s' "$json" | json_value building)"
    result="$(printf '%s' "$json" | json_value result)"

    if [[ "$building" != "true" ]]; then
      printf '#%s finished: %s\n' "$build" "$result"
      fetch_console "$build" >/dev/null
      tail -n 80 "$JENKINS_OUTPUT"
      [[ "$result" == "SUCCESS" ]]
      return
    fi

    printf '#%s still running...\n' "$build"
    sleep "${JENKINS_POLL_SECONDS:-15}"
  done
}

command="${1:-}"
case "$command" in
  trigger)
    trigger
    ;;
  status)
    status
    ;;
  fetch)
    fetch_console "${2:-lastBuild}"
    ;;
  wait)
    wait_for_build "${2:-}"
    ;;
  -h|--help|help|'')
    usage
    ;;
  *)
    printf 'Unknown command: %s\n\n' "$command" >&2
    usage >&2
    exit 1
    ;;
esac
