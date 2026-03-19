#!/usr/bin/env bash
set -euo pipefail

# Deploy Echo frontend to Vercel by cloning AXIS at a pinned commit SHA
# and deploying the Next.js frontend.
#
# Usage:
#   ./ci/deploy-echo-frontend.sh --vercel-env production
#   ./ci/deploy-echo-frontend.sh --vercel-env preview --axis-ref abc1234
#
# Required env vars: VERCEL_TOKEN, VERCEL_ORG_ID, VERCEL_PROJECT_ID
# Optional env var:  AXIS_CLONE_TOKEN (for private AXIS repo)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Defaults ---
AXIS_REF=""
VERCEL_ENV=""
VERCEL_CLI_VERSION="${VERCEL_CLI_VERSION:-44.2.3}"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --axis-ref)   AXIS_REF="$2"; shift 2 ;;
    --vercel-env) VERCEL_ENV="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$VERCEL_ENV" ]]; then
  echo "Error: --vercel-env is required (production or preview)"
  exit 1
fi

# --- Resolve AXIS ref ---
if [[ -z "$AXIS_REF" ]]; then
  AXIS_REF="$(cat "$REPO_ROOT/ci/axis-version" | tr -d '[:space:]')"
  echo "Using AXIS ref from ci/axis-version: $AXIS_REF"
else
  echo "Using AXIS ref from --axis-ref override: $AXIS_REF"
fi

if [[ -z "$AXIS_REF" ]]; then
  echo "Error: No AXIS ref found. Set --axis-ref or populate ci/axis-version."
  exit 1
fi

# --- Validate SHA format ---
if [[ ! "$AXIS_REF" =~ ^[0-9a-f]{7,40}$ ]]; then
  echo "Error: AXIS ref '$AXIS_REF' is not a valid commit SHA."
  echo "Production deploys require a commit SHA, not a branch or tag name."
  exit 1
fi

# --- Check required env vars ---
for var in VERCEL_TOKEN VERCEL_ORG_ID VERCEL_PROJECT_ID; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: $var is not set"
    exit 1
  fi
done

# --- Export Vercel env vars for CLI ---
export VERCEL_TOKEN
export VERCEL_ORG_ID
export VERCEL_PROJECT_ID

# --- Create work directory ---
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
echo "Work directory: $WORK_DIR"

# --- Clone AXIS ---
echo "Cloning AXIS repo..."
CLONE_URL="https://github.com/ax-foundry/axis.git"
if [[ -n "${AXIS_CLONE_TOKEN:-}" ]]; then
  CLONE_URL="https://x-access-token:${AXIS_CLONE_TOKEN}@github.com/ax-foundry/axis.git"
fi

git clone --quiet "$CLONE_URL" "$WORK_DIR/axis"

# --- Validate SHA exists in repo ---
if ! git -C "$WORK_DIR/axis" cat-file -e "${AXIS_REF}^{commit}" 2>/dev/null; then
  echo "Error: Commit $AXIS_REF does not exist in the AXIS repo."
  echo "Verify the SHA is correct and has been pushed to origin."
  exit 1
fi

# --- Checkout pinned SHA ---
echo "Checking out AXIS at $AXIS_REF..."
git -C "$WORK_DIR/axis" checkout --quiet "$AXIS_REF"

FRONTEND_DIR="$WORK_DIR/axis/frontend"

if [[ ! -d "$FRONTEND_DIR" ]]; then
  echo "Error: $FRONTEND_DIR does not exist. Check AXIS repo structure."
  exit 1
fi

cd "$FRONTEND_DIR"

# --- Install Vercel CLI ---
echo "Installing Vercel CLI v${VERCEL_CLI_VERSION}..."
npm install -g "vercel@${VERCEL_CLI_VERSION}" --silent

# --- Pull Vercel project settings ---
VERCEL_PULL_ENV="preview"
if [[ "$VERCEL_ENV" == "production" ]]; then
  VERCEL_PULL_ENV="production"
fi
echo "Pulling Vercel project settings (environment: $VERCEL_PULL_ENV)..."
vercel pull --yes --environment="$VERCEL_PULL_ENV" --token "$VERCEL_TOKEN"

# --- Deploy ---
DEPLOY_FLAGS="--token $VERCEL_TOKEN --yes"
if [[ "$VERCEL_ENV" == "production" ]]; then
  DEPLOY_FLAGS="$DEPLOY_FLAGS --prod"
fi

echo "Deploying to Vercel ($VERCEL_ENV)..."
DEPLOY_OUTPUT=$(vercel deploy $DEPLOY_FLAGS 2>&1)
echo "$DEPLOY_OUTPUT"

# Extract deploy URL from "Production:" or "Preview:" line in Vercel output
DEPLOY_URL=$(echo "$DEPLOY_OUTPUT" | grep -E '^\s*(Production|Preview):' | grep -oE 'https://[^ ]+' | head -1)

if [[ -z "$DEPLOY_URL" ]]; then
  echo "Error: Failed to capture deploy URL from Vercel output."
  exit 1
fi

echo "Deploy URL: $DEPLOY_URL"

# Use FRONTEND_URL for smoke tests if set (required when the per-deployment alias
# URL is not routable, e.g. only the production domain is configured in Vercel).
SMOKE_URL="${FRONTEND_URL:-$DEPLOY_URL}"

# --- Smoke tests ---
echo ""
echo "=== Smoke Tests ==="

# Hard gate: frontend loads (hard fail for production, warning for preview)
echo "Checking frontend health (${SMOKE_URL})..."
CURL_FLAGS=(-fL -s -o /dev/null -w "%{http_code}" --max-time 30)
if [[ -n "${VERCEL_BYPASS_SECRET:-}" ]]; then
  CURL_FLAGS+=(-H "x-vercel-protection-bypass: ${VERCEL_BYPASS_SECRET}")
fi
HTTP_CODE=$(curl "${CURL_FLAGS[@]}" "$SMOKE_URL" || true)
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "PASS: Frontend returned HTTP $HTTP_CODE"
elif [[ "$VERCEL_ENV" == "production" ]]; then
  echo "FAIL: Frontend returned HTTP $HTTP_CODE (expected 200)"
  exit 1
else
  echo "WARNING: Frontend returned HTTP $HTTP_CODE — per-deployment URLs require wildcard domain config in Vercel to be routable"
fi

# Soft gate: API reachability (warn-only)
# TODO: make hard-fail after Gate 0a (Cloud Run auth) is resolved
echo "Checking API reachability..."
API_CODE=$(curl "${CURL_FLAGS[@]}" "$SMOKE_URL/api/config/theme" || true)
if [[ "$API_CODE" == "200" ]]; then
  echo "PASS: API returned HTTP $API_CODE"
else
  echo "WARNING: API returned HTTP $API_CODE (expected 200)"
  echo "This is expected if Cloud Run auth (Gate 0a) is not yet resolved."
fi

echo ""
echo "=== Deploy Complete ==="
echo "URL: $DEPLOY_URL"
echo "AXIS SHA: $AXIS_REF"
echo "Environment: $VERCEL_ENV"
