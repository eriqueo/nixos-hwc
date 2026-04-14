{ lib, ... }:

{
  options.hwc.home.apps.scraper = {
    enable = lib.mkEnableOption "Playwright-based social media scraper";
  };
}
