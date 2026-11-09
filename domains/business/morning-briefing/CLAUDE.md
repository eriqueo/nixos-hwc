# Morning briefing runtime

`run.sh` is the producer of `output/briefing.json`. The dashboard, wall display,
Workbench and MCP briefing tools read that snapshot. They do not gather a second copy.

The scheduled runner gathers system, mail, calendar, weather and backup data with
local tools. `hostHealthFrom` selects the host for system, disk, journal, VPN and
backup reads. Business jobs and invoices come from JobTread PAVE. CalDAV tasks
and Today actions use the local HWC MCP gateway through `dashboard/mcp-client.mjs`.
The resident Laya classifier owns mail judgments and the append-only mail ledger;
`triage-mail.sh` preserves its owner lock and publishes the resulting snapshot.

`gather-*.mjs` expose importable functions with explicit I/O, configuration and
clock inputs. Their CLI entries bind environment and runtime handles. A failed
source retains other source results. Project card reads have per-request and
total deadlines. Tool actions are not automatically retried.

`dashboard/view-policy.json` owns the source-to-section map and surface links.
The dashboard and both `email.jq` renderers consume it. JSON snapshots keep their
existing shape. The email runner sends only before 09:00 unless FORCE_EMAIL=1.
Do not trigger a live run as a read-only check: it can classify mail, advance the
Today cursor and send a project digest or email.

`run-dispatch.sh` consumes Eric-approved read-only diagnostic prompt cards.
Its tool grant remains unchanged. The external CLI authentication workaround
stays until the CLI returns nonzero for those failures.

Run `node --test domains/business/morning-briefing/gather.test.mjs` for source,
transport, deadline, lock, backup and renderer behavior. The registered
`morning-briefing-async` check runs the same suite with pinned tools.
