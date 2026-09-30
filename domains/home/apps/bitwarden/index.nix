# One-package desktop client; account data stays in Bitwarden's own state.
import ../../../lib/mkSimpleApp.nix {
  name = "bitwarden";
  description = "Bitwarden desktop client for the self-hosted vault";
  package = pkgs:
    let
      upstream = pkgs.bitwarden-desktop;
      launcher = pkgs.writeText "bitwarden-portal-launcher.py" (builtins.readFile ./portal-launcher.py);
    in pkgs.symlinkJoin {
      name = "bitwarden-desktop-${upstream.version}-portal";
      paths = [ upstream ];
      nativeBuildInputs = [ pkgs.makeWrapper pkgs.asar ];
      # Preserve the upstream launcher, resources, native modules and security.
      # Remove when direct portal requests from a hardened client work upstream.
      postBuild = ''
        cp "${upstream}/bin/bitwarden" "$out/bin/.bitwarden-real"
        substituteInPlace "$out/bin/.bitwarden-real" \
          --replace-fail "${upstream}/opt/Bitwarden/resources/app.asar" \
                         "$out/opt/Bitwarden/resources/app.asar"
        asar extract "${upstream}/opt/Bitwarden/resources/app.asar" bitwarden-portal
        substituteInPlace bitwarden-portal/main.js \
          --replace-fail 'electron_1.app.setPath("exe", "${upstream}/bin/bitwarden");' \
                         "electron_1.app.setPath(\"exe\", \"$out/bin/bitwarden\");"
        rm "$out/opt/Bitwarden/resources/app.asar"
        rm -r "$out/opt/Bitwarden/resources/app.asar.unpacked"
        asar pack bitwarden-portal "$out/opt/Bitwarden/resources/app.asar" \
          --unpack-dir 'node_modules/@bitwarden/desktop-napi'
        # Native code must stay outside ASAR, byte-for-byte unchanged.
        ${pkgs.python3}/bin/python3 - "${upstream}/opt/Bitwarden/resources/app.asar" "$out/opt/Bitwarden/resources/app.asar" <<'PY'
        import json, pathlib, struct, sys
        def unpacked(path):
            with open(path, 'rb') as f:
                _, _, _, size = struct.unpack('<4I', f.read(16))
                header = json.loads(f.read(size))
            def walk(node, prefix=""):
                for name, entry in node.get('files', {}).items():
                    if 'files' in entry:
                        yield from walk(entry, prefix + name + '/')
                    elif entry.get('unpacked'):
                        yield prefix + name
            return set(walk(header))
        old, new = sys.argv[1:]
        assert unpacked(old) == unpacked(new), 'Native resource layout changed'
        for name in unpacked(old):
            assert (pathlib.Path(old + '.unpacked') / name).read_bytes() == (pathlib.Path(new + '.unpacked') / name).read_bytes(), name
        PY
        rm -r bitwarden-portal
        rm "$out/bin/bitwarden"
        makeWrapper "${pkgs.python3}/bin/python3" "$out/bin/bitwarden" \
          --add-flags "${launcher}" \
          --add-flags "${pkgs.xdg-dbus-proxy}/bin/xdg-dbus-proxy" \
          --add-flags "$out/bin/.bitwarden-real" \
          --inherit-argv0
      '';
      passthru.portalLauncher = launcher;
      meta = upstream.meta;
    };
}
