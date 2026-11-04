# Pure verification function; not a NixOS or Home Manager module.
{ inputs, lib, pkgs, repoRoot, self }:
{

screenshot-renamer = let
  c = self.nixosConfigurations.hwc-home.config;
  worker = c.systemd.services.screenshot-renamer.serviceConfig;
  laptop = self.nixosConfigurations.hwc-laptop.config.home-manager.users.eric;
  binds = laptop.wayland.windowManager.hyprland.settings.bind;
  pi = pkgs.callPackage (repoRoot + "/domains/home/apps/pi/parts/package.nix") {};
  python = pkgs.python3.withPackages (ps: [ ps.pillow ]);
in
assert lib.assertMsg (lib.length (lib.filter (host: lib.attrByPath [ "hwc" "automation" "screenshotRenamer" "enable" ] false host.config)
    (lib.attrValues self.nixosConfigurations)) == 1
  && c.hwc.automation.screenshotRenamer.enable
  && c.hwc.automation.screenshotRenamer.mode == "apply"
  && c.hwc.automation.screenshotRenamer.operatorReview
  && lib.elem "${c.hwc.paths.user.inbox}/screenshots" worker.BindPaths
  && !(lib.elem "${c.hwc.paths.user.inbox}/screenshots" worker.BindReadOnlyPaths)
  && lib.hasInfix " dispatch" worker.ExecStart
  && !(c.systemd.timers ? screenshot-renamer)
  && c.systemd.paths.screenshot-renamer.pathConfig.PathChanged == [ "${c.hwc.paths.user.inbox}/screenshots" "${c.hwc.paths.user.inbox}/screenshots/.screenshot-policy" ]
  && worker.Restart == "no"
  && worker.RestartForceExitStatus == [ 75 ]
  && worker.RestartSec == "30s"
  && lib.elem "${c.hwc.paths.user.inbox}/screenshots" c.services.borgbackup.jobs.hwc-backup.paths
  && lib.elem "${c.hwc.paths.state}/screenshot-renamer/work-*" c.services.borgbackup.jobs.hwc-backup.exclude
  && lib.elem "${c.hwc.paths.state}/screenshot-renamer/ledger.sqlite*" c.services.borgbackup.jobs.hwc-backup.exclude
  && c.systemd.timers.screenshot-renamer-check.wantedBy == [ "timers.target" ]
  && c.systemd.services.screenshot-renamer-check.serviceConfig.BindReadOnlyPaths == []
  && lib.any (b: lib.hasInfix "hwc-screenshot" (builtins.toJSON b) && lib.hasInfix "--private" (builtins.toJSON b)) binds
  && lib.any (b: lib.hasInfix "hwc-screenshot" (builtins.toJSON b) && lib.hasInfix "--private" (builtins.toJSON b))
    self.homeConfigurations."eric@hwc-laptop".config.wayland.windowManager.hyprland.settings.bind)
  "screenshot wiring must apply with explicit operator review, monitoring and capture privacy";
pkgs.runCommand "screenshot-renamer-contract" {
  nativeBuildInputs = [ python pi pkgs.tesseract ];
} ''
  export PYTHONDONTWRITEBYTECODE=1
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  cd ${inputs.screenshot-renamer}
  python3 -m unittest -v screenshot_renamer_checks test_worker
  python3 - <<'PY'
  from pathlib import Path
  import dataclasses, tempfile, socket
  from PIL import Image, ImageDraw, ImageFont
  import screenshot_renamer as r
  with tempfile.TemporaryDirectory() as d:
      p = Path(d)
      font = ImageFont.truetype("${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf", 32)
      image = Image.new("RGB", (900, 220), "white")
      ImageDraw.Draw(image).text((20, 35), "Quarterly sales report\nRevenue growth planning", font=font, fill="black")
      image.save(p / "shot.png")
      cfg = r.Config(p, p / "state", owner=socket.gethostname())
      text = r.ocr(cfg, p / "shot.png", p)
      assert "Quarterly sales report" in text, text
  PY
  touch "$out"
'';

mqtt-webhook-contract = let
  module = import (repoRoot + "/domains/automation/mqtt/index.nix") {
    inherit pkgs lib;
    config.hwc = {
      paths.state = "/tmp";
      automation.mqtt = {
        enable = true;
        port = 18884;
        dataDir = "/tmp/mqtt";
        webhookBridge = {
          enable = true;
          topic = "fixture/events";
          eventTypes = [ "end" ];
          webhookUrl = "http://127.0.0.1:18386/capture";
        };
      };
    };
  };
  bridge = module.config.content.systemd.services.mqtt-webhook-bridge.content.serviceConfig.ExecStart;
in pkgs.runCommand "mqtt-webhook-contract" {
  nativeBuildInputs = [ pkgs.python3 pkgs.mosquitto ];
} ''
  python3 ${(repoRoot + "/domains/automation/mqtt/test_bridge.py")} ${bridge}
  touch $out
'';

# ── The SR gauntlet units can actually run `flock` ──────────────────
# run.sh serializes the poll timer against the run-now drain with flock,
# which NixOS' default service PATH does not provide: without
# pkgs.util-linux on srgPath both units exit 1 at the lock line, before
# any investigation. Resolved against the PATH systemd will really set
# (read off the rendered unit files of the evaluated hwc-home config),
# not against the srgPath list, so this cannot pass on a package that is
# named but never reaches the unit.
# The gauntlet runs on hwc-work since service split wave 1; the check
# follows it (it failed "no subject" while still pointed at hwc-home).
# Rebuilding a runtime must not launch or interrupt investigations.
gauntlet-switch-policy = let
  services = self.nixosConfigurations.hwc-work.config.systemd.services;
  names = [ "sr-gauntlet" "sr-gauntlet-runnow" "dx1-gauntlet" "dx1-gauntlet-runnow" ];
in
assert lib.all (name:
  builtins.hasAttr name services && !services.${name}.restartIfChanged
  && lib.hasInfix "X-RestartIfChanged=false"
    self.nixosConfigurations.hwc-work.config.systemd.units."${name}.service".text
) names;
pkgs.runCommand "gauntlet-switch-policy" {} ''touch "$out"'';

sr-gauntlet-flock = let
  server = self.nixosConfigurations."hwc-work".config;
  units = [ "sr-gauntlet.service" "sr-gauntlet-runnow.service" ];
  unitFile = n: pkgs.writeText "check-${n}" server.systemd.units.${n}.text;
in
assert lib.assertMsg server.hwc.automation.srGauntlet.enable
  "sr-gauntlet-flock: srGauntlet is disabled on hwc-work — this check has no subject and would pass empty";
pkgs.runCommand "sr-gauntlet-flock" {} ''
  fail=0
  ${lib.concatMapStringsSep "\n" (n: ''
    unitPath=""
    while IFS= read -r line; do
      case "$line" in
        Environment=*PATH=*) unitPath="''${line#*PATH=}"; unitPath="''${unitPath%\"}" ;;
      esac
    done < ${unitFile n}
    if [ -z "$unitPath" ]; then
      echo "FAIL: ${n} sets no PATH — srgPath is not reaching the unit." >&2
      fail=1
    elif ! ( PATH="$unitPath"; command -v flock >/dev/null ); then
      echo "FAIL: ${n} has no flock on its PATH. run.sh takes its lock with" >&2
      echo "      flock; the unit exits 1 before any work. Add pkgs.util-linux" >&2
      echo "      to srgPath in domains/automation/sr-gauntlet/index.nix." >&2
      fail=1
    fi
  '') units}
  [ "$fail" = 0 ] || exit 1
  touch $out
