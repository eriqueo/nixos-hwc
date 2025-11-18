# mailbot — HWC Gmail cleanup automation

Purpose
- Simple tool to unsubscribe/archive promotional Gmail messages for the Heartwood Craft inbox.
- Designed to be developed and run locally as a user tool, or deployed to a server with a systemd installer.

Charter compliance
- No secrets checked into the workspace. OAuth client files / tokens must be stored out-of-repo or managed by `agenix` (see domains/secrets). This repo-level project includes `.gitignore` to protect local credentials.
- Follows workspace purpose-based layout: `workspace/projects/` for development projects. See HWC workspace conventions.

Entry points
- `src/mailbot/bulk_unsubscribe.py` — main script
- Use `python -m mailbot.bulk_unsubscribe` or `pipx`/`pyproject` entrypoint when installed.

Local development
- Use `nix/shell.nix` to get a reproducible Python dev shell.

Deployment
- For system deployment, add a small installer service that copies `workspace/projects/mailbot/src/mailbot/bulk_unsubscribe.py` to `/opt/tools/` and configures a systemd unit or run via a user cron/runner.
