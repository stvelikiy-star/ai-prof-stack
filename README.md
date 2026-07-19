# AI PROF Stack

Private infrastructure repository for the AI PROF automation platform.

## Current Components

- Docker Compose
- PostgreSQL
- n8n
- Local PostgreSQL and n8n backups
- Safe restore testing
- Server health monitoring
- Telegram infrastructure alerts
- systemd services and timers
- AI governance documentation

## Security Model

- PostgreSQL is not exposed through a host port.
- n8n is bound only to `127.0.0.1:5678`.
- Remote owner access uses SSH over Tailscale.
- Secrets are stored only in the local `secrets/` directory.
- Runtime state is stored only in the local `runtime/` directory.
- Secret and runtime directories are excluded from Git.
- Telegram does not execute remote server commands.
- No public webhook or public server port is configured at this stage.

## Repository Structure

- `ai-system/` — governance, architecture, status, and decision documents.
- `postgres/` — PostgreSQL initialization resources.
- `n8n/` — n8n container entrypoint resources.
- `scripts/` — backup, restore, monitoring, and alert scripts.
- `systemd/` — versioned copies of systemd services, timers, and overrides.
- `compose.yaml` — PostgreSQL and n8n Docker Compose stack.

## Branch Policy

- `main` — accepted and stable infrastructure state.
- `develop` — integration branch for approved changes.
- `feature/*` — isolated feature work.
- `fix/*` — isolated corrective work.

Direct unreviewed changes to `main` are prohibited.

## Secret Recovery Requirement

The repository does not contain passwords, encryption keys, tokens, chat IDs,
or other credentials. A server restored from this repository requires separately
protected secret recovery material.
