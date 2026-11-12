{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.hwc.home.apps.atari-style;
in
{
  # OPTIONS
  options.hwc.home.apps.atari-style = {
    enable = lib.mkEnableOption "Atari-style terminal arcade collection";
    package = lib.mkOption {
      type = lib.types.package;
      description = "Packaged upstream terminal arcade collection.";
      default = pkgs.python3Packages.buildPythonApplication {
        pname = "atari-style";
        version = "0.1.0";
        src = inputs.atari-style;
        # Upstream leaks terminal modes/keys, accepts one-axis keyboard devices,
        # and auto-launches Breakout. Remove when all input tests pass unpatched.
        patches = [ ./terminal-session.patch ];
        pyproject = true;
        build-system = [ pkgs.python3Packages.setuptools ];
        dependencies = with pkgs.python3Packages; [ pygame blessed pillow moderngl numpy ];
        # Permanent by design: setuptools must include the metadata and shader
        # assets used by upstream's installed content discovery.
        postPatch = ''
          # nixpkgs supplies the compatible pygame community edition.
          substituteInPlace setup.py \
            --replace-fail 'packages=find_packages(),' 'packages=find_packages(), include_package_data=True,' \
            --replace-fail 'pygame>=2.5.0' 'pygame-ce>=2.5.0'
          printf 'recursive-include atari_style *\nrecursive-include terminal_arcade *\n' > MANIFEST.in
        '';
        nativeCheckInputs = [ pkgs.python3Packages.pytestCheckHook ];
        pytestFlags = [ "tests/test_registry.py" "tests/test_claugger.py" "tests/test_scripted_input.py" "tests/test_terminal_session.py" "tests/test_game_controls.py" "tests/test_input_devices.py" ];
        pythonImportsCheck = [ "atari_style.main" "atari_style.demos.games" ];
        meta = {
          description = "Terminal arcade games including Breakout, Galaga, Pac-Man and Grand Prix";
          homepage = "https://github.com/jcaldwell-labs/atari-style";
          license = lib.licenses.mit;
          mainProgram = "atari-style";
        };
      };
    };
  };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
