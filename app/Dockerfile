# Stage 1: dependency install
FROM node:22-alpine AS deps

# Install only production deps in a clean layer
WORKDIR /app
COPY package*.json ./
# Use the CodeArtifact-proxied registry injected at build time via --build-arg
ARG NPM_REGISTRY
RUN if [ -n "$NPM_REGISTRY" ]; then npm config set registry "$NPM_REGISTRY"; fi \
 && npm ci --omit=dev

# Stage 2: build/test
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
ARG NPM_REGISTRY
RUN if [ -n "$NPM_REGISTRY" ]; then npm config set registry "$NPM_REGISTRY"; fi \
 && npm ci
COPY src/ ./src/
RUN npm test

# Stage 3: production image
FROM node:22-alpine AS production

# Non-root user for least-privilege execution
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app
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
