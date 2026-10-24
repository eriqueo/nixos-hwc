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

SSH inspection on October 22–23, 2026 found an i7-8750H with six cores/twelve threads, 32 GB RAM, Intel UHD 630 and an NVIDIA GTX 1050 Ti Mobile. The internal NVMe is nominally 1 TB. Hardware transcoding has not been exercised; the proposed Jellyfin configuration uses software encoding.

The TerraMaster D2-320 contains two 3 TB WD Red drives in the ZFS `media-pool` mirror. Usable pool capacity is about 2.7 TiB, not the sum of both disks. ZFS owns its mount at `/mnt/media`. Do not format these drives or add an ext4 mount for that path.

There is no separate hot or backup volume. `/mnt/hot` is a directory on the root SSD. Archives written there share the SSD's failure domain. A mirror protects against a member failure; it does not establish independent historical or offsite recovery.

Pool import is bounded to 30 seconds. The Jellyfin declaration requires the media mount and checks pool health with a 10-second probe before database or scanning setup. ONLINE passes; DEGRADED passes with a warning; suspended, unavailable, failed or unknown health blocks startup. This startup check does not repair a cable or guarantee that a running pool cannot later suspend.

The enclosure connects directly to the XPS. Linux also sees a hub inside the enclosure. The observed storage link ran at USB 2 speed. A clean completed scrub and passing SMART checks were recorded, but later USB disconnects mean the connection fault must remain open until tested after a known cable/port change.

## Services and data

The source enables local native Jellyfin and preserves its existing state under `/var/lib/hwc/jellyfin`. User/library state is CRITICAL for recovery; metadata and the transcode cache are REPLACEABLE. The shared module bounds transcode-cache cleanup to files aged 12 hours.

Media folders are `/mnt/media/tv`, `/mnt/media/movies` and `/mnt/media/music`. These contain selected copies, not an automatically synchronized copy of home's library. Home's full media library exceeds this mirror's capacity.

The independent Jellyfin database has its own account and API credentials. Do not assume home's API key or account policy applies to it. Never put passwords or API tokens in this guide.

The older running generation includes CouchDB and central monitoring services. Current source does not enable those services. Classify their callers and preserve their state before a full switch retires anything. The source's SMART and scrub declarations likewise need activation and runtime checks before being reported as live.

The investigation started `jellyfin-recovery.service` as a transient validation service using the cached 10.11.4 package. It is not permanent startup. Stop it and verify it is inactive before activating native `jellyfin.service`; remove the transient service when that transition is exercised.

The legacy `server-backup.timer` is not proof of complete backups: its observed run saved system/configuration archives on the root SSD, skipped authenticated CouchDB and still reported success. Resolve that coverage and reporting before relying on it. Its replacement or retirement is part of the recovery plan, not an implicit side effect of a system update.

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

A temporary composition-root rollout gate keeps clients and XPS agent publication disabled until the cable/destination and real restore pass. This prevents another fleet rebuild from starting premature backup jobs. The server role derives client paths from these declarations once the gate opens. Home/work retain
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

After the rollout gate opens, XPS backs up its Jellyfin state to home's dedicated
`borg-hwc-xps` repository, limited to 10G. It uses a separate SSH key and passphrase
that XPS can decrypt as the origin. The daily 02:30 job has a one-hour deadline
and a 1024 KiB/s upload limit. A validated online SQLite snapshot replaces the raw
database/WAL files in archives. Cache, logs and replaceable metadata are excluded.
This covers Jellyfin users, library definitions and watch history. It does not
claim full-host or T3 coverage. Source and encrypted configuration live in Git;
other legacy application state remains in the verified recovery checkpoint.
Retire the old SSD-local backup timer only after the real remote state archive
and restore pass. Verify `borgbackup-job-hwc-backup-home` and `borg-check-home`.

## Software updates before a cable change

The system can be updated while `ready=false`. That hold disables backup clients,
agent publication and automatic repository-directory initialization. The ZFS
bootstrap has no independent boot target. This allows native Jellyfin/software
activation without creating offsite datasets or starting backup uploads.
Take and validate a fresh quiesced Jellyfin checkpoint before activation. Keep
existing state/configuration checkpoints. Inspect native Jellyfin, remote access
and unchanged dataset inventory after the switch. Cable speed/stability, actual
destination restores and reboot acceptance remain separate checks.
