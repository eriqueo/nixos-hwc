{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.scraper;
  enabled = cfg.enable;

  # Handshake protocol for standalone compatibility (home-derived fallback, Law 3)
  nixosPath =
    let p = lib.attrByPath [ "hwc" "paths" "nixos" ] null osConfig;
    in if p != null then p else "${config.home.homeDirectory}/.nixos";

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    pandas
    playwright
    pydantic
  ]);

  # Wrapper script that sets up Playwright browsers and runs the scraper
  scraperScript = pkgs.writeShellScriptBin "scraper" ''
    export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
    exec ${pythonEnv}/bin/python ${nixosPath}/workspace/home/scraper/scraper.py "$@"
  '';

  # Pass 2: Comment scraper for deeper analysis
  commentScraperScript = pkgs.writeShellScriptBin "scrape-comments" ''
    export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
    exec ${pythonEnv}/bin/python ${nixosPath}/workspace/home/scraper/scrape_comments.py "$@"
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.scraper = {
    enable = lib.mkEnableOption "Playwright-based social media scraper";
  };

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
