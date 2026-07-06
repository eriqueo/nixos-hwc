# Prompt: hwc-server rebuild + verification (paste into a Claude session ON hwc-server)

Copy everything below the line into a Claude Code session running on
hwc-server. Written 2026-06-11 after the roles refactor (Charter v12.1) plus
the Mission 1/2 follow-up commits (SSH password-auth off, Jellyfin key
removal, CUDA cache / nix-ld / gotify / exodos / powerScripts extractions).

---

Rebuild hwc-server from ~/.nixos main and verify it. The repo is at Charter
v12.1 (roles architecture). The laptop is already live on these commits; the
server has not rebuilt since before the refactor. Intentional behavior
changes you should EXPECT (do not "fix" them): HM cursor theme Adwaita →
Nordzy; fzf/starship colors move to hwc palette tokens; fleet-wide
`systemd.user.startServices = "sd-switch"` (user units, including mail
timers, restart on switch when changed); `jellyfin-apply-policies` unit is
GONE (deliberately deleted); SSH password authentication is now OFF.

## 0. Guards (do these first, in order)

1. `hostname` — must print `hwc-server`. Stop if not.
2. SSH lockout guard — BEFORE switching, confirm key auth works so the
   password-auth removal cannot lock Eric out. From this session:
   `sudo grep -c 'ssh-ed25519' /home/eric/.ssh/authorized_keys` (expect ≥1),
   and after the switch (step 3) verify the declarative key landed:
   `grep eriqueo@proton.me /etc/ssh/authorized_keys.d/eric`.
   The mutable ~/.ssh/authorized_keys keeps working regardless (sshd default
   AuthorizedKeysFile includes both), so existing sessions/keys survive.
3. Record the rollback target:
   `sudo nix-env --list-generations -p /nix/var/nix/profiles/system | tail -3`
   — note the CURRENT generation number. Rollback, if anything goes wrong:
   `sudo nixos-rebuild switch --rollback` (or boot the previous generation
   from the boot menu; the emergency console password still works locally).

## 1. Pull + eval (no state change yet)

```
cd ~/.nixos && git pull --ff-only
git log --oneline -8   # expect the 2026-06-11 mission commits
nix eval --raw '.#nixosConfigurations.hwc-server.config.system.build.toplevel.drvPath'
```

Eval must succeed. If it fails, STOP and report — do not switch.

## 2. Test activation, then switch

```
sudo nixos-rebuild test --flake ~/.nixos#hwc-server
```

`test` activates without touching the bootloader — if the box wedges, a
reboot returns to the old generation. Sanity-check step 3's critical
services under `test`; if healthy:

```
sudo nixos-rebuild switch --flake ~/.nixos#hwc-server
```

## 3. Verify (report each, don't stop at the first failure)

1. No failed units: `systemctl --failed` (expect none; sd-switch may restart
   user units — that's the intended new behavior).
2. Critical services active:
   `systemctl is-active caddy postgresql couchdb n8n jellyfin`
   and containers: `podman ps --format '{{.Names}} {{.Status}}'` — expect
   immich stack, frigate, the arr stack, etc. Up. (Gotify decommissioned
   2026-07-06 — gotify/igotify/bridge units and containers should be GONE,
   not failed.)
3. Monitoring: `systemctl is-active prometheus grafana` (or their actual
   unit names — check `systemctl list-units | rg -i 'prometheus|grafana'`).
4. Mail timers: `systemctl --user list-timers` as eric (expect mail health /
   sync timers present and scheduled).
5. Jellyfin: confirm it serves (`curl -sf http://127.0.0.1:8096/health` or
   `/System/Info/Public`), and `systemctl status jellyfin-apply-policies`
   reports NOT-FOUND (deliberate deletion — its job was a no-op).
6. SSH policy: `sudo sshd -T | rg passwordauthentication` → `no`, and the
   declarative key file exists (step 0.2). From Eric's laptop later:
   `ssh -o PasswordAuthentication=no eric@hwc-server.ocelot-wahoo.ts.net true`.
7. Journal clean: `journalctl -p err -b --since '-15 min' | tail -40` —
   nothing NEW vs. pre-switch noise (GPU/nvidia warnings that predate the
   switch don't count; compare against `journalctl -p err -b --until '-15 min' | tail` if unsure).
8. HM lane works: as eric run
   `home-manager switch --flake ~/.nixos#eric@hwc-server` (alias `hms`) —
   must succeed; HM dual-path warning: the module lane just placed files, so
   if hms complains about "existing file in the way", STOP and report rather
   than deleting anything.
9. Intentional HM changes appeared: `rg color ~/.config/starship.toml | head`
   (hwc palette hexes, not Gruvbox-Material literals); fzf colors in the zsh
   env; cursor theme = Nordzy (`rg -i nordzy ~/.config/gtk-3.0/settings.ini`
   or `dconf read /org/gnome/desktop/interface/cursor-theme` equivalent —
   headless box, GTK file is the check).
10. (Removed 2026-07-06: gotify decommissioned; alerting is hwc-notify
    Discord+SMTP only. A test notification if Eric wants:
    `hwc-notify send monitoring "[P3] test" "server rebuild OK" --priority 3`.)

## 4. Report

Reply with: generation before/after, each check's pass/fail, any journal
lines that are genuinely new, and whether rollback is needed. If anything
failed that you can't explain from the intentional-changes list above, run
the rollback from step 0.3 and say so.
