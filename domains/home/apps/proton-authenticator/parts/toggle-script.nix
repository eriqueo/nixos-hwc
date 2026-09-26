{ pkgs }:

pkgs.writeShellScriptBin "proton-authenticator-toggle" ''
  set -euo pipefail
  # Keep the existing WebKit/X11 workaround while Hyprland owns the launch.
  exec hyprland-app-toggle Proton-authenticator \
    env WEBKIT_DISABLE_DMABUF_RENDERER=1 GDK_BACKEND=x11 \
    ${pkgs.proton-authenticator}/bin/proton-authenticator
''
