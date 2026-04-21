#!/bin/bash
# =============================================================================
# Initialize Nginx Proxy Manager via REST API (IaC)
# All proxy hosts use HTTPS with SSL forced
# =============================================================================
set -e

NPM_URL="http://nginx-proxy-manager:81"
DOMAIN="${DOMAIN_NAME:-invariantcontinuum.io}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@invariantcontinuum.io}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-changeme}"

# Public hosts managed here:
#   - app.<DOMAIN>      -> Docker host gateway:3535
#   - auth.<DOMAIN>     -> keycloak:8080
#   - docs.<DOMAIN>     -> Docker host gateway:8190
#   - pgadmin.<DOMAIN>  -> pgadmin:80
#   - n8n.<DOMAIN>      -> n8n:5678
# The Substrate frontend keeps handling /api, /jobs, /ingest and /auth
# internally in its own nginx config. NPM's job is hostname routing and
# preserving forwarded headers so upstreams generate correct absolute URLs.
APP_SUBDOMAIN="${APP_SUBDOMAIN:-app}"
KC_SUBDOMAIN="${KC_SUBDOMAIN:-auth}"
DOCS_SUBDOMAIN="${DOCS_SUBDOMAIN:-docs}"
PGADMIN_SUBDOMAIN="${PGADMIN_SUBDOMAIN:-pgadmin}"
N8N_SUBDOMAIN="${N8N_SUBDOMAIN:-n8n}"
HOST_GATEWAY_IP=$(getent hosts host.docker.internal 2>/dev/null | awk 'NR==1 {print $1}')
HOST_GATEWAY_IP="${HOST_GATEWAY_IP:-host.docker.internal}"

echo "============================================================================="
echo "  NPM IaC Provisioner"
echo "  Domain: ${DOMAIN}"
echo "  HTTPS: Enabled (SSL Forced)"
echo "============================================================================="
echo ""

echo "⏳ Waiting for Nginx Proxy Manager API..."
until curl -sf "${NPM_URL}/api/" >/dev/null 2>&1; do
    sleep 3
done
echo "✓ NPM API is ready"
echo ""

# ─── Authenticate (try custom creds first, fall back to defaults) ──────────────
get_token() {
    local email=$1
    local pass=$2
    curl -sf -X POST "${NPM_URL}/api/tokens" \
        -H "Content-Type: application/json" \
        -d "{\"identity\":\"${email}\",\"secret\":\"${pass}\"}" 2>/dev/null \
        | grep -o '"token":"[^"]*"' | cut -d'"' -f4
}

