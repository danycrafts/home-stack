FROM nginx:1.27-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        certbot \
        cron \
        curl \
        logrotate \
        openssl \
    && rm -rf /var/lib/apt/lists/*

COPY bin/certbot-issue /usr/local/bin/certbot-issue
COPY docker-entrypoint.d/*.sh /docker-entrypoint.d/

RUN chmod +x /usr/local/bin/certbot-issue /docker-entrypoint.d/*.sh \
    && mkdir -p /var/log/letsencrypt /var/www/certbot \
    && printf '%s\n' \
        'SHELL=/bin/sh' \
        'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
        '0 */12 * * * root certbot renew --webroot -w /var/www/certbot --deploy-hook "nginx -s reload" >> /var/log/letsencrypt/renew.log 2>&1' \
        '25 0 * * * root /usr/sbin/logrotate /etc/logrotate.d/nginx >> /var/log/nginx/logrotate.log 2>&1' \
        > /etc/cron.d/home-stack-nginx \
    && chmod 0644 /etc/cron.d/home-stack-nginx