'';

# Exercise the generated wrapper: quiet mornings have no external effect,
# while decisions and errors still notify and every run retains its audit.
nightly-review-silent = let
  work = self.nixosConfigurations.hwc-work.config;
  fixture = pkgs.writeText "nightly-review-fixture.json" (builtins.toJSON {
    script = work.systemd.services.nightly-builds-review.serviceConfig.ExecStart;
    cli = "${work.hwc.automation.refinery.package}/bin/refinery-morning-review";
  });
in pkgs.runCommand "nightly-review-silent" {
  nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.jq pkgs.coreutils ];
} ''
  python3 ${./test_nightly_review.py} ${fixture}
  touch "$out"
'';

# Tracked n8n workflow JSON is a REDACTED DERIVED EXPORT of live n8n
# (domains/automation/n8n/parts/workflows/README.md). This runs the same
# scanner the export tool refuses to write past, so a raw webhook, bearer
# token, API key or unrecognised credential-shaped literal cannot reach
# git through a hand-pasted export. The rule table lives in the tool, not
# here — one producer — and is exercised by
# workspace/automation/test_n8n_workflow_export.py.
n8n-workflow-secret-literals = pkgs.runCommand "n8n-workflow-secret-literals" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  cd ${self}
  python3 workspace/automation/n8n-workflow-export.py \
    scan --dir domains/automation/n8n/parts/workflows
  touch $out
'';
}
