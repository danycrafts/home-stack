#!/bin/bash
# =============================================================================
# Initialize Nginx Proxy Manager via REST API
# =============================================================================
set -e

NPM_URL="http://localhost:81"
DOMAIN="${DOMAIN_NAME:-invariantcontinuum.io}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@invariantcontinuum.io}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-invariant}"
PGADMIN_SUBDOMAIN="${PGADMIN_SUBDOMAIN:-pgadmin}"
KC_SUBDOMAIN="${KC_SUBDOMAIN:-keycloak}"
N8N_SUBDOMAIN="${N8N_SUBDOMAIN:-n8n}"
NPM_SUBDOMAIN="${NPM_ADMIN_SUBDOMAIN:-npm}"

echo "Waiting for Nginx Proxy Manager API..."
until curl -sf "${NPM_URL}/api/" >/dev/null 2>&1; do
    sleep 3
done
echo "✓ NPM API is ready"

# ─── Authenticate (try custom creds first, fall back to defaults) ──────────────
get_token() {
    local email=$1
    local pass=$2
    curl -sf -X POST "${NPM_URL}/api/tokens" \
        -H "Content-Type: application/json" \
        -d "{\"identity\":\"${email}\",\"secret\":\"${pass}\"}" 2>/dev/null \
        | grep -o '"token":"[^"]*"' | cut -d'"' -f4
}

TOKEN=$(get_token "${ADMIN_EMAIL}" "${ADMIN_PASSWORD}")
if [ -z "$TOKEN" ]; then
    echo "Trying default NPM credentials..."
    TOKEN=$(get_token "admin@example.com" "changeme")
    if [ -z "$TOKEN" ]; then
        echo "ERROR: Cannot authenticate with NPM" >&2
        exit 1
    fi
    echo "✓ Logged in with default credentials"

    # Update admin user to our desired email/password
    echo "Updating admin credentials..."
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

    echo "✓ Admin credentials updated to ${ADMIN_EMAIL}"

    # Re-authenticate with new credentials
    TOKEN=$(get_token "${ADMIN_EMAIL}" "${ADMIN_PASSWORD}")
fi

echo "✓ Authenticated as ${ADMIN_EMAIL}"

# ─── Helper: create proxy host if not exists ──────────────────────────────────
create_proxy_host() {
    local subdomain=$1
    local forward_host=$2
    local forward_port=$3
    local fqdn="${subdomain}.${DOMAIN}"

    # Check if already exists
    existing=$(curl -sf "${NPM_URL}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer ${TOKEN}" | \
        grep -o "\"${fqdn}\"" | head -1 || echo "")

    if [ -n "$existing" ]; then
        echo "  ✓ Already exists: ${fqdn}"
        return
    fi

    curl -sf -X POST "${NPM_URL}/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\":[\"${fqdn}\"],
            \"forward_scheme\":\"http\",
            \"forward_host\":\"${forward_host}\",
            \"forward_port\":${forward_port},
            \"block_exploits\":true,
            \"allow_websocket_upgrade\":true,
            \"http2_support\":false,
            \"caching_enabled\":false,
            \"ssl_forced\":false,
            \"hsts_enabled\":false,
            \"hsts_subdomains\":false,
            \"enabled\":true,
            \"meta\":{\"letsencrypt_agree\":false,\"dns_challenge\":false}
        }" >/dev/null

    echo "  ✓ Created: ${fqdn} → ${forward_host}:${forward_port}"
}

# ─── Create proxy hosts ───────────────────────────────────────────────────────
echo "Creating proxy hosts for domain: ${DOMAIN}"
create_proxy_host "${PGADMIN_SUBDOMAIN}" "pgadmin" 80
create_proxy_host "${KC_SUBDOMAIN}"      "keycloak" 8080
create_proxy_host "${N8N_SUBDOMAIN}"     "n8n"     5678
create_proxy_host "${NPM_SUBDOMAIN}"     "nginx-proxy-manager" 81

echo ""
echo "✓ Proxy configuration complete:"
echo "  http://${PGADMIN_SUBDOMAIN}.${DOMAIN}"
echo "  http://${KC_SUBDOMAIN}.${DOMAIN}"
echo "  http://${N8N_SUBDOMAIN}.${DOMAIN}"
echo "  http://${NPM_SUBDOMAIN}.${DOMAIN}"
