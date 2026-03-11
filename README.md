# Echo

Deployment controller for the **Echo** frontend — MGT's observability and evaluation studio, powered by [AXIS](https://github.com/ax-foundry/axis).

This repo deploys the AXIS Next.js frontend to Vercel. Config, branding, and agent avatars live in mlds-services and are served by the backend at runtime.

## Architecture

```
Browser ──/api/*──> Vercel (Next.js) ──rewrite──> Cloud Run (FastAPI)
                     same-origin       INTERNAL_API_URL (server-side)
```

- All browser API calls use relative paths (`/api/...`) — no CORS
- Next.js server-side rewrites proxy `/api/*` to Cloud Run via `INTERNAL_API_URL`
- Branding, config, and assets are served by the backend at runtime

## How to Deploy

1. Get the AXIS commit SHA you want to deploy
2. Update `ci/axis-version` with the SHA
3. Commit and push to `main`
4. The production workflow deploys automatically (requires environment approval)

```bash
echo "abc1234def5678..." > ci/axis-version
git add ci/axis-version
git commit -m "bump AXIS to abc1234"
git push origin main
```

## How to Rollback

Revert the `ci/axis-version` commit:

```bash
git revert HEAD
git push origin main
```

Or use the Vercel dashboard to promote a previous deployment.

## Preview Deploys

PRs that change `ci/axis-version` or `ci/deploy-echo-frontend.sh` automatically get a Vercel preview deploy. The preview URL is posted as a PR comment.

## Repository Structure

```
echo/
├── ci/
│   ├── axis-version                 # Pinned AXIS commit SHA
│   └── deploy-echo-frontend.sh      # Deploy script
├── .github/workflows/
│   ├── deploy-echo-frontend-production.yml
│   └── deploy-echo-frontend-preview.yml
└── README.md
```

## Required Secrets (GitHub Actions)

| Secret | Description |
|--------|-------------|
| `VERCEL_TOKEN` | Vercel deploy token |
| `VERCEL_ORG_ID` | Vercel team/org ID |
| `VERCEL_PROJECT_ID` | Vercel project ID |
| `AXIS_CLONE_TOKEN` | GitHub PAT with read access to `ax-foundry/axis` |

## Local Testing

```bash
export VERCEL_TOKEN=xxx
export VERCEL_ORG_ID=xxx
export VERCEL_PROJECT_ID=xxx
export AXIS_CLONE_TOKEN=xxx  # if AXIS repo is private

./ci/deploy-echo-frontend.sh --vercel-env preview
```

## Rules

- **Production deploys always use `ci/axis-version`** — no manual SHA overrides for production
- **No application code** — the frontend is AXIS; this repo only controls deployment
- **No config/branding** — those live in mlds-services, served by the backend
