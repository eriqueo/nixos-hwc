{ lib, ... }:

{
  options.hwc.home.apps.wayvnc = {
    enable = lib.mkEnableOption "Wayland VNC server (wayvnc) for second-screen use";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Autostart wayvnc with the graphical session.";
    };

    network = {
      address = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Bind address for wayvnc (localhost by default for SSH/Tailscale tunneling).";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5901;
        description = "VNC port to listen on.";
      };
    };

    virtualOutput = {
      enable = lib.mkEnableOption "Create a virtual output for the VNC session" // { default = true; };

      name = lib.mkOption {
        type = lib.types.str;
        default = "VIRTUAL1";
        description = "Virtual output name passed to wlr-randr and wayvnc.";
      };

      mode = lib.mkOption {
        type = lib.types.str;
        default = "1920x1080@60";
        description = "Resolution and refresh rate for the virtual output.";
      };

      position = lib.mkOption {
        type = lib.types.str;
        default = "0,0";
        description = "Position for the virtual output relative to other displays.";
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = { render_cursor = true; enable_auth = true; output = "VIRTUAL1"; };
      description = "Additional wayvnc settings merged into the generated config.";
    };
  };
}
