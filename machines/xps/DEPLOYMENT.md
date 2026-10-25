# XPS operating guide

The XPS is an independent NixOS machine in Maryland. Home owns the primary media/storage services. Work owns business/development applications and central monitoring. The proposed additional XPS role is offsite recovery, with selected local media as a secondary use.

The old installation template described active-active redundancy that was never established by this investigation. This guide describes the declared design and operating procedure. Current deployment evidence, pending human answers and work status live in the [project tracker](http://hwc-work:8765/p/xps-jellyfin/overview). Source declarations alone do not prove that a service is running.

## Configuration owners

- `flake.nix`: stable channel, base/desktop/server role membership and the same scoped native Node runtime used on work. The runtime binding preserves Chromium/PyTorch build dependencies.
- `machines/xps/config.nix`: machine-specific services, ZFS pool import, local network and startup safeguards.
- `machines/xps/hardware.nix`: boot/root UUIDs and detected boot modules.
- `machines/xps/home.nix`: desktop overrides for this machine.
- `machines/xps/SSH_HOST_ED25519_PUBLIC_KEY.txt`: verified SSH host-key pin for offsite clients; separate from the age recipient identity.
- `domains/media/jellyfin-native/index.nix`: native Jellyfin package, user/group, generated policy and cache cleanup.
- `domains/data/borg/`: the existing fleet backup capability. Do not add a second backup framework.
- `CHARTER.md` and `CLAUDE.md`: release and architecture rules.

## Hardware and storage

SSH inspection on October 22–23, 2026 found an i7-8750H with six cores/twelve threads, 32 GB RAM, Intel UHD 630 and an NVIDIA GTX 1050 Ti Mobile. The internal NVMe is nominally 1 TB. Hardware transcoding has not been exercised; native Jellyfin is configured for software encoding.

The TerraMaster D2-320 contains two 3 TB WD Red drives in the ZFS `media-pool` mirror. Usable pool capacity is about 2.7 TiB, not the sum of both disks. ZFS owns its mount at `/mnt/media`. Do not format these drives or add an ext4 mount for that path.

There is no separate hot or backup volume. `/mnt/hot` is a directory on the root SSD. Archives written there share the SSD's failure domain. A mirror protects against a member failure; it does not establish independent historical or offsite recovery.

Pool import is bounded to 30 seconds. The Jellyfin declaration requires the media mount and checks pool health with a 10-second probe before database or scanning setup. ONLINE passes; DEGRADED passes with a warning; suspended, unavailable, failed or unknown health blocks startup. This startup check does not repair a cable or guarantee that a running pool cannot later suspend.

The enclosure connects directly to the XPS. Linux also sees a hub inside the enclosure. The observed storage link ran at USB 2 speed. A clean completed scrub and passing SMART checks were recorded, but later USB disconnects mean the connection fault must remain open until tested after a known cable/port change.

## Services and data

The source enables local native Jellyfin and preserves its existing state under `/var/lib/hwc/jellyfin`. User/library state is CRITICAL for recovery; metadata and the transcode cache are REPLACEABLE. The shared module bounds transcode-cache cleanup to files aged 12 hours.

Media folders are `/mnt/media/tv`, `/mnt/media/movies` and `/mnt/media/music`. These contain selected copies, not an automatically synchronized copy of home's library. Home's full media library exceeds this mirror's capacity.

Local mail synchronization is disabled on XPS; work owns mail. The inherited desktop mail defaults do not make this recovery/media machine a mail owner.

The independent Jellyfin database has its own account and API credentials. Do not assume home's API key or account policy applies to it. Never put passwords or API tokens in this guide.

The October 24 cutover retired local CouchDB and central monitoring. CouchDB had no application databases; its state and the five-dashboard Grafana database were preserved in validated encrypted checkpoints. Central monitoring remains on work. The tracker owns current timer and health evidence.

Native `jellyfin.service` replaced the transient 10.11.4 recovery process on October 24. A normal reboot loaded Linux 6.18.53 and started Jellyfin 10.11.11. Real admin login, Nathan S1E4 and matching media bytes passed after boot. Current source revision and archive evidence live on the tracker.

The legacy `server-backup.timer` reported success while skipping authenticated CouchDB and writing to the root SSD. It is retired. Its archives remain intact. The replacement protects the scoped Jellyfin state on home; Git and the retained encrypted checkpoints cover the declared configuration/legacy recovery material, not a full-host ongoing archive.

## Access

The stable tailnet identity is `hwc-xps`; its registered address comes from `domains/networking/hosts/index.nix`. Tailscale authentication must remain valid.

The observed Maryland DHCP addresses were Ethernet `192.168.1.191` and Wi-Fi `192.168.1.173`, with Ethernet preferred. Verify them after a network change; these are not documented DHCP reservations.

Local Jellyfin uses `http://<current-XPS-LAN-address>:8096`. Its server identity should be `hwc-xps`. The home Jellyfin vhost continues to name the home server. Do not move that shared vhost as a shortcut to local streaming.

## Inspect before changing

Run on the XPS:

```bash
hostname
readlink -f /run/current-system
systemctl is-system-running
systemctl --failed
ip -brief address
ip route show default
sudo zpool status media-pool
findmnt -T /mnt/media
systemctl status jellyfin jellyfin-recovery
systemctl list-timers --all
sudo journalctl -k -b
```

Use serial-based `/dev/disk/by-id/` paths for SMART queries. USB reconnects changed the kernel names from sda/sdb to sdc/sdd during this investigation; cached sd names are unsafe identifiers.

A completed scrub checks the data ZFS read at that time. It does not prove cable stability, backup completeness or restore success. Read the actual backup log and destination filesystem, not only the job's exit code.

## Change and release

This is system/mixed work, so the activation lane is `sudo nixos-rebuild switch --flake .#hwc-xps`, not `hms`. Follow the repository's worktree, commit-before-build and reviewed-main workflow.

Before a full switch:

1. Run `nix build --no-link .#checks.x86_64-linux.xps-media-readiness` and the required charter checks on the final source revision.
2. Inspect the candidate service/closure diff and ensure existing data and SSH recovery are covered.
3. Read the current server-upgrade-mail-health tracker. Do not revive its held outputs or create another broad build that bypasses its release work.
4. Preserve a consistent Jellyfin state backup before a new version can migrate the database. OS rollback alone does not undo database migration.
5. Confirm the pool is usable, stop the transient validation service, then activate the reviewed main revision on XPS.
6. Check native service health, generated policy, remote access, pool state and boot behavior. Record the actual revision and observed result.

A build does not activate a system. A source commit or the presence of this guide does not satisfy these release conditions.

## Connection and recovery procedure

For a disk/enclosure fault, inspect `zpool status`, SMART through stable IDs and kernel USB events. Confirm enclosure power and the data cable. Do not clear errors before preserving their evidence or treat reappearing device nodes as proof that the pool recovered.

Use a normal shutdown when possible before changing enclosure power or cables. A suspended ZFS pool previously blocked shutdown; forced restart needs explicit authorization because pending writes may be lost. Bring the enclosure up before booting the XPS, then inspect the imported pool and scrub state.

If a release fails, fix forward or revert its source commit on main under the repository policy. Emergency boot of a previous generation can restore access, but reconcile the source and any database changes before declaring recovery complete.

## Declared backup destination

The source declares `media-pool/offsite` mounted at `/mnt/media/offsite`, with
a 1 TiB parent quota. The home/work child quotas are 750/150 GiB. Native Borg
serves only the corresponding repository to its dedicated SSH key; server quotas
are 700G/140G and subrepositories are forbidden. `xps-offsite-storage` validates
all existing datasets before creating any missing child. Property or mount drift
fails without resizing or deleting data. Repo initialization requires that unit
and each child mount. Nothing is created merely by evaluating or building source.

A temporary composition-root rollout gate keeps Maryland clients and XPS agent publication disabled until the cable/destination and real restore pass. This prevents another fleet rebuild from starting premature backup jobs. The server role derives client paths from these declarations once the gate opens. Home/work retain
their primary jobs and gain independent Maryland jobs at 06:00 MDT, limited to
2048 KiB/s uploads and eight hours. Interrupted initial seeding can require several
runs before the first complete archive. Do not start a manual seed inside the
nine-hour window before the primary backup. Shared snapshots/archives serialize
per host; contention fails after 300 seconds. Completion and failure are visible
in each native unit. Weekly `borg-check-maryland` checks repository consistency;
full cryptographic verification and real restores are separate acceptance steps.

Home/work offsite credentials exclude XPS from age recipients and mounts. Home, work,
laptop and the existing user identity retain recovery. Secret mounts remain
root:secrets 0440; systemd delivers private SSH identities. Repository-key exports
must be encrypted and retained outside the destination after initialization.

Current activation, hardware checks, recovery checkpoint evidence and archive
coverage remain on the tracker. No source declaration alone establishes readiness.

## Offsite recovery acceptance

The tracked plan owns the replication recipe, capacity bound and verification. Permanent offsite readiness requires all of the following:

- Confirm the XPS's Maryland residence and availability.
- Establish connection stability after the physical test.
- Keep consistent encrypted recovery data from both primary servers within a declared destination space/retention bound.
- Preserve the previous usable copy on interruption or capacity failure.
- Keep recovery credentials available independently of a lost home server.
- Exercise a file restore, an isolated application/database restore, a second incremental run and the failure-reporting path.
- Record the deployed revision, schedule, operator commands and known recovery lag.

Do not describe a copied media folder, an SSD-local archive or an ONLINE mirror as completion of this offsite recovery contract.

## XPS application-state recovery

The independent recovery gate enables XPS Jellyfin-state backups to home's dedicated
`borg-hwc-xps` repository, limited to 10G. It uses a separate SSH key and passphrase
that XPS can decrypt as the origin. The daily 02:30 MDT job has up to one hour of random delay, a one-hour deadline
and a 1024 KiB/s upload limit. A validated online SQLite snapshot replaces the raw
database/WAL files in archives. Cache, logs and replaceable metadata are excluded.
This covers Jellyfin users, library definitions and watch history. It does not
claim full-host or T3 coverage. Source and encrypted configuration live in Git;
other legacy application state remains in the verified recovery checkpoint.
Keep the old SSD-local archives until recovery is no longer needed. Verify `borgbackup-job-hwc-backup-home` and `borg-check-home`.

## Software updates before a cable change

The system can be updated while `ready=false`. That hold disables Maryland backup clients,
agent publication and automatic repository-directory initialization. The ZFS
bootstrap has no independent boot target. This allows native Jellyfin/software
activation without creating offsite datasets or starting backup uploads.
Take and validate a fresh quiesced Jellyfin checkpoint before activation. Keep
existing state/configuration checkpoints. Inspect native Jellyfin, remote access
and unchanged dataset inventory after the switch. Cable speed/stability, actual
destination restores and reboot acceptance remain separate checks.

The bounded pool-health query runs in `xps-media-ready`, a separate oneshot as
`eric:users` with only `/dev/zfs` device access. Jellyfin requires it and waits
for completion before database setup. The oneshot does not remain active, so a
later Jellyfin start checks the pool again. Jellyfin keeps its device sandbox;
putting the query in its own preStart fails under that sandbox.

`offsiteStorage.recovery.ready` controls the SSD-to-home state backup separately
from the Maryland enclosure's `ready` gate. The existing home destination can
protect current Jellyfin state before the USB cable is replaced. The Maryland
repository initialization, uploads and metrics-agent publication stay held.

## Restore the XPS state from home

On home, become root with `sudo -i`. The local repository is
`/mnt/backup/borg-hwc-xps`. Set `BORG_REPO` to that path and set
`BORG_PASSCOMMAND` to `cat /run/agenix/borg-xps-state-passphrase`.
Run `borg list` to select a completed archive. Extract it into a new private
recovery directory. Do not extract over the running server.

The archive carries the application tree at `var/lib/hwc/jellyfin` and its
consistent database at `var/lib/hwc/borg-sqlite/ready/jellyfin.sqlite`. Put that
snapshot at the restored application's `data/jellyfin.db` path. Set the restored
application tree to `eric:users`, keeping the database private, before starting it
as that user. Start an isolated
instance of the matching Jellyfin version and verify login and library data
before any intentional production replacement. Preserve the current state first.

The encrypted repository-key export is
`domains/secrets/parts/system/borg-xps-state-repository-key.age` in Git. It matches
the real repository and decrypts on home, work and XPS. It complements the
passphrase; neither replaces the other. Normal extraction uses the repository's
existing key. Import a recovery key only when repairing a missing repository key.
Weekly `borg-check-home` performs consistency checks. Full `--verify-data` and
actual isolated application restores are separate checks recorded on the tracker.

## Household desktop and remote administration

Dad uses UID1001 with a private home/group, native Plasma/SDDM and automatic
login. Eric retains his existing SSH/Tailscale/sudo identity and Hyprland session
choice. Dad has video/render access but no wheel, users, secrets, disk or container
authority. Instance polkit permits Wi-Fi scan/radio/connection and own-profile changes
only from Dad’s active local session. System-wide network settings, global
network shutdown, power, disk and service management remain denied. Use Eric’s
account for system settings. Physical power loss and
forced power-button holds remain outside software control.

The paths domain must not export HOME globally: PAM/systemd select the actual
account home. HWC_USER_HOME still identifies the primary HWC account. If an old
Dad session inherited Eric’s home during a transition, stop the display manager,
terminate only Dad’s session and start the display manager again. Do not relax
Eric’s0700 home permissions. Stock Plasma settings are seeded once; subsequent
user edits survive builds. The desktop Start Here file explains normal use.

Steam and Proton-GE use the shared gaming capability. Installed games stay on
SSD; game installation is not proof of compatibility. The first rollout keeps
the existing Intel graphics/kernel. Proprietary NVIDIA loading/reboot remains a
separate maintenance action requiring proved unattended recovery. Do not promise
B-17 Redux performance on the1050Ti below its listed1070 minimum.

The existing10G encrypted XPS-to-Home state job also includes Dad’s Documents,
Desktop, Pictures, .config and Steam userdata/compatdata (including local saves).
Installed Steam games, Downloads and shader caches are excluded by the positive
source list. Steam Cloud is not a substitute. Quota failure must remain visible;
do not silently enlarge the repository or prune unrelated archives. Personal
files/settings are CRITICAL; game installs are REPLACEABLE from Steam. Verify a
real restored Dad file before claiming new personal-data coverage.

For remote-only live updates, retain/root the complete old system closure. Arm a
local root systemd timer BEFORE native test activation. It must run the old
system’s nixos-rebuild test --no-reexec --store-path after five minutes with a
120-second action deadline. Reconnect through a NEW Tailscale SSH session and
verify sudo, native services, Dad authority/home and actual desktop before stopping
the timer. Loss-of-client restore and confirmation were exercised October25;
an actual failed desktop transition was restored successfully too. This protects
userspace activation, not a pre-userspace kernel hang. Keep boot/kernel changes
separate; no automatic forced reboot or shared Git reset. Reconcile reviewed main
with the final running system before release. Runtime records and exact store
paths belong in the project handoff, not this permanent procedure.

Dad’s generated recovery password and yescrypt hash use the existing encrypted
secret owner (dad-login-password and dad-login-password-hash). Do not share Eric’s
password, use an empty password, print values in chat or put credentials in Steam
launch options. Eric can recover/rotate Dad’s password privately via the existing
secret workflow. Dad’s automatic login does not require entering it. A future
manual login or explicit lock still needs that password.

## Private T3 agent environment

XPS runs its own T3 Code environment so agents work on this machine without an
SSH session per task. It is a third environment, not a copy: its own `~/.t3`
store, signing key, `environment-id` and pairing. Never copy a store, a signing
key or a pairing token between hosts — two writers on one event-sourced SQLite
store is a known failure, and a shared key would let one host's clients act as
another's.

Owners: `machines/xps/home.nix` (headless shape and bind), `domains/home/apps/t3code/`
(the module and its `t3-update` release driver), `domains/networking/routes.nix`
(the `t3-xps` vhost), `machines/xps/config.nix` (state protection).

### Shape

Headless `t3 serve`, not the Electron app. The desktop role turns the Electron
shape on by default and this machine turns it off; the module asserts the two
shapes never coexist. Build artifacts live in the fork's working tree at
`~/600_apps/t3code`, which the launcher runs and does not build.

The backend binds `127.0.0.1:3773`, deliberately unlike hwc-server and hwc-work,
which bind `0.0.0.0`. Those two sit in Eric's house. This one sits in Dad's, on
a household LAN the firewall trusts wholesale (`trustedInterfaces` carries
`eno1`). So there is no pair-by-tailnet-IP fallback here, on purpose: the Caddy
vhost is the only door.

### Reaching it

`https://t3-xps.hwc.iheartwoodcraft.com`, tailnet-only, behind the wildcard
certificate and T3's own pairing auth.

This rests on the deSEC A record `t3-xps.hwc.iheartwoodcraft.com -> 100.126.80.42`
(created 2026-10-25, TTL 900), the same per-owner record every other owner-pinned
name has. Without it, `*.hwc.iheartwoodcraft.com` resolves to hwc-home, whose
Caddy renders `routeOwner = "main"` only, so an xps-owned route is filtered out
and answers 404.

So a 404 here means the DNS record, not the backend. Check in that order:

```bash
dig +short t3-xps.hwc.iheartwoodcraft.com          # expect 100.126.80.42
curl --resolve t3-xps.hwc.iheartwoodcraft.com:443:100.126.80.42 \
  https://t3-xps.hwc.iheartwoodcraft.com/          # bypasses DNS entirely
```

If the second answers 200 and the first does not resolve to this host, the
backend is fine and the record is the problem. deSEC publishes zone changes on
a ~60s batch cycle, and its two nameservers do not update together — check both
`ns1.desec.io` and `ns2.desec.org` before concluding a write failed.

The pairing URL and QR that `t3 serve` prints at startup are loopback URLs and
are useless from a phone. Eric mints his own against the real hostname:

```bash
cd ~/600_apps/t3code && node apps/server/dist/bin.mjs \
  auth pairing create --base-url https://t3-xps.hwc.iheartwoodcraft.com
```

A pairing link is a credential. Do not put one in this guide, in chat, in Git or
in a log, and do not consume Eric's link on his behalf.

### Providers

The service PATH is explicit, because a systemd user unit inherits none. On this
host `claude`, `codex`, `pi` and `herdr` all come from
`/etc/profiles/per-user/eric/bin`; `~/.npm-global/bin` is empty, so
`agent-harness.cliUpdates` is deliberately NOT enabled here as it is on the other
two servers. The consequence is real and worth knowing: T3 hides any model whose
manifest `minVersion` is newer than the installed CLI, and the CLIs here move
only when the Nix profile does.

Provider authentication is per-host and interactive. `codex login` on this
machine is Eric's to run; an expired token shows up as `401` from
`wss://chatgpt.com/backend-api/codex/responses`, not as a service failure.

### Updating the fork

Use `t3-update` (see `domains/home/apps/t3code/README.md`), not a hand-run
`pnpm build` in the serving tree. It stages a candidate, verifies it natively,
proves OLD->NEW->OLD recovery and only then promotes. `hms` is not needed for an
application update — the launcher reads the working tree at run time. Run the
system lane only after changing anything under `serve.*`, `repo`, or the route.

### State and recovery

`~/.t3/userdata` is CRITICAL: it holds the event-sourced thread store and the
server signing key, which nothing can regenerate and no other machine holds.
Losing the key invalidates every paired client. `~/.t3/caches` and
`~/.t3/worktrees` are REPLACEABLE and are not backed up.

It rides the existing bounded XPS-to-home Borg job — the same 10G repository,
the same 02:30 schedule, the same retention. Registration is explicit in
`machines/xps/config.nix` rather than inherited from `profiles/base/sys.nix`,
because the base role attaches it to `primary.enable`, which this host keeps
false so a missing primary job is not invented.

Only the `t3-v2` snapshot is registered. V1 `state.sqlite` exists on the other
two hosts because their stores were MIGRATED to protocol 2; this environment was
created at it. Do not add `t3` until `~/.t3/userdata/state.sqlite` actually
exists here — a snapshot whose source is missing fails the copy worker, and the
job propagates that, taking the Jellyfin and Dad-personal-file archive down with
it.

Borg stores the consistent snapshot at `var/lib/hwc/borg-sqlite/ready/t3-v2.sqlite`
and excludes the live `statev2.sqlite` / `-wal` / `-shm` / `-journal` tuple
automatically. To recover, restore that snapshot to
`~/.t3/userdata/statev2.sqlite` with the service stopped, and restore
`~/.t3/userdata/secrets/` alongside it — the store without the signing key means
re-pairing every client.

Known gap, separately owned: `agent-harness-doctor` reports `FAIL mutable state
ownership` because `~/800_agents/state` has no clone here, and XPS has no SSH
path to the hub on hwc-home. Agents run without the shared state; this is the
existing backlog item, not a T3 fault.