echo "🔐 Authenticating..."
TOKEN=$(get_token "${ADMIN_EMAIL}" "${ADMIN_PASSWORD}")
if [ -z "$TOKEN" ]; then
    echo "  → Trying default NPM credentials..."
    TOKEN=$(get_token "admin@example.com" "changeme")
    if [ -z "$TOKEN" ]; then
        echo "ERROR: Cannot authenticate with NPM" >&2
        exit 1
    fi
    echo "  ✓ Logged in with default credentials"

    # Update admin user to our desired email/password
    echo "  → Updating admin credentials..."
    USER_ID=$(curl -sf "${NPM_URL}/api/users" \
        -H "Authorization: Bearer ${TOKEN}" | \
        grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')

    curl -sf -X PUT "${NPM_URL}/api/users/${USER_ID}" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"Admin\",\"nickname\":\"admin\",\"email\":\"${ADMIN_EMAIL}\",\"roles\":[\"admin\"]}" >/dev/null

    curl -sf -X PUT "${NPM_URL}/api/users/${USER_ID}/auth" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"password\",\"current\":\"changeme\",\"secret\":\"${ADMIN_PASSWORD}\"}" >/dev/null

    echo "  ✓ Admin credentials updated to ${ADMIN_EMAIL}"

    # Re-authenticate with new credentials
    TOKEN=$(get_token "${ADMIN_EMAIL}" "${ADMIN_PASSWORD}")
fi

echo "✓ Authenticated as ${ADMIN_EMAIL}"
echo ""

# ─── Helper: request Let's Encrypt certificate ───────────────────────────────
request_letsencrypt_cert() {
    local fqdn=$1

    # Check if cert already exists
    existing_cert=$(curl -sf "${NPM_URL}/api/nginx/certificates" \
        -H "Authorization: Bearer ${TOKEN}" | \
        grep -o "\"${fqdn}\"" | head -1 || echo "")

    if [ -n "$existing_cert" ]; then
        # Return existing cert ID
        curl -sf "${NPM_URL}/api/nginx/certificates" \
            -H "Authorization: Bearer ${TOKEN}" | \
            python3 -c "import sys,json; certs=json.load(sys.stdin); [print(c['id']) for c in certs if '${fqdn}' in c.get('domain_names',[])]" 2>/dev/null | head -1
        return 0
    fi

    # Request new Let's Encrypt certificate
    cert_response=$(curl -sf -X POST "${NPM_URL}/api/nginx/certificates" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\":[\"${fqdn}\"],
            \"meta\":{},
            \"provider\":\"letsencrypt\"
        }" 2>&1)

    echo "$cert_response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null
}

# ─── Helper: get proxy host ID by FQDN ───────────────────────────────────────
get_proxy_host_id() {
    local fqdn=$1
    curl -sf "${NPM_URL}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer ${TOKEN}" | \
        python3 -c "import sys,json; hosts=json.load(sys.stdin); [print(h['id']) for h in hosts if '${fqdn}' in h.get('domain_names',[])]" 2>/dev/null | head -1
}

# ─── Helper: create or update proxy host with HTTPS + Let's Encrypt ──────────
create_proxy_host_https() {
    local subdomain=$1
    local forward_host=$2
    local forward_port=$3
    local advanced_config="${4:-}"
    local fqdn="${subdomain}.${DOMAIN}"

    # Request Let's Encrypt certificate
    echo "  ⏳ Requesting Let's Encrypt cert for ${fqdn}..."
    cert_id=$(request_letsencrypt_cert "${fqdn}")

    # Build certificate_id field if cert was obtained
    local cert_field=""
    if [ -n "$cert_id" ] && [ "$cert_id" != "null" ]; then
        cert_field="\"certificate_id\":${cert_id},"
        echo "  🔒 Certificate obtained (ID: ${cert_id})"
    else
        echo "  ⚠  Certificate request failed, proceeding without SSL cert"
    fi

    # Build advanced_config field
    local adv_field=""
    if [ -n "$advanced_config" ]; then
        # Escape newlines and quotes for JSON
        local escaped_config
        escaped_config=$(echo "$advanced_config" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")' 2>/dev/null || echo "\"\"")
        adv_field="\"advanced_config\":${escaped_config},"
    fi

    # Check if proxy host already exists
    host_id=$(get_proxy_host_id "${fqdn}")

    if [ -n "$host_id" ] && [ "$host_id" != "null" ]; then
        echo "  🔄 Updating existing proxy host ${fqdn} (ID: ${host_id})..."
        curl -sf -X PUT "${NPM_URL}/api/nginx/proxy-hosts/${host_id}" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"domain_names\":[\"${fqdn}\"],
                \"forward_scheme\":\"http\",
                \"forward_host\":\"${forward_host}\",
                \"forward_port\":${forward_port},
                ${cert_field}
                ${adv_field}
                \"block_exploits\":true,
                \"allow_websocket_upgrade\":true,
                \"http2_support\":true,
                \"caching_enabled\":true,
                \"ssl_forced\":true,
                \"hsts_enabled\":true,
                \"hsts_subdomains\":true,
                \"trust_forwarded_proto\":true,
                \"enabled\":true,
                \"meta\":{\"letsencrypt_agree\":false,\"dns_challenge\":false}
            }" >/dev/null
        echo "  ✓ ${fqdn} → ${forward_host}:${forward_port} (updated, HTTPS + Let's Encrypt)"
    else
        echo "  🆕 Creating proxy host ${fqdn}..."
        curl -sf -X POST "${NPM_URL}/api/nginx/proxy-hosts" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "{
                \"domain_names\":[\"${fqdn}\"],
                \"forward_scheme\":\"http\",
                \"forward_host\":\"${forward_host}\",
                \"forward_port\":${forward_port},
                ${cert_field}
                ${adv_field}
                \"block_exploits\":true,
                \"allow_websocket_upgrade\":true,
                \"http2_support\":true,
                \"caching_enabled\":true,
                \"ssl_forced\":true,
                \"hsts_enabled\":true,
                \"hsts_subdomains\":true,
                \"trust_forwarded_proto\":true,
                \"enabled\":true,
                \"meta\":{\"letsencrypt_agree\":false,\"dns_challenge\":false}
            }" >/dev/null
        echo "  ✓ ${fqdn} → ${forward_host}:${forward_port} (created, HTTPS + Let's Encrypt)"
    fi
}

