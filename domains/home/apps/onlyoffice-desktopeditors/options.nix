{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.apps.onlyoffice-desktopeditors = {
    enable = lib.mkEnableOption "Office suite that combines text, spreadsheet and presentation editors allowing to create, view and edit local documents";
  };
}