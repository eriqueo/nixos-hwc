# domains/home/apps/gpg/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.gpg;

  # One owner for the decision "is this GnuPG lock stale?". The login oneshot
  # below and mail-health's check_gpg both call this; neither keeps its own test.
  #
  # Upstream workaround. GnuPG's dotlock treats a lock as live while its PID
  # exists on this hostname. A crash leaves keyboxd's lifetime lock behind
  # (SIGKILL/power loss never cleans it), and after the reboot another process
  # can get that PID; gpg then waits forever (2026-11-10: PID 5691 reused,
  # every keybox read timed out, pass-secret-service and T3 failed).
  # Remove when: GnuPG dotlock detects locks from an earlier boot (boot id or
  # holder start time) — recheck at each gnupg version bump.
  #
  # Stale means either:
  #   pre-boot  the lock is older than this boot AND its PID does not hold the
  #             protected file open. The fd test, not the process name, decides:
  #             a reused PID may belong to another GnuPG process.
  #   dead-pid  the PID is empty or gone AND the lock is at least 15 minutes
  #             old, so a lock re-taken between check and removal is never hit.
  # --check reports; --apply removes through `gpgconf --unlock`, which always
  # exits 1 for a lock it did not take, so success is the file being gone.
  staleLockHelper = pkgs.writeShellApplication {
    name = "hwc-gpg-stale-lock";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils pkgs.gnupg ];
    text = ''
      mode="''${1:-}"
      case "$mode" in
        --check|--apply) ;;
        *) echo "usage: hwc-gpg-stale-lock --check|--apply" >&2; exit 64 ;;
      esac
      home="''${GNUPGHOME:-$HOME/.gnupg}"
      [ -d "$home" ] || exit 0
      boot=$(awk '/^btime/ { print $2 }' /proc/stat)
      now=$(date +%s)
      minAge=900
      found=0
      rc=0

      holds_open() {   # holds_open <pid> <protected-file>
        local link
        for link in /proc/"$1"/fd/*; do
          [ "$(readlink "$link" 2>/dev/null)" = "$2" ] && return 0
        done
        return 1
      }

      while IFS= read -r -d "" lock; do
        pid=$(head -n 1 "$lock" 2>/dev/null | tr -d '[:space:]' || true)
        [[ "$pid" =~ ^[0-9]+$ ]] || pid=""
        mtime=$(stat -c %Y "$lock" 2>/dev/null) || continue
        inode=$(stat -c %i "$lock")
        protected="''${lock%.lock}"
        reason=""
        if (( mtime < boot )) && { [ -z "$pid" ] || ! holds_open "$pid" "$protected"; }; then
          reason=pre-boot
        elif { [ -z "$pid" ] || [ ! -d "/proc/$pid" ]; } && (( now - mtime >= minAge )); then
          reason=dead-pid
        fi
        [ -n "$reason" ] || continue
        found=1
        if [ "$mode" = --check ]; then
          echo "stale $lock reason=$reason pid=''${pid:--}"
          continue
        fi
        # The lock must be the one judged above, not one re-taken since.
        if [ "$(stat -c %i "$lock" 2>/dev/null)" != "$inode" ] \
           || [ "$(head -n 1 "$lock" 2>/dev/null | tr -d '[:space:]')" != "$pid" ]; then
          echo "skipped $lock reason=changed pid=''${pid:--}"
          continue
        fi
        rel="''${protected#"$home"/}"
        GNUPGHOME="$home" gpgconf --unlock "$rel" >/dev/null 2>&1 || true
        if [ -e "$lock" ]; then
          echo "failed $lock reason=$reason pid=''${pid:--}" >&2
          rc=2
        else
          echo "removed $lock reason=$reason pid=''${pid:--}"
        fi
      done < <(find "$home" -maxdepth 2 -type f -name '*.lock' -print0 2>/dev/null)

      if [ "$mode" = --check ]; then exit "$found"; fi
      exit "$rc"
    '';
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.gpg = {
    enable = lib.mkEnableOption "GPG and gpg-agent";

    # pass-secret-service exposes the existing pass store over the
    # org.freedesktop.secrets D-Bus API, so Electron/Chromium apps (Claude
    # Desktop, etc.) use pass (GPG-encrypted) as their keyring backend instead
    # of the weak `--password-store=basic` fallback. Opt-in per machine: only
    # graphical hosts with a D-Bus session want a SecretService daemon — a
    # headless server should leave this off.
    secretService.enable =
      lib.mkEnableOption "pass-secret-service (org.freedesktop.secrets over pass)";

    staleLock = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Clear GnuPG locks left by an earlier boot before any user service starts.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "hwc-gpg-stale-lock (--check|--apply): the one stale-lock decision; mail-health calls it.";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Enable GPG and the user gpg-agent service
    programs.gpg.enable = true;

    services.gpg-agent = {
      enable = true;
      enableSshSupport = true;
      # Use GUI pinentry for systemd services (Bridge, etc.).
      # Hosts running the secret service use pinentry-qt: pinentry-gnome3
      # needs GNOME's gcr system prompter on D-Bus, which Hyprland hosts do
      # not run, so it fell back to curses and failed with no tty. Every
      # pass-secret-service unlock after a reboot failed that way (measured
      # 2026-11-10: "gnome3.isatty ... Inappropriate ioctl for device").
      pinentry.package =
        if cfg.secretService.enable then pkgs.pinentry-qt else pkgs.pinentry-gnome3;
      # Cache passphrase for 2 hours to reduce prompts
      defaultCacheTtl = 7200;
      maxCacheTtl = 7200;
    };

    # Make pass the default password store (used by bridge CLI)
    home.sessionVariables = {
      PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
    };

    # GPG_TTY must be evaluated per-shell — as a session variable the
    # literal "$(tty)" was exported unevaluated (sessionVariables are
    # sourced once, not interpreted by every tty).
    programs.zsh.initContent = ''
      export GPG_TTY=$(tty)
    '';

    # Ensure pass + gnupg tools exist
    home.packages = [ pkgs.pass pkgs.gnupg ];

    # Optional: bridge the pass store to the SecretService D-Bus API. When on,
    # apps that use libsecret/Electron safeStorage store their secrets in pass
    # (GPG-encrypted) rather than the hardcoded-key `basic` store. gpg-agent
    # (above) supplies the pinentry/unlock path.
    services.pass-secret-service.enable = cfg.secretService.enable;

    # Start with the graphical session, not default.target. Under lingering,
    # default.target starts the daemon before Hyprland imports WAYLAND_DISPLAY
    # and DISPLAY into the user manager. The daemon then has no display, so gpg
    # cannot show a pinentry for a locked key and that decrypt fails.
    # graphical-session.target is reached only after that environment import.
    systemd.user.services.pass-secret-service = lib.mkIf cfg.secretService.enable {
      Unit = {
        PartOf = lib.mkForce [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Install.WantedBy = lib.mkForce [ "graphical-session.target" ];
    };

    hwc.home.apps.gpg.staleLock.package = staleLockHelper;

    # Runs once per user-manager start, before basic.target and therefore
    # before every ordinary user service and any GnuPG daemon they launch.
    # Ordered by target rather than by naming consumers, so a new gpg user needs
    # no edit here.
    systemd.user.services.gpg-stale-lock = lib.mkIf cfg.staleLock.enable {
      Unit = {
        Description = "Clear GnuPG locks left by an earlier boot";
        DefaultDependencies = false;
        Before = [ "basic.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${lib.getExe staleLockHelper} --apply";
      };
      Install.WantedBy = [ "basic.target" ];
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # Add dependency assertions here if needed
    ];
  };
}