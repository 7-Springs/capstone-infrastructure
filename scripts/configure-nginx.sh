#!/usr/bin/env bash
set -Eeuo pipefail

UPLOAD_MAX_BODY_SIZE="${UPLOAD_MAX_BODY_SIZE:-25M}"
NGINX_SITE="${NGINX_SITE:-/etc/nginx/conf.d/default.conf}"

NGINX_BIN="$(command -v nginx || true)"
if [[ -z "$NGINX_BIN" && -x /usr/sbin/nginx ]]; then
  NGINX_BIN=/usr/sbin/nginx
fi

if [[ -z "$NGINX_BIN" ]]; then
  exit 0
fi

printf 'client_max_body_size %s;\n' "$UPLOAD_MAX_BODY_SIZE" |
  sudo tee /etc/nginx/conf.d/capstone-upload-size.conf >/dev/null

if [[ -f "$NGINX_SITE" ]] &&
  sudo grep -q 'server_name app\.capstone-dev\.ddns\.net;' "$NGINX_SITE" &&
  ! sudo grep -q 'Capstone app-host API proxy' "$NGINX_SITE"; then
  tmp_file="$(mktemp)"
  sudo awk '
    /server_name app\.capstone-dev\.ddns\.net;/ {
      in_app_server = 1
    }

    in_app_server && /^[[:space:]]*server_name / && $0 !~ /app\.capstone-dev\.ddns\.net/ {
      in_app_server = 0
    }

    {
      print
    }

    in_app_server && !inserted && /^[[:space:]]*index index\.html;[[:space:]]*$/ {
      print ""
      print "    # Capstone app-host API proxy"
      print "    location /api/ {"
      print "        proxy_pass http://127.0.0.1:3000/api/;"
      print ""
      print "        proxy_http_version 1.1;"
      print ""
      print "        proxy_set_header Host $host;"
      print "        proxy_set_header X-Real-IP $remote_addr;"
      print "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
      print "        proxy_set_header X-Forwarded-Proto $scheme;"
      print ""
      print "        proxy_set_header Upgrade $http_upgrade;"
      print "        proxy_set_header Connection \"upgrade\";"
      print "    }"
      inserted = 1
    }

    END {
      if (!inserted) {
        exit 42
      }
    }
  ' "$NGINX_SITE" >"$tmp_file"
  sudo cp "$NGINX_SITE" "$NGINX_SITE.bak-$(date +%Y%m%d%H%M%S)"
  sudo cp "$tmp_file" "$NGINX_SITE"
  rm -f "$tmp_file"
fi

sudo "$NGINX_BIN" -t
sudo systemctl reload nginx
