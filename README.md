# Echo

Deployment controller for the **Echo** frontend — MGT's observability and evaluation studio, powered by [AXIS](https://github.com/ax-foundry/axis).

This repo contains no application code and no config. Its sole job is to pin an AXIS commit SHA and deploy the AXIS Next.js frontend to Vercel.

## Architecture

```
Browser ──/api/*──> Vercel (Next.js) ──rewrite──> Cloud Run (FastAPI)
                     same-origin       INTERNAL_API_URL (server-side)
```

- All browser API calls use relative paths (`/api/...`) — no CORS
- Next.js server-side rewrites proxy `/api/*` to Cloud Run via `INTERNAL_API_URL`
- Branding, config, and agent avatars live in `mlds-services/services/echo/` and are served by the Cloud Run backend at runtime

## How to Deploy

1. Get the AXIS commit SHA you want to deploy
2. Update `ci/axis-version` with the SHA
3. Commit and push to `main`
4. The production workflow triggers automatically (requires `production` environment approval)

```bash
echo "abc1234def5678..." > ci/axis-version
git add ci/axis-version
git commit -m "chore: bump AXIS to abc1234"
git push origin main
```

## How to Rollback

Revert the `ci/axis-version` commit and push:

```bash
git revert HEAD
git push origin main
```

Or promote a previous deployment from the Vercel dashboard.

## Deploy Script

`ci/deploy-echo-frontend.sh` does the following on every deploy:

1. Reads the AXIS SHA from `ci/axis-version` (or `--axis-ref` override)
2. Validates the SHA format (must be a commit hash — branches/tags rejected)
3. Clones `ax-foundry/axis` and checks out the pinned SHA
4. Installs Vercel CLI and pulls project settings
5. Deploys `axis/frontend/` to Vercel
6. Runs smoke tests:
   - **Hard gate**: frontend returns HTTP 200
   - **Soft gate** (warn-only): `/api/config/theme` returns HTTP 200

## Preview Deploys

A preview deploy is triggered automatically when a PR modifies `ci/axis-version` or `ci/deploy-echo-frontend.sh`. The preview URL is posted as a PR comment.

You can also trigger a preview manually via `workflow_dispatch` with an optional `axis_ref` input to deploy a specific SHA without updating `ci/axis-version`.

## Repository Structure

```
echo/
├── ci/
│   ├── axis-version                          # Pinned AXIS commit SHA
│   └── deploy-echo-frontend.sh               # Deploy script
├── .github/workflows/
│   ├── deploy-echo-frontend-production.yml   # Triggers on push to main (ci/axis-version change)
│   └── deploy-echo-frontend-preview.yml      # Triggers on PRs + workflow_dispatch
└── README.md
```

## Required Secrets (GitHub Actions)

| Secret | Description |
|--------|-------------|
| `VERCEL_TOKEN` | Vercel deploy token |
| `VERCEL_ORG_ID` | Vercel team/org ID |
| `VERCEL_PROJECT_ID` | Vercel project ID for Echo |
| `AXIS_CLONE_TOKEN` | GitHub PAT with read access to `ax-foundry/axis` (if repo is private) |

## Vercel Environment Variables

Set these in the Vercel project settings:

| Variable | Notes |
|----------|-------|
| `NEXT_PUBLIC_API_URL` | Public Cloud Run URL |
| `INTERNAL_API_URL` | Cloud Run URL used server-side (e.g. `https://echo-xxx.run.app`) |
| `API_GATEWAY_KEY` | Must match `API_GATEWAY_KEY` on the Cloud Run backend |
| `NEXTAUTH_URL` | Vercel deployment URL (e.g. `https://echo.vercel.app`) |
| `NEXTAUTH_SECRET` | NextAuth JWT signing secret |
| `GOOGLE_CLIENT_ID` | Google OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | Google OAuth client secret |
| `AUTH_REQUIRED` | `true` to enforce authentication |
| `AUTH_DOMAIN` | Restrict sign-in to this email domain (e.g. `mgtinsurance.com`) |
| `NEXT_PUBLIC_AUTH_DOMAIN` | Same domain, displayed on the sign-in page |

## Running Locally

This runs the full Echo stack (backend + frontend) on your machine using the echo configs from `mlds-services`.

### Prerequisites

- Python 3.11+
- Node.js 20+
- Access to `mlds-services` repo (for configs, branding, agents)
- DB connection strings (from 1Password or a teammate)

### 1. Clone AXIS

```bash
git clone https://github.com/ax-foundry/axis.git
cd axis
```

Or use an existing clone — just make sure you're on the right commit:

```bash
git fetch && git checkout $(cat /path/to/echo/ci/axis-version)
```

### 2. Install dependencies

```bash
make install
```

This installs Python + Node dependencies and runs `make setup` (creates `custom/` dirs and copies `.example` YAML templates).

### 3. Point AXIS at the echo configs

Instead of using the default `custom/` directory, point `AXIS_CUSTOM_DIR` at the echo configs in `mlds-services`:

```bash
# backend/.env
AXIS_CUSTOM_DIR=/path/to/mlds-services/services/echo
```

This tells the backend to load all YAML configs, branding, and agent avatars from the echo-specific directory — no copying needed.

### 4. Set backend secrets

Add your DB connection strings and API keys to `backend/.env`:

```bash
# backend/.env (add alongside AXIS_CUSTOM_DIR)
EVAL_DB_URL=...
MONITORING_DB_URL=...
HUMAN_SIGNALS_DB_URL=...
KPI_DB_URL=...
AGENT_REPLAY_DB_URL=...
OPENAI_API_KEY=...
ANTHROPIC_API_KEY=...
API_GATEWAY_KEY=...   # any value works locally
```

### 5. Set frontend env

```bash
# frontend/.env.local
NEXT_PUBLIC_API_URL=http://localhost:8500
API_GATEWAY_KEY=...   # must match backend
AUTH_REQUIRED=false   # disable auth for local dev
```

### 6. Start the dev servers

```bash
make dev
```

- Backend: http://localhost:8500
- Frontend: http://localhost:3500

---

## Local Testing (Deploy Script)

```bash
export VERCEL_TOKEN=xxx
export VERCEL_ORG_ID=xxx
export VERCEL_PROJECT_ID=xxx
export AXIS_CLONE_TOKEN=xxx  # if AXIS repo is private

./ci/deploy-echo-frontend.sh --vercel-env preview
# or with a specific SHA:
./ci/deploy-echo-frontend.sh --vercel-env preview --axis-ref abc1234
```

## Rules

- **Production deploys always use `ci/axis-version`** — no manual SHA overrides for production
- **No application code** — the frontend is AXIS; this repo only controls deployment
- **No config/branding/agents** — those live in `mlds-services/services/echo/`, served by the Cloud Run backend
