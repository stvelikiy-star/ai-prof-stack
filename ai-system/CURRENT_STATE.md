
## Infrastructure Status Update — 2026-07-20 01:36:18 +06

The PostgreSQL and n8n deployment stage is complete.

Verified status:

- PostgreSQL container: healthy
- n8n container: healthy
- n8n restart count after repair: 0
- n8n readiness endpoint: HTTP 200
- PostgreSQL application role: n8n
- PostgreSQL application database: n8n
- PostgreSQL has no published external port
- n8n is bound only to 127.0.0.1:5678
- Windows access is provided through an SSH tunnel over Tailscale
- n8n owner account was created
- Owner login to the n8n interface was verified

Result:

PASS

No production workflows have been created yet.

Next approved planning stage:

- automatic restart verification;
- PostgreSQL and n8n backup design;
- restoration testing;
- server no-sleep configuration;
- closed-lid operation;
- resource monitoring.

## Reboot Recovery Verification — 2026-07-20 01:55:28 +06

The Ubuntu development node was rebooted to verify automatic infrastructure recovery.

Verified after reboot:

- Docker startup state: enabled
- Docker service state: active
- PostgreSQL container: healthy
- n8n container: healthy
- n8n readiness endpoint: HTTP 200
- PostgreSQL data persisted
- n8n owner account persisted
- n8n configuration persisted
- Manual container startup was not required
- Windows access through the SSH tunnel over Tailscale was restored successfully

Result:

PASS

The infrastructure automatically recovers after an Ubuntu reboot.

## Infrastructure Status — 2026-07-20

### Core Services

- Docker service is enabled and active.
- PostgreSQL container `ai-prof-postgres` is running and healthy.
- n8n container `ai-prof-n8n` is running and healthy.
- n8n readiness endpoint returns HTTP 200.
- PostgreSQL is not exposed through a host port.
- n8n is bound only to `127.0.0.1:5678`.
- Remote owner access uses an SSH tunnel over Tailscale.

### Backup System

- Local backup root: `/home/agent/ai-prof-backups`.
- PostgreSQL database `n8n` is backed up in custom dump format.
- The persistent n8n Docker volume is archived.
- Non-secret infrastructure configuration and AI governance files are archived.
- SHA-256 checksums are generated and verified.
- Backup retention is 14 days.
- The backup script successfully restores n8n to healthy status after backup.
- A real restore test into temporary database `n8n_restore_test` completed successfully.
- The temporary restore-test database was removed after validation.
- Backup verification status: PASS.

### Backup Schedule

- systemd unit: `ai-prof-backup.service`.
- systemd timer: `ai-prof-backup.timer`.
- Schedule: daily at 03:00 Asia/Bishkek.
- The timer is enabled and active.
- Persistent scheduling is enabled.

### Health Monitoring

- Local health script: `/home/agent/ai-prof-stack/scripts/check-ai-prof-health.sh`.
- Checks include disk usage, RAM, swap, Docker, PostgreSQL, n8n, HTTP readiness, backup timer, and backup freshness.
- The script performs read-only checks and does not restart or modify services.
- systemd unit: `ai-prof-health.service`.
- systemd timer: `ai-prof-health.timer`.
- Schedule: every hour at minute 15.
- The timer is enabled and active.
- Latest verified health result: PASS.
- Latest verified warning count: 0.
- Latest verified critical-problem count: 0.

### Verified Resource Snapshot

- Root filesystem usage: 19%.
- RAM available: approximately 83%.
- Swap usage: 0%.
- PostgreSQL status: healthy.
- n8n status: healthy.
- n8n readiness: HTTP 200.

### Power Configuration

- The Ubuntu host is used as a stationary server with an external monitor.
- The original laptop lid and internal display are not used.
- Automatic sleep was disabled before this infrastructure stage.
- No additional lid-switch configuration is required.

## Telegram Alert System — 2026-07-20

### Telegram Channel

- A dedicated Telegram bot and private control group are connected.
- The Telegram channel is used only for infrastructure alerts.
- The bot does not accept or execute remote server commands.
- No Telegram webhook is configured.
- No additional public port was opened.
- Telegram communication uses outbound HTTPS requests to the Telegram Bot API.

### Secret Storage

- Bot token file: `/home/agent/ai-prof-stack/secrets/telegram_bot_token`.
- Telegram chat ID file: `/home/agent/ai-prof-stack/secrets/telegram_chat_id`.
- Both files use permission mode `600`.
- Telegram secrets are excluded from Git and infrastructure archives.
- Secret values are not stored in governance documents or system logs.

### Alert Components

- Telegram sender: `/home/agent/ai-prof-stack/scripts/send-telegram-alert.sh`.
- Health alert wrapper: `/home/agent/ai-prof-stack/scripts/run-health-with-alert.sh`.
- Backup alert wrapper: `/home/agent/ai-prof-stack/scripts/run-backup-with-alert.sh`.
- Runtime alert state directory: `/home/agent/ai-prof-stack/runtime`.
- Runtime directory permission mode: `700`.
- Alert-state files use permission mode `600`.

### Health Alert Behavior

- A normal health-check result does not send a Telegram message.
- A new WARNING sends one Telegram notification.
- A new CRITICAL result sends one Telegram notification.
- An unchanged repeated problem is suppressed.
- A changed problem generates a new notification.
- Recovery from WARNING or CRITICAL sends a RECOVERY notification.
- Health monitoring remains read-only and does not restart services automatically.

### Backup Alert Behavior

- A successful backup does not send a Telegram message.
- A backup failure sends a CRITICAL notification.
- An unchanged repeated backup failure is suppressed.
- Recovery after a failed backup sends a RECOVERY notification.
- A local file lock prevents concurrent executions of the backup wrapper.

### systemd Integration

- `ai-prof-health.service` executes `run-health-with-alert.sh` through a systemd override.
- `ai-prof-backup.service` executes `run-backup-with-alert.sh` through a systemd override.
- Health monitoring runs every hour at minute 15.
- Backup runs daily at 03:00 Asia/Bishkek.
- Both timers are enabled and active.

### Verification Status

- Telegram bot-token validation: PASS.
- Private Telegram group registration: PASS.
- Telegram test-message delivery: PASS.
- Health WARNING notification test: PASS.
- Repeated health-alert suppression test: PASS.
- Health CRITICAL notification test: PASS.
- Health RECOVERY notification test: PASS.
- Backup CRITICAL notification test: PASS.
- Repeated backup-alert suppression test: PASS.
- Backup RECOVERY notification test: PASS.
- Production health-alert state isolation: PASS.
- Production backup-alert state isolation: PASS.
- systemd health-wrapper execution: PASS.
- systemd backup-wrapper execution: PASS.
- PostgreSQL status after integration: healthy.
- n8n status after integration: healthy.
- n8n readiness after integration: HTTP 200.