# ─── Prune any proxy hosts outside the managed public set ────────────────────
APP_FQDN="${APP_SUBDOMAIN}.${DOMAIN}"
KC_FQDN="${KC_SUBDOMAIN}.${DOMAIN}"
DOCS_FQDN="${DOCS_SUBDOMAIN}.${DOMAIN}"
PGADMIN_FQDN="${PGADMIN_SUBDOMAIN}.${DOMAIN}"
N8N_FQDN="${N8N_SUBDOMAIN}.${DOMAIN}"

echo "🧹 Pruning any proxy hosts outside the managed set..."
hosts_json=$(curl -sf "${NPM_URL}/api/nginx/proxy-hosts" \
    -H "Authorization: Bearer ${TOKEN}" || echo "[]")

to_delete=$(echo "$hosts_json" | python3 -c "
import json, sys
hosts = json.load(sys.stdin)
keep = {'${APP_FQDN}', '${KC_FQDN}', '${DOCS_FQDN}', '${PGADMIN_FQDN}', '${N8N_FQDN}'}
for h in hosts:
    names = h.get('domain_names', [])
    if not any(n in keep for n in names):
        print(f\"{h['id']}|{','.join(names)}\")
" 2>/dev/null || echo "")

if [ -z "$to_delete" ]; then
    echo "  ✓ Nothing to prune."
else
    while IFS='|' read -r host_id host_names; do
        [ -z "$host_id" ] && continue
        echo "  🗑  Deleting proxy host ${host_names} (ID: ${host_id})"
        curl -sf -X DELETE "${NPM_URL}/api/nginx/proxy-hosts/${host_id}" \
            -H "Authorization: Bearer ${TOKEN}" >/dev/null || true
    done <<< "$to_delete"
fi
echo ""

# ─── Create managed public proxy hosts ───────────────────────────────────────
echo "🌐 Provisioning public proxy hosts"
echo ""

# Shared forwarded headers for browser-facing upstreams. NPM sets several of
# these already, but keeping them explicit in advanced config avoids surprises
# when upstream apps validate redirect URLs or rely on the original scheme.
COMMON_PROXY_HEADERS='proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Port 443;'

APP_ADVANCED_CONFIG='proxy_redirect http://$host:3000/ /;
proxy_redirect https://$host:3000/ /;
proxy_redirect http://$host:3000 /;
proxy_redirect https://$host:3000 /;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
'"${COMMON_PROXY_HEADERS}"

KEYCLOAK_ADVANCED_CONFIG='proxy_redirect off;
'"${COMMON_PROXY_HEADERS}"

PGADMIN_ADVANCED_CONFIG='proxy_redirect off;
'"${COMMON_PROXY_HEADERS}"

N8N_ADVANCED_CONFIG='proxy_redirect off;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
'"${COMMON_PROXY_HEADERS}"

DOCS_ADVANCED_CONFIG='proxy_redirect off;
'"${COMMON_PROXY_HEADERS}"

create_proxy_host_https "${APP_SUBDOMAIN}" "${HOST_GATEWAY_IP}" 3535 "$APP_ADVANCED_CONFIG"
# Keycloak and pgAdmin are served by the substrate compose stack (ports 8080 / 5050)
create_proxy_host_https "${KC_SUBDOMAIN}" "${HOST_GATEWAY_IP}" 8080 "$KEYCLOAK_ADVANCED_CONFIG"
create_proxy_host_https "${DOCS_SUBDOMAIN}" "${HOST_GATEWAY_IP}" 8190 "$DOCS_ADVANCED_CONFIG"
create_proxy_host_https "${PGADMIN_SUBDOMAIN}" "${HOST_GATEWAY_IP}" 5050 "$PGADMIN_ADVANCED_CONFIG"
create_proxy_host_https "${N8N_SUBDOMAIN}" "n8n" 5678 "$N8N_ADVANCED_CONFIG"
echo ""

echo "============================================================================="
echo "  ✓ IaC Provisioning Complete"
echo "============================================================================="
echo ""
echo "Public:"
echo "  → https://${APP_FQDN}                (Substrate Frontend)"
echo "  → https://${KC_FQDN}                 (Keycloak)"
echo "  → https://${DOCS_FQDN}               (Substrate Docs)"
echo "  → https://${PGADMIN_FQDN}            (pgAdmin)"
echo "  → https://${N8N_FQDN}                (n8n)"
echo ""
echo "Local admin/debug ports:"
echo "  → http://localhost:81                (NPM admin)"
echo "  → other infra services on their published ports"
echo ""
echo "Note: if Let's Encrypt cert issuance failed, it can be retried"
echo "      manually from the NPM admin UI."
echo ""
