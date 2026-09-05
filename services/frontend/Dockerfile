FROM node:24.20-alpine3.24 AS builder

WORKDIR /app

# Require the lockfile for reproducible dependency installation.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.30.4-alpine-slim

# Runtime defaults.
# The value is intentionally empty so the envsubst template always
# resolves successfully when telemetry is disabled.
ENV APPLICATIONINSIGHTS_CONNECTION_STRING=""
ENV NGINX_ENVSUBST_FILTER="^APPLICATIONINSIGHTS_CONNECTION_STRING$"

# The unprivileged NGINX image automatically renders *.template files
# from /etc/nginx/templates into /etc/nginx/conf.d.
COPY --chown=101:101 \
    nginx.local.conf.template \
    /etc/nginx/templates/default.conf.template

COPY --chown=101:101 \
    --from=builder \
    /app/dist \
    /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK \
    --interval=30s \
    --timeout=5s \
    --start-period=10s \
    --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
