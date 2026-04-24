#!/usr/bin/env bash
# setup-codeartifact.sh
# Configures npm and pip to use CodeArtifact as the package registry.
#
# Usage: setup-codeartifact.sh <domain> <domain-owner> <region> <npm-repo> [pip-repo]
set -euo pipefail

DOMAIN="$1"
DOMAIN_OWNER="$2"
REGION="$3"
NPM_REPO="${4:-${DOMAIN}-npm}"
PIP_REPO="${5:-${DOMAIN}-pip}"

echo "Fetching CodeArtifact authorization token ..."
TOKEN=$(aws codeartifact get-authorization-token \
  --domain "$DOMAIN" \
  --domain-owner "$DOMAIN_OWNER" \
  --region "$REGION" \
  --duration-seconds 900 \
  --query authorizationToken \
  --output text)

echo "Configuring npm ..."
NPM_ENDPOINT=$(aws codeartifact get-repository-endpoint \
  --domain "$DOMAIN" \
  --domain-owner "$DOMAIN_OWNER" \
  --repository "$NPM_REPO" \
  --format npm \
  --region "$REGION" \
  --query repositoryEndpoint \
  --output text)

NPM_HOST=$(echo "$NPM_ENDPOINT" | sed 's|https://||' | sed 's|/.*||')
npm config set registry "$NPM_ENDPOINT"
npm config set "//${NPM_HOST}/:_authToken" "$TOKEN"
npm config set "//${NPM_HOST}/:always-auth" true
echo "npm registry set to: ${NPM_ENDPOINT}"

echo "Configuring pip ..."
PIP_ENDPOINT=$(aws codeartifact get-repository-endpoint \
  --domain "$DOMAIN" \
  --domain-owner "$DOMAIN_OWNER" \
  --repository "$PIP_REPO" \
  --format pypi \
  --region "$REGION" \
  --query repositoryEndpoint \
  --output text)

PIP_INDEX_URL="${PIP_ENDPOINT%/}/simple/"
# Write pip config
mkdir -p ~/.config/pip
cat > ~/.config/pip/pip.conf <<EOF
[global]
index-url = https://aws:${TOKEN}@$(echo "$PIP_INDEX_URL" | sed 's|https://||')
EOF
echo "pip index-url configured."

echo "CodeArtifact setup complete."
