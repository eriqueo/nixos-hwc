# domains/home/apps/swaync/parts/appearance.nix
{ config, lib, pkgs, osConfig ? {}, ... }:

let
  colors = config.hwc.home.theme.colors;
in
{
  settings = {
    positionX = "right";
    positionY = "top";
    layer = "overlay";
    control-center-layer = "overlay";
    layer-shell = true;
    cssPriority = "user";
    control-center-margin-top = 10;
    control-center-margin-bottom = 10;
    control-center-margin-right = 10;
    control-center-margin-left = 0;
    notification-2fa-action = true;
    notification-inline-replies = false;
    notification-icon-size = 64;
    notification-body-image-height = 100;
    notification-body-image-width = 200;
    timeout = 10;
    timeout-low = 5;
    timeout-critical = 0;
    fit-to-screen = true;
    control-center-width = 500;
    control-center-height = 600;
    notification-window-width = 500;
    keyboard-shortcuts = true;
    image-visibility = "when-available";
    transition-time = 200;
    hide-on-clear = false;
    hide-on-action = true;
    script-fail-notify = true;
    widgets = [
      "title"
      "dnd"
      "notifications"
    ];
    widget-config = {
      title = {
        text = "Notifications";
        clear-all-button = true;
        button-text = "Clear All";
      };
      dnd = {
        text = "Do Not Disturb";
      };
      notifications = {
        clear-all-button = true;
      };
    };
  };

  style = ''
    * {
      all: unset;
      font-family: "JetBrainsMono Nerd Font";
      font-size: 14px;
    }

    .notification-row {
      outline: none;
      margin: 0;
      padding: 0;
    }

    .notification {
      background: #${colors.bg1};
      border: 2px solid #${colors.border};
      border-radius: 8px;
      margin: 8px;
      padding: 0;
    }

    .notification.critical {
      border: 2px solid #${colors.error};
    }

    .notification-content {
      background: transparent;
      padding: 12px;
      margin: 0;
    }

    .close-button {
      background: #${colors.bg3};
      color: #${colors.fg0};
      border-radius: 6px;
      padding: 4px 8px;
      margin: 8px;
    }

    .close-button:hover {
      background: #${colors.error};
      color: #${colors.bg1};
    }

    .notification-default-action {
      margin: 0;
      padding: 0;
      border-radius: 8px;
    }

    .summary {
      font-weight: bold;
      color: #${colors.fg0};
      font-size: 16px;
      margin-bottom: 4px;
    }

    .time {
      color: #${colors.fg3};
      font-size: 12px;
      margin-right: 8px;
    }

    .body {
      color: #${colors.fg1};
      font-size: 14px;
    }

    .control-center {
      background: #${colors.bg0};
      border: 2px solid #${colors.border};
      border-radius: 12px;
      margin: 0;
      padding: 0;
    }

    .control-center-list {
      background: transparent;
      padding: 8px;
    }

    .control-center-list-placeholder {
      color: #${colors.fg3};
      font-size: 16px;
      padding: 20px;
    }

    .widget-title {
      background: #${colors.bg2};
      color: #${colors.fg0};
      font-size: 18px;
      font-weight: bold;
      padding: 12px;
      border-radius: 8px 8px 0 0;
    }

    .widget-title button {
      background: #${colors.bg3};
      color: #${colors.fg0};
      border-radius: 6px;
      padding: 6px 12px;
      margin-left: 8px;
    }

    .widget-title button:hover {
      background: #${colors.accent};
      color: #${colors.bg1};
    }

    .widget-dnd {
      background: #${colors.bg2};
      color: #${colors.fg0};
      padding: 12px;
      margin: 8px;
      border-radius: 8px;
    }

    .widget-dnd > switch {
      background: #${colors.bg3};
      border-radius: 12px;
      padding: 4px;
    }

    .widget-dnd > switch:checked {
      background: #${colors.accent};
    }

    .widget-dnd > switch slider {
      background: #${colors.fg0};
      border-radius: 10px;
    }

    .notification-action {
      background: #${colors.bg3};
      color: #${colors.fg0};
      border-radius: 6px;
      padding: 8px 16px;
      margin: 4px;
    }

    .notification-action:hover {
      background: #${colors.accent};
      color: #${colors.bg1};
    }

    .inline-reply {
      background: #${colors.bg2};
      color: #${colors.fg0};
      border: 1px solid #${colors.border};
      border-radius: 6px;
      padding: 8px;
      margin: 4px;
    }

    .inline-reply:focus {
      border: 1px solid #${colors.accent};
    }

    .image {
      margin: 8px;
      border-radius: 6px;
    }
  '';
}