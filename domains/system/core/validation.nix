# Permission model validation for the system core domain
{ config, lib, pkgs, ... }:
{
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf config.hwc.system.core.validation.enable {
    systemd.services.hwc-permission-validation = {
      description = "Validate HWC permission model assumptions";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
      FAILED=0

      echo "===================================="
      echo "HWC Permission Model Validation"
      echo "===================================="
      echo ""

      # Check 1: eric primary group is users (GID 100)
      ERIC_GID=$(${pkgs.coreutils}/bin/id -g eric 2>/dev/null || echo "MISSING")
      if [[ "$ERIC_GID" != "100" ]]; then
        echo "❌ FAIL: eric primary GID is $ERIC_GID, expected 100 (users)"
        FAILED=1
      else
        echo "✅ PASS: eric primary group is users (GID 100)"
      fi

      # Check 2: eric user is UID 1000
      ERIC_UID=$(${pkgs.coreutils}/bin/id -u eric 2>/dev/null || echo "MISSING")
      if [[ "$ERIC_UID" != "1000" ]]; then
        echo "❌ FAIL: eric UID is $ERIC_UID, expected 1000"
        FAILED=1
      else
        echo "✅ PASS: eric UID 1000"
      fi

      # Check 3: /home/eric owned by eric:users
      if [[ -d /home/eric ]]; then
        HOME_OWNER=$(${pkgs.coreutils}/bin/stat -c '%U:%G' /home/eric)
        if [[ "$HOME_OWNER" != "eric:users" ]]; then
          echo "❌ FAIL: /home/eric owned by $HOME_OWNER, expected eric:users"
          FAILED=1
        else
          echo "✅ PASS: /home/eric owned by eric:users"
        fi
      else
        echo "⚠️  WARNING: /home/eric doesn't exist"
      fi

      # Check 4: eric in secrets group
      if ${pkgs.coreutils}/bin/groups eric | ${pkgs.gnugrep}/bin/grep -q secrets; then
        echo "✅ PASS: eric in secrets group"
      else
        echo "❌ FAIL: eric not in secrets group"
        FAILED=1
      fi

      echo ""
      echo "===================================="

      if [[ $FAILED -eq 1 ]]; then
        echo "❌ Permission validation FAILED"
        echo ""
        echo "See docs/troubleshooting/permissions.md for resolution steps"
        exit 1
      fi

      echo "✅ All permission validations passed"
      echo ""
    '';
    };
  };
}
