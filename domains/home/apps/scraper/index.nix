{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.scraper;
  enabled = cfg.enable;

  # Handshake protocol for standalone compatibility
  nixosPath = lib.attrByPath [ "hwc" "paths" "nixos" ] "/home/eric/.nixos" osConfig;

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    pandas
    playwright
    pydantic
  ]);

  # Wrapper script that sets up Playwright browsers and runs the scraper
  scraperScript = pkgs.writeShellScriptBin "scraper" ''
    export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
    exec ${pythonEnv}/bin/python ${nixosPath}/workspace/hwc/social_media_scraper/scraper.py "$@"
  '';

  # Pass 2: Comment scraper for deeper analysis
  commentScraperScript = pkgs.writeShellScriptBin "scrape-comments" ''
    export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
    exec ${pythonEnv}/bin/python ${nixosPath}/workspace/hwc/social_media_scraper/scrape_comments.py "$@"
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    home.packages = [
      scraperScript
      commentScraperScript
      pkgs.playwright-driver.browsers
    ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
}
