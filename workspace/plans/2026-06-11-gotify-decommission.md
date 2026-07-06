# Gotify Decommission

**Date**: 2026-06-11
**Status**: EXECUTED 2026-07-06 (repo side; runtime archive + n8n workflow edit tracked in handoff)
**Replacement**: hwc-notify has been the primary alert path since the
2026-05-31 Phase 1.6 cutover (Discord + SMTP); gotify was kept as the iOS
push relay. Eric no longer uses it.

## Why this needs a deliberate pass (not a delete-and-pray)

Gotify is wired across roles, machines, automation, monitoring, and
secrets. Removing only the server unit would leave dangling clients and a
dead alertmanager receiver. Surface inventory (2026-06-11):

- **Roles**: profiles/server/sys.nix (gotify server enable/port/dataDir);
  profiles/business/sys.nix (n8n `gotifyTokenFiles` secret discovery);
  profiles/monitoring/sys.nix (alertmanager `gotify-bridge` receiver
  → localhost:9095).
- **Machines**: server (admin password, token auto-discovery, igotify,
  bridge), laptop + xps (`hwc.notifications.send.gotify` clients —
  laptop's points at the tailnet URL :2586).
- **Domain modules**: domains/notifications/send/gotify/,
  domains/notifications/gotify/{server,igotify,bridge}/.
- **Automation**: n8n `sys:router:notify` workflow routes to gotify
  tokens (n_TOKEN_* env vars); gotifyTokenFiles option in the n8n module.
- **Secrets**: agenix `gotify-*` (admin password, per-app tokens,
  gotify-token-laptop/alerts) + the recipients generated from them.
- **Possible consumers to check**: hwc.data.backup notifications path,
  waybar/notify CLI helpers, anything reading `hwc.notifications.send.*`.

## Execution sketch (one commit per step, hash/diff verified)

1. Confirm with Eric: no iOS push replacement needed (hwc-notify Discord/
   SMTP suffices)? If push is still wanted, pick the successor BEFORE
   removal (ntfy.sh self-hosted is the usual drop-in).
2. Remove the alertmanager gotify-bridge receiver (monitoring role) —
   alerts then flow only to hwc-notify. Verify alertmanager config drv.
3. Disable + remove client config (laptop/xps machine files, send/gotify
   consumers), then the server-side stack (server role block, igotify,
   bridge, machine token wiring).
4. Update the n8n notify workflow (drop gotify branch) and remove
   gotifyTokenFiles from the business role + n8n module option.
5. Delete the domains/notifications gotify modules + README updates.
6. Retire agenix gotify-* secrets (rekey) and archive
   /var/lib/hwc/gotify data on the server before removal.
7. Update: registry plan examples, server-verification-prompt (drop
   gotify service checks), notifications README, firewall port 2586/9095
   entries.

## Notes

- Until executed, gotify is still RUNNING config — server verification
  should keep checking it.
- The roles refactor used gotify as the worked example in several plan
  docs; those examples stay historically accurate.
