<p align="center">
  <img src="branding/echo.png" alt="Echo" width="400" />
</p>

# Echo

Use-case configuration for **Echo** — MGT's observability and evaluation studio, powered by [AXIS](https://github.com/ax-foundry/axis).

This repo contains branding, agent avatars, and YAML configs. It has no application code — AXIS (Repo A) provides the framework, and this repo customizes it for the Echo deployment.

## Repository Structure

```
echo/
├── config/                    # YAML configuration files
│   ├── theme.yaml             # Branding, color palette, hero image
│   ├── agents.yaml            # Agent registry (name, role, avatar)
│   ├── eval_db.yaml           # Evaluation database connection
│   ├── monitoring_db.yaml     # Monitoring database connection
│   ├── human_signals_db.yaml  # Human signals database connection
│   ├── kpi_db.yaml            # KPI database connection
│   ├── agent_replay.yaml      # Agent replay (Langfuse) settings
│   ├── agent_replay_db.yaml   # Agent replay lookup database
│   ├── signals_metrics.yaml   # Signals dashboard display overrides
│   ├── duckdb.yaml            # DuckDB embedded store settings
│   └── memory.yaml            # Memory/rule-extraction display config
├── branding/                  # Hero images, logos, favicons
├── agents/                    # Agent avatar images
├── .gitignore
└── README.md
```

## Credentials Policy

**No secrets in this repo.** YAML config files define non-secret fields (`host`, `port`, `database`, `username`, `ssl_mode`, queries, display settings) and set `password: null`. Actual credentials are injected at runtime:

- **Local dev**: environment variables in the AXIS repo's `backend/.env` (gitignored)
- **Production**: GCP Secret Manager via `--set-secrets` in Cloud Run

## Local Development

### Prerequisites

- [AXIS](https://github.com/ax-foundry/axis) cloned locally
- Python 3.12+, Node.js 20+

### Setup

Clone both repos side by side:

```bash
git clone https://github.com/ax-foundry/axis.git
git clone https://github.com/MGT-Insurance/echo.git
```

Point AXIS at this repo:

```bash
cd axis
export AXIS_CUSTOM_DIR=/path/to/echo
```

> **Tip**: Add `AXIS_CUSTOM_DIR` to your shell profile or a `.envrc` (if using direnv) so you don't have to re-export it every session.

### Inject Database Passwords

Create or update `axis/backend/.env` (gitignored in the AXIS repo) with the passwords that correspond to the YAML configs:

```bash
# Database passwords (match host/port/database in YAML configs)
EVAL_DB_PASSWORD=<your-password>
MONITORING_DB_PASSWORD=<your-password>
HUMAN_SIGNALS_DB_PASSWORD=<your-password>
AGENT_REPLAY_DB_PASSWORD=<your-password>
KPI_DB_PASSWORD=<your-password>

# API keys
OPENAI_API_KEY=sk-proj-...
ANTHROPIC_API_KEY=sk-ant-...

# Langfuse (per-agent credentials)
LANGFUSE_ATHENA_PUBLIC_KEY=pk-lf-...
LANGFUSE_ATHENA_SECRET_KEY=sk-lf-...
LANGFUSE_MAGIC_DUST_PUBLIC_KEY=pk-lf-...
LANGFUSE_MAGIC_DUST_SECRET_KEY=sk-lf-...
```

### Run

```bash
make dev   # Starts backend + frontend + FalkorDB
```

The backend reads YAML configs from `AXIS_CUSTOM_DIR/config/` and serves branding/agent images from the corresponding directories. Changes to this repo are picked up on backend restart.

### Docker Compose

If using Docker Compose, update the volume mount in `axis/docker-compose.yml` to point at this repo:

```yaml
services:
  backend:
    volumes:
      - /path/to/echo:/app/custom:ro
```

## Production Deployment

Echo is deployed via a platform repo (Repo C) that assembles AXIS + Echo into a single Docker image.

### How It Works

1. Repo C's CI checks out AXIS (Repo A) and Echo (Repo B)
2. Echo's directories are copied into the AXIS build context:
   ```bash
   cp -r echo/config   axis/backend/custom/config
   cp -r echo/branding axis/backend/custom/branding
   cp -r echo/agents   axis/backend/custom/agents
   ```
3. The Docker image is built from `axis/backend/`
4. Secrets are injected at runtime from GCP Secret Manager

### Runtime Secrets

These are set via `--set-secrets` in the Cloud Run deploy command (never stored in this repo):

| Secret | Source |
|--------|--------|
| `EVAL_DB_PASSWORD` | GCP Secret Manager |
| `MONITORING_DB_PASSWORD` | GCP Secret Manager |
| `HUMAN_SIGNALS_DB_PASSWORD` | GCP Secret Manager |
| `AGENT_REPLAY_DB_PASSWORD` | GCP Secret Manager |
| `KPI_DB_PASSWORD` | GCP Secret Manager |
| `OPENAI_API_KEY` | GCP Secret Manager |
| `ANTHROPIC_API_KEY` | GCP Secret Manager |
| `LANGFUSE_*_SECRET_KEY` | GCP Secret Manager |

### Config Load Order

The backend resolves configuration in this order (first match wins):

1. Environment variables (from Secret Manager or Cloud Run settings)
2. YAML files in `config/` (baked into the image)
3. Hardcoded defaults in AXIS `backend/app/config.py`

### Image Serving

Branding and agent images are served by the backend at:

- `/api/config/assets/branding/{filename}` — 1-year immutable cache
- `/api/config/assets/agents/{filename}` — 24-hour cache

The frontend references these URLs directly. No frontend build step depends on this repo.

## Making Changes

### Branding or theme update

Edit `config/theme.yaml` or add/replace files in `branding/`. Commit, push, and bump the config ref in Repo C to deploy.

### New agent

1. Add the avatar image to `agents/`
2. Add the agent entry to `config/agents.yaml`
3. Commit and push

### Database config change

Edit the relevant `config/*_db.yaml`. Non-secret fields (host, port, queries, thresholds) go here. Password changes go in GCP Secret Manager.

## Rules

- **No credentials** — passwords, API keys, and tokens are never committed
- **No application code** — custom behavior goes in AXIS behind a config flag
- **No infrastructure** — Terraform, Docker, CI workflows belong in Repo C
