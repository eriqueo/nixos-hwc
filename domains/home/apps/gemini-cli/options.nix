{ lib, osConfig ? {}, ...}:

{
  options.hwc.home.apps.gemini-cli = {
    enable = lib.mkEnableOption "AI agent that brings the power of Gemini directly into your terminal";
  };
}