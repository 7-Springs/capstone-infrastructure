#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
trap cleanup_key_copy EXIT

retry_command() {
  local attempts="$1"
  shift

  local attempt
  for attempt in $(seq 1 "$attempts"); do
    if "$@"; then
      return 0
    fi

    if [[ "$attempt" == "$attempts" ]]; then
      return 1
    fi

    printf 'Command failed, retrying in 5 seconds (%s/%s): %s\n' "$attempt" "$attempts" "$*" >&2
    sleep 5
  done
}

deploy_server() {
  if [[ "$SKIP_DEPLOY" == "1" ]]; then
    section "Skipping deploy"
    printf 'SKIP_DEPLOY=1, so production was not changed.\n'
    return
  fi

  if [[ "$LOCAL_DEPLOY" == "1" ]]; then
    section "Deploying on local server"
    (
      set -Eeuo pipefail
      NGINX_BIN="$(command -v nginx || true)"
      if [[ -z "$NGINX_BIN" && -x /usr/sbin/nginx ]]; then
        NGINX_BIN=/usr/sbin/nginx
      fi
      if [[ -n "$NGINX_BIN" ]]; then
        printf 'client_max_body_size %s;\n' "$UPLOAD_MAX_BODY_SIZE" | sudo tee /etc/nginx/conf.d/capstone-upload-size.conf >/dev/null
        sudo "$NGINX_BIN" -t
        sudo systemctl reload nginx
      fi

      cd "$BACKEND_DIR"
      git fetch origin main
      git reset --hard "$SERVER_GIT_REF"
      npm ci --cache "$NPM_CACHE_DIR" --prefer-offline
      npm run prisma:generate
      npm run prisma:deploy
      npm run build
      pm2 reload ecosystem.config.cjs --update-env
      pm2 save

      if [[ -n "$PREBUILT_FRONTEND_DIR" ]]; then
        if [[ ! -d "$PREBUILT_FRONTEND_DIR" ]]; then
          printf 'Prebuilt frontend directory not found: %s\n' "$PREBUILT_FRONTEND_DIR" >&2
          exit 1
        fi
        FRONTEND_SOURCE_DIR="$PREBUILT_FRONTEND_DIR"
      else
        cd "$FRONTEND_DIR"
        git fetch origin main
        git reset --hard "$SERVER_GIT_REF"
        npm ci --cache "$NPM_CACHE_DIR" --prefer-offline
        npm run build
        FRONTEND_SOURCE_DIR="$FRONTEND_DIR/dist/capstone-frontend/browser"
      fi

      sudo mkdir -p "$FRONTEND_WEB_ROOT"
      sudo rsync -av --delete "$FRONTEND_SOURCE_DIR/" "$FRONTEND_WEB_ROOT/"
    )
    return
  fi

  prepare_key

  section "Deploying to $DEPLOY_USER@$DEPLOY_HOST"
  retry_command 3 ssh -i "$KEY_COPY" \
    -o BatchMode=yes \
    -o ConnectTimeout=30 \
    -o ServerAliveInterval=10 \
    -o StrictHostKeyChecking=no \
    "$DEPLOY_USER@$DEPLOY_HOST" \
    "set -Eeuo pipefail
      NGINX_BIN=\"\$(command -v nginx || true)\"
      if [[ -z \"\$NGINX_BIN\" && -x /usr/sbin/nginx ]]; then
        NGINX_BIN=/usr/sbin/nginx
      fi
      if [[ -n \"\$NGINX_BIN\" ]]; then
        printf 'client_max_body_size %s;\n' '$UPLOAD_MAX_BODY_SIZE' | sudo tee /etc/nginx/conf.d/capstone-upload-size.conf >/dev/null
        sudo \"\$NGINX_BIN\" -t
        sudo systemctl reload nginx
      fi

      cd $REMOTE_BACKEND_DIR
      git fetch origin main
      git reset --hard $SERVER_GIT_REF
      npm ci --cache \"\$HOME/.npm-cache\" --prefer-offline
      npm run prisma:generate
      npm run prisma:deploy
      npm run build
      pm2 reload ecosystem.config.cjs --update-env
      pm2 save"

  if [[ -n "$PREBUILT_FRONTEND_DIR" ]]; then
    if [[ ! -d "$PREBUILT_FRONTEND_DIR" ]]; then
      printf 'Prebuilt frontend directory not found: %s\n' "$PREBUILT_FRONTEND_DIR" >&2
      exit 1
    fi

    section "Uploading prebuilt frontend"
    remote_upload_dir="/tmp/capstone-frontend-browser-${DEPLOY_USER}-$$"
    retry_command 3 ssh -i "$KEY_COPY" \
      -o BatchMode=yes \
      -o ConnectTimeout=30 \
      -o ServerAliveInterval=10 \
      -o StrictHostKeyChecking=no \
      "$DEPLOY_USER@$DEPLOY_HOST" \
      "rm -rf $remote_upload_dir && mkdir -p $remote_upload_dir"
    retry_command 3 rsync -av --delete \
      -e "ssh -i $KEY_COPY -o BatchMode=yes -o ConnectTimeout=30 -o ServerAliveInterval=10 -o StrictHostKeyChecking=no" \
      "$PREBUILT_FRONTEND_DIR/" \
      "$DEPLOY_USER@$DEPLOY_HOST:$remote_upload_dir/"
    retry_command 3 ssh -i "$KEY_COPY" \
      -o BatchMode=yes \
      -o ConnectTimeout=30 \
      -o ServerAliveInterval=10 \
      -o StrictHostKeyChecking=no \
      "$DEPLOY_USER@$DEPLOY_HOST" \
      "sudo mkdir -p $FRONTEND_WEB_ROOT
       sudo rsync -av --delete $remote_upload_dir/ $FRONTEND_WEB_ROOT/
       rm -rf $remote_upload_dir"
    return
  fi

  section "Building frontend on $DEPLOY_USER@$DEPLOY_HOST"
  retry_command 3 ssh -i "$KEY_COPY" \
    -o BatchMode=yes \
    -o ConnectTimeout=30 \
    -o ServerAliveInterval=10 \
    -o StrictHostKeyChecking=no \
    "$DEPLOY_USER@$DEPLOY_HOST" \
    "set -Eeuo pipefail
      cd $REMOTE_FRONTEND_DIR
      git fetch origin main
      git reset --hard $SERVER_GIT_REF
      npm ci --cache \"\$HOME/.npm-cache\" --prefer-offline
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
  resolve_deploy_mode

  VERIFY_PUSHED=1 ensure_pushed "$BACKEND_DIR" "Backend"
  VERIFY_PUSHED=1 ensure_pushed "$FRONTEND_DIR" "Frontend"
  deploy_server
  smoke_check

  section "Done"
  printf 'Capstone deployment completed.\n'
}

main "$@"
