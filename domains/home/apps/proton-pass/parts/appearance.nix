# ProtonPass • Appearance part
# Theming and visual configuration.
{ lib, pkgs, config, osConfig ? {}, ... }:

{
  files = profileBase: {
    # Proton Pass manages its own config at ~/.config/Proton Pass/config.json
    # Cannot be managed by Home Manager - app needs write access
    # Set dark mode manually in app: Settings > Theme > Dark
  };
}