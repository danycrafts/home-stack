#!/bin/sh
set -eu

if [ -z "${CERTBOT_DOMAINS:-}" ]; then
  exit 0
fi

for domain in $CERTBOT_DOMAINS; do
  cert_dir="/etc/letsencrypt/live/$domain"
  if [ -f "$cert_dir/fullchain.pem" ] && [ -f "$cert_dir/privkey.pem" ]; then
    continue
  fi

  mkdir -p "$cert_dir"
  openssl req \
    -x509 \
    -nodes \
    -newkey rsa:2048 \
    -days 1 \
    -keyout "$cert_dir/privkey.pem" \
    -out "$cert_dir/fullchain.pem" \
    -subj "/CN=$domain" \
    -addext "subjectAltName=DNS:$domain" >/dev/null 2>&1
  cp "$cert_dir/fullchain.pem" "$cert_dir/cert.pem"
  cp "$cert_dir/fullchain.pem" "$cert_dir/chain.pem"
done
