#!/bin/sh
set -eu

config="${SING_BOX_CONFIG:-/var/lib/sing-box/config.json}"
owner="${SING_BOX_OWNER:-sing-box:sing-box}"
url="${SUB_STORE_URL:?SUB_STORE_URL is required}"
curl_bin="${CURL_BIN:-curl}"
sing_box_bin="${SING_BOX_BIN:-/usr/bin/sing-box}"
systemctl_bin="${SYSTEMCTL_BIN:-systemctl}"

tmp="$(mktemp "${config}.XXXXXX")"
backup="${config}.previous"

cleanup() {
  rm -f "$tmp"
}
trap cleanup 0 1 2 15

"$curl_bin" \
  --fail \
  --silent \
  --show-error \
  --location \
  --retry 3 \
  --connect-timeout 10 \
  --max-time 120 \
  --noproxy '*' \
  "$url" \
  --output "$tmp"

"$sing_box_bin" check -c "$tmp"

if [ -f "$config" ] && cmp -s "$tmp" "$config"; then
  exit 0
fi

chown "$owner" "$tmp"
chmod 0640 "$tmp"

if [ -f "$config" ]; then
  cp -p "$config" "$backup"
fi

mv -f "$tmp" "$config"

if ! "$systemctl_bin" restart sing-box.service; then
  if [ -f "$backup" ]; then
    mv -f "$backup" "$config"
    "$systemctl_bin" restart sing-box.service || true
  fi
  exit 1
fi
