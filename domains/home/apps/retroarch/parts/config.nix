# Pure helper for generating RetroArch configuration
{ lib, cfg }:

let
  boolToString = b: if b then "true" else "false";
in
{
  # Generate retroarch.cfg content
  generateConfig = ''
    # RetroArch Configuration (NixOS HWC Generated)
    # Manual edits will be preserved unless config is regenerated

    # === UI Settings ===
    menu_driver = "${cfg.theme}"
    menu_swap_ok_cancel_buttons = "false"
    menu_show_core_updater = "false"  # Cores managed by Nix

    # === Video Settings ===
    video_driver = "${cfg.videoDriver}"
    video_fullscreen = "${boolToString cfg.fullscreen}"
    video_smooth = "true"
    video_threaded = "true"
    video_vsync = "true"
    video_hard_sync = "false"
    video_shader_enable = "${boolToString cfg.enableShaders}"
    ${lib.optionalString cfg.enableShaders ''
    video_shader_dir = "~/.config/retroarch/shaders"
    ''}

    # === Audio Settings ===
    audio_driver = "${cfg.audioDriver}"
    audio_enable = "true"
    audio_sync = "true"
    audio_latency = "64"
    audio_max_timing_skew = "0.05"

    # === Input Settings ===
    input_autodetect_enable = "true"
    input_joypad_driver = "udev"
    input_max_users = "4"
    input_menu_toggle_gamepad_combo = "2"  # L3+R3
    input_player1_analog_dpad_mode = "1"  # 0=none, 1=left analog, 2=right analog
    input_autoconfig_dir = "/home/eric/.config/retroarch/autoconfig"

    # === Paths ===
    rgui_browser_directory = "${cfg.romPath}"
    content_database_path = "~/.config/retroarch/database/rdb"
    cursor_directory = "~/.config/retroarch/database/cursors"
    cheat_database_path = "~/.config/retroarch/cheats"
    video_shader_dir = "~/.config/retroarch/shaders"
    assets_directory = "~/.config/retroarch/assets"

    # Save/State paths
    savestate_directory = "${cfg.saveStatePath}/states"
    savefile_directory = "${cfg.saveStatePath}/saves"
    savestate_auto_save = "${boolToString cfg.autoSave}"
    savestate_auto_load = "${boolToString cfg.autoSave}"

    # === Performance ===
    rewind_enable = "${boolToString cfg.rewindSupport}"
    ${lib.optionalString cfg.rewindSupport ''
    rewind_granularity = "1"
    rewind_buffer_size = "20"
    ''}

    # === Network ===
    netplay_enable = "${boolToString cfg.netplay}"
    ${lib.optionalString cfg.netplay ''
    netplay_mode = "false"
    netplay_spectator_mode_enable = "false"
    netplay_client_swap_input = "true"
    netplay_use_mitm_server = "false"
    ''}

    # === Cheats ===
    cheat_database_path = "~/.config/retroarch/cheats"
    ${lib.optionalString (!cfg.enableCheats) ''
    # Cheats disabled - database not loaded
    ''}

    # === Core Options ===
    core_options_path = "~/.config/retroarch/retroarch-core-options.cfg"
    load_dummy_on_core_shutdown = "false"
    check_firmware_before_loading = "true"

    # === Logging ===
    log_verbosity = "true"
    frontend_log_level = "1"

    # === Misc ===
    fps_show = "false"
    notification_show_autoconfig = "true"
    menu_enable_kiosk_mode = "false"
    pause_nonactive = "true"
    quit_press_twice = "true"
    config_save_on_exit = "false"
  '';

  # Directory structure to create
  directories = [
    cfg.romPath
    "${cfg.saveStatePath}/states"
    "${cfg.saveStatePath}/saves"
    "~/.config/retroarch/assets"
    "~/.config/retroarch/database"
    "~/.config/retroarch/shaders"
    "~/.config/retroarch/cheats"
  ];
}
