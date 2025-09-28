{ lib, ... }:

{
  options.hwc.home.apps.geminiCli = {
    enable = lib.mkEnableOption "AI agent that brings the power of Gemini directly into your terminal";
  };
}
