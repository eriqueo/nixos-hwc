# domains/media/scripts/index.nix
#
# Hot→cold sweep — cleans orphaned downloads from SSD staging area.
# Checks qBittorrent API before deleting (never removes active seeds).
# Copies new audiobooks to cold storage (never deletes — MAM seeding).
#
# Namespace: hwc.media.scripts.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.media.scripts;
  paths = config.hwc.paths;
  qbtPort = config.hwc.media.downloaders.qbittorrent.webPort;

  sweepScript = pkgs.writeScript "hot-sweep" ''
    #!${pkgs.python3}/bin/python3
    """Sweep orphaned downloads from hot storage to prevent SSD bloat."""
    import json, os, shutil, subprocess, sys, time, urllib.request

    QBT = "http://127.0.0.1:${toString qbtPort}"
    HOT = "${paths.hot.downloads}"
    COLD_AUDIOBOOKS = "${paths.media.audiobooks}"
    CATEGORIES = ["tv", "movies", "music"]
    EXPECTED = {"incomplete", "complete", "tv", "movies", "music", "books", "scripts", "readarr", "software"}
    MIN_AGE_H = 1  # skip files younger than 1 hour (may still be importing)


    def qbt_active(cat):
        """Get names of active torrents in a qBt category. Returns None if API unreachable."""
        try:
            url = f"{QBT}/api/v2/torrents/info?category={cat}"
            with urllib.request.urlopen(url, timeout=10) as r:
                names = set()
                for t in json.loads(r.read()):
                    cp = t.get("content_path", "")
                    if cp:
                        names.add(os.path.basename(cp.rstrip("/")))
                return names
        except Exception as e:
            print(f"SKIP {cat}: qBt API error: {e}")
            return None


    def sweep_category(cat):
        """Remove orphaned downloads for a category (not in qBt = safe to delete)."""
        cat_dir = os.path.join(HOT, cat)
        if not os.path.isdir(cat_dir):
            return
        active = qbt_active(cat)
        if active is None:
            return  # API down — don't touch anything
        for name in os.listdir(cat_dir):
            if name in active:
                continue
            path = os.path.join(cat_dir, name)
            age_h = (time.time() - os.path.getmtime(path)) / 3600
            if age_h < MIN_AGE_H:
                continue
            try:
                if os.path.isdir(path):
                    shutil.rmtree(path)
                else:
                    os.remove(path)
                print(f"SWEPT {cat}/{name} ({age_h:.0f}h old)")
            except OSError as e:
                print(f"ERROR {cat}/{name}: {e}")


    def sweep_books():
        """Copy new audiobooks to cold storage. Never deletes (MAM seeding)."""
        books = os.path.join(HOT, "books")
        if not os.path.isdir(books):
            return
        audio_exts = (".mp3", ".m4a", ".m4b", ".flac", ".opus", ".ogg", ".wav", ".aac")
        for name in os.listdir(books):
            src = os.path.join(books, name)
            marker = os.path.join(src, ".abs-copied")
            if not os.path.isdir(src) or os.path.exists(marker):
                continue
            has_audio = any(
                f.endswith(audio_exts)
                for _, _, files in os.walk(src) for f in files
            )
            if not has_audio:
                continue
            dst = os.path.join(COLD_AUDIOBOOKS, name)
            os.makedirs(dst, exist_ok=True)
            result = subprocess.run(
                ["${pkgs.rsync}/bin/rsync", "-a", "--ignore-existing", src + "/", dst + "/"],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                open(marker, "w").close()
                print(f"COPIED books/{name} -> audiobooks")
            else:
                print(f"ERROR rsync books/{name}: {result.stderr.strip()}")


    def log_strays():
        """Log unexpected entries in the downloads root."""
        for name in os.listdir(HOT):
            if name not in EXPECTED:
                print(f"STRAY {HOT}/{name}")


    if __name__ == "__main__":
        for cat in CATEGORIES:
            sweep_category(cat)
        sweep_books()
        log_strays()
  '';

in
{
  options.hwc.media.scripts = {
    sweep = {
      enable = lib.mkEnableOption "hot->cold download sweep timer";

      interval = lib.mkOption {
        type = lib.types.str;
        default = "5min";
        description = "How often to run the sweep (systemd time span)";
      };
    };
  };

  config = lib.mkIf cfg.sweep.enable {
    assertions = [
      {
        assertion = paths.hot.downloads != null;
        message = "hwc.media.scripts.sweep requires hwc.paths.hot.downloads (server only)";
      }
    ];

    systemd.services.hot-sweep = {
      description = "Sweep orphaned downloads from hot storage";
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${sweepScript}";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.timers.hot-sweep = {
      description = "Periodic hot storage sweep";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnUnitActiveSec = cfg.sweep.interval;
        OnBootSec = "10min";
        Persistent = true;
      };
    };
  };
}
