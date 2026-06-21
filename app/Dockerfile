# Stage 1: dependency install
FROM node:22-alpine@sha256:ab07539e0988b63558ff621f5fbe1077054c39d9809112974fb79993949d41cd AS deps

WORKDIR /app
# Upgrade npm to pull latest security patches before installing app deps
RUN npm install -g npm@latest --no-audit --no-fund
COPY package*.json ./
# Use the CodeArtifact-proxied registry injected at build time via --build-arg
# NPM_TOKEN is set as _authToken (not embedded in URL) for npm v9+ compatibility
ARG NPM_REGISTRY
ARG NPM_TOKEN
RUN if [ -n "$NPM_REGISTRY" ]; then \
      HOST=$(echo "$NPM_REGISTRY" | sed 's|https://||' | sed 's|/.*||'); \
      npm config set registry "$NPM_REGISTRY"; \
      npm config set "//${HOST}/:_authToken" "$NPM_TOKEN"; \
    fi \
 && npm ci --omit=dev

# Stage 2: build/test
FROM node:22-alpine@sha256:ab07539e0988b63558ff621f5fbe1077054c39d9809112974fb79993949d41cd AS builder

WORKDIR /app
RUN npm install -g npm@latest --no-audit --no-fund
COPY package*.json ./
ARG NPM_REGISTRY
ARG NPM_TOKEN
RUN if [ -n "$NPM_REGISTRY" ]; then \
      HOST=$(echo "$NPM_REGISTRY" | sed 's|https://||' | sed 's|/.*||'); \
      npm config set registry "$NPM_REGISTRY"; \
      npm config set "//${HOST}/:_authToken" "$NPM_TOKEN"; \
    fi \
 && npm ci
COPY src/ ./src/
RUN npm test

# Stage 3: production image
FROM node:22-alpine@sha256:ab07539e0988b63558ff621f5fbe1077054c39d9809112974fb79993949d41cd AS production

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app
# Upgrade npm in the final image so the image scanner sees the patched version
RUN npm install -g npm@latest --no-audit --no-fund

COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/src ./src
COPY package.json .

USER appuser
EXPOSE 3000

ARG APP_VERSION=unknown
ENV APP_VERSION=${APP_VERSION}
ENV NODE_ENV=production

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "src/index.js"]
