{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.sonarr;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  appVersion = "4.0.20.3014";
  runtimeVersion = "10.0.14";
  upstreamImage = "lscr.io/linuxserver/sonarr@sha256:386c962ee6e260e3a5656b25df2ed056bcc9b6410e197d075f9547fd14c23bca";
  archive = pkgs.fetchurl {
    url = "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/10.0.14/aspnetcore-runtime-10.0.14-linux-musl-x64.tar.gz";
    hash = "sha512-LPMIg8C6jKGpahWBpwcs7CKaGafcJVjInSqp2YmOLPiv6mu4489ZaHWFxm6tfauif+Yx4kHXKQ+7KUQl7XTFjg==";
  };
  # Temporary: Alpine 3.24 still ships 3.53.4. Remove when that branch's
  # signed sqlite-libs includes the 3.54 fixes and passes current-data recovery.
  sqliteNative = pkgs.pkgsMusl.stdenv.mkDerivation {
    pname = "sonarr-sqlite-native";
    version = "3.54.1";
    src = pkgs.fetchurl {
      url = "https://sqlite.org/2026/sqlite-autoconf-3540100.tar.gz";
      hash = "sha256-km740+q5P79uBgEZASc+7AdrJVlKThza3VDJh/T21k4=";
    };
    nativeBuildInputs = [ pkgs.patchelf ];
    # Reuse the pinned package's feature vocabulary; do not create a second list.
    env.NIX_CFLAGS_COMPILE = pkgs.pkgsMusl.sqlite.NIX_CFLAGS_COMPILE;
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      $CC -fPIC -shared -O2 sqlite3.c -Wl,-soname,libsqlite3.so.0 -o libsqlite3.so.0 -lm
      runHook postBuild
    '';
    installPhase = ''
      mkdir -p "$out/lib"
      cp libsqlite3.so.0 "$out/lib/"
    '';
    postFixup = ''
      # Alpine and Nix name musl's same ABI differently; use the target's name.
      patchelf --replace-needed libc.so libc.musl-x86_64.so.1 --remove-rpath "$out/lib/libsqlite3.so.0"
    '';
  };
  # Temporary: retain the vendor's complete applet/configuration surface and
  # add the pinned upstream wget fix. Remove when Alpine's signed BusyBox
  # rejects raw URL control characters and passes the same applet/boot tests.
  busyboxInputs = builtins.fromJSON ''
{"schemaVersion":1,"aportsRevision":"35f5eb2864e50dd4448758d31f3e2a32f733ab84","version":"1.37.0","pkgrel":31,"source":{"file":"busybox-1.37.0.tar.bz2","url":"https://busybox.net/downloads/busybox-1.37.0.tar.bz2","hash":"sha256-MxHf8y50ZJn03w1d8E1+s5Y4LX4Qi7klDntRm4NwQ6Q="},"config":{"file":"busyboxconfig","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/busyboxconfig","hash":"sha256-ZbKfYIXNeatfAy1+QplTSobD760kDnjBYYahm/hH/Mo="},"patches":[{"file":"0001-wget-add-header-Accept.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0001-wget-add-header-Accept.patch","hash":"sha256-DtxTw04Lf4LvtAEKxBfELBgokAiPg5RPH7VXulgmlos="},{"file":"0002-adduser-default-to-sbin-nologin-as-shell-for-system-.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0002-adduser-default-to-sbin-nologin-as-shell-for-system-.patch","hash":"sha256-H32VhJsM2gp11givyplNeC8KZ/4PHLR1eEJOut6yZsc="},{"file":"0003-ash-add-built-in-BB_ASH_VERSION-variable.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0003-ash-add-built-in-BB_ASH_VERSION-variable.patch","hash":"sha256-kFn+B+eocu0W5m+ctxHb/PTV0oMI8g3ZpsNpVjJpEck="},{"file":"0004-Avoid-redefined-warnings-when-buiding-with-utmps.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0004-Avoid-redefined-warnings-when-buiding-with-utmps.patch","hash":"sha256-isVHh/5r/rQqbBPkmzmsfGHoOcTOokPSc8cboQ8bSiw="},{"file":"0005-libbb-sockaddr2str-ensure-only-printable-characters-.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0005-libbb-sockaddr2str-ensure-only-printable-characters-.patch","hash":"sha256-PRbkPBH6Ov60QcZBKQcRaM6aep5YT8eMzBi7rpn+2oc="},{"file":"0006-modinfo-add-k-option-for-kernel-version.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0006-modinfo-add-k-option-for-kernel-version.patch","hash":"sha256-aDJmn6QT2aI2oiu00FGebMiXcaDvJKvXI6/ZnOUukA8="},{"file":"0007-nologin-Install-applet-to-sbin-instead-of-usr-sbin.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0007-nologin-Install-applet-to-sbin-instead-of-usr-sbin.patch","hash":"sha256-O/BuXN0aDUoK1UHIqDgAT9DE5G5ErTr20UatL2mWfTs="},{"file":"0008-pgrep-add-support-for-matching-against-UID-and-RUID.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0008-pgrep-add-support-for-matching-against-UID-and-RUID.patch","hash":"sha256-xDtu3gWWVq20c0ga/yqikjnSMrmY9zUwLpejJGUOd6M="},{"file":"0009-properly-fix-wget-https-support.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0009-properly-fix-wget-https-support.patch","hash":"sha256-S+Cp0orKpMEXxpSkgW+tSi0/eOIkZ238LRQH060NwXo="},{"file":"0010-fsck-resolve-LABEL-.-UUID-.-spec-to-device.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0010-fsck-resolve-LABEL-.-UUID-.-spec-to-device.patch","hash":"sha256-9FYVx6mFswRl2l2To1NUBGNvRag8vu+vvQvLawyGNx8="},{"file":"0011-nslookup-sanitize-all-printed-strings-with-printable.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0011-nslookup-sanitize-all-printed-strings-with-printable.patch","hash":"sha256-ofKCaAR+niaPl2Dz88m/U/QetacS4JIvEF3SO5bADcc="},{"file":"0012-ash-exec-busybox.static.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0012-ash-exec-busybox.static.patch","hash":"sha256-gTVVu2m8m5f/PX7BRWnrJ2PsFr/ZZQu6Xx8IulzUImw="},{"file":"0013-app-location-for-cpio-vi-and-lspci.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0013-app-location-for-cpio-vi-and-lspci.patch","hash":"sha256-fwg7VwXawc+oCVPjLoOqpl5CNMQaWfFXi/xAOhq/Tu0="},{"file":"0014-udhcpc-set-default-discover-retries-to-5.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0014-udhcpc-set-default-discover-retries-to-5.patch","hash":"sha256-PjBrBSot9BNN5hAS3pB4k66+uc0QfpQQ6Bdw1gYIxB0="},{"file":"0015-ping-make-ping-work-without-root-privileges.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0015-ping-make-ping-work-without-root-privileges.patch","hash":"sha256-gCgnWJ6xwE9jS6j2kVjPC6h+QQYZNbpQR8zIMivyD0E="},{"file":"0016-fbsplash-support-console-switching.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0016-fbsplash-support-console-switching.patch","hash":"sha256-TbGw/pF4waBPjqY6mRXbhhWRIDmOi9YZwCMa+jA0ctQ="},{"file":"0017-fbsplash-support-image-and-bar-alignment-and-positio.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0017-fbsplash-support-image-and-bar-alignment-and-positio.patch","hash":"sha256-0Sj6Yzz60IRda9XwruY0q5lxsu3WABrZHZmzwb6K7pE="},{"file":"0018-depmod-support-generating-kmod-binary-index-files.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0018-depmod-support-generating-kmod-binary-index-files.patch","hash":"sha256-aBfhT2ja5hKpGqfXXnaxISpbuo6c/f8RM25ga97tmOs="},{"file":"0019-Add-flag-for-not-following-symlinks-when-recursing.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0019-Add-flag-for-not-following-symlinks-when-recursing.patch","hash":"sha256-pPDlmIdOAikHHG/lk4DNbHOdaOy8dOHu8t525g6kkDA="},{"file":"0020-udhcpc-Don-t-background-if-n-is-given.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0020-udhcpc-Don-t-background-if-n-is-given.patch","hash":"sha256-PMKyFClRS1fXXmaki25MIGjJMfkemT6GJajyLQTarUs="},{"file":"0021-tests-fix-tarball-creation.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0021-tests-fix-tarball-creation.patch","hash":"sha256-3UwQ4NKhR50jZ88RbgW9oJ8PKSFjb2WvmUKNDP9UJBI="},{"file":"0022-tests-musl-doesn-t-seem-to-recognize-UTC0-as-a-timez.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0022-tests-musl-doesn-t-seem-to-recognize-UTC0-as-a-timez.patch","hash":"sha256-qx8iVBaRWs8EiizONXHbvpQuzXsRRJJAG54GNFZ+Yzo="},{"file":"0023-Hackfix-to-disable-HW-acceleration-for-MD5-SHA1-on-x.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0023-Hackfix-to-disable-HW-acceleration-for-MD5-SHA1-on-x.patch","hash":"sha256-u5hYcl9iwa7Juu6s5KIXpKIWroSIpKBOkvwiXvTwY8U="},{"file":"0024-umount-Implement-O-option-to-unmount-by-mount-option.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0024-umount-Implement-O-option-to-unmount-by-mount-option.patch","hash":"sha256-/hse1Jg8JpYL+diAYuUvbx8nNaVNFSNDYdKyxT7vFM4="},{"file":"0025-find-fix-xdev-depth-and-delete.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0025-find-fix-xdev-depth-and-delete.patch","hash":"sha256-2IFG2+xpljRbglgFQIqMhV5hbey0rSVVUBKzfWBca2I="},{"file":"0026-awk.c-fix-CVE-2023-42366-bug-15874.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0026-awk.c-fix-CVE-2023-42366-bug-15874.patch","hash":"sha256-NKUkVbo4ZsQ9U1WAR/pA7bpRGCGJMKP4YNHTQ9x9Cag="},{"file":"0027-awk-Mark-test-for-handling-of-start-of-word-pattern-.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0027-awk-Mark-test-for-handling-of-start-of-word-pattern-.patch","hash":"sha256-9Hiyw4oS+tMYtDg59KqXxhFgh9TJhu1s4RMg4ZuECcE="},{"file":"0028-od-Skip-od-B-on-big-endian.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0028-od-Skip-od-B-on-big-endian.patch","hash":"sha256-g0g6FFiSJKb358A4g6vYtU1o3EbwBii+WaYezGjXkGc="},{"file":"0029-ash-reject-unknown-long-options.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0029-ash-reject-unknown-long-options.patch","hash":"sha256-TtG5WSt1q7dAh4gE3IzEjP/F5tps1tQxmow1CCtrGnc="},{"file":"0030-hexdump-Skip-a-single-test-on-big-endian-systems.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0030-hexdump-Skip-a-single-test-on-big-endian-systems.patch","hash":"sha256-oD5mxXaNT6WssneJQwGcHMyWyff1uLViBt+RfJ0olnw="},{"file":"0031-syslogd-fix-wrong-OPT_locallog-flag-detection.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0031-syslogd-fix-wrong-OPT_locallog-flag-detection.patch","hash":"sha256-pLjpWu/VOsNgv8iY8PCMp9hu9ReAWKNJl4OpnjckdBI="},{"file":"0032-lineedit-fix-some-tab-completions-written-to-stdout.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0032-lineedit-fix-some-tab-completions-written-to-stdout.patch","hash":"sha256-AyouQWmAohptyhtwJUOym2dajvhDmY2cJNMerLf8J8s="},{"file":"0033-lineedit-use-stdout-for-shell-history-builtin.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0033-lineedit-use-stdout-for-shell-history-builtin.patch","hash":"sha256-YSZYc9MtDQsSxCmnNt5slJ8NvNQ04erRdlvz/RnPwIQ="},{"file":"0034-adduser-remove-preconfigured-GECOS-full-name-field.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0034-adduser-remove-preconfigured-GECOS-full-name-field.patch","hash":"sha256-sbYjGNW0VQwqSubK10Mwu7kVnazdjwYXdZMR2dl3278="},{"file":"0035-cpio-map-F-to-file-long-option.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0035-cpio-map-F-to-file-long-option.patch","hash":"sha256-amWvSbhJciDrjvUCFn12vxKjD3zxoS62IAQeHv0HR7U="},{"file":"0001-hexdump-fix-regression-with-n4-e-u.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0001-hexdump-fix-regression-with-n4-e-u.patch","hash":"sha256-womz7XCWVXhGBp9oFOBjImslUubSapWcnjURZGnd3zU="},{"file":"0001-awk-fix-handling-of-literal-backslashes-in-replaceme.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0001-awk-fix-handling-of-literal-backslashes-in-replaceme.patch","hash":"sha256-Ui5IslsyC4VIhUGfPuOgkr1YrS7REdqHpXyvvIQg/q4="},{"file":"0001-tunctl-fix-segfault-on-ioctl-failure.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0001-tunctl-fix-segfault-on-ioctl-failure.patch","hash":"sha256-2EiGUdevRFAxDc4jS8Ys9XN6RzR49n4pihrVDGIFp4w="},{"file":"0001-init-add-support-for-separate-reboot-action.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0001-init-add-support-for-separate-reboot-action.patch","hash":"sha256-31snJYLr8Z3gYjQUaa3pJrHHRyeIcRkIVawNFsB59Rk="},{"file":"0001-blkdiscard-ship-link-to-sbin-instead-of-usr-bin.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0001-blkdiscard-ship-link-to-sbin-instead-of-usr-bin.patch","hash":"sha256-9JDOZDQSoz39PJKqrv9QGhDA94ZiFy0c9V5dYyt/gDM="},{"file":"0001-tar-fix-TOCTOU-symlink-race-condition.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0001-tar-fix-TOCTOU-symlink-race-condition.patch","hash":"sha256-GmXQhwB1/IPVjXXpGi5RjRvuGJgIMIb7lQKB63m306g="},{"file":"0001-netstat-sanitize-process-names.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0001-netstat-sanitize-process-names.patch","hash":"sha256-2vQoISCsvE6x2QchVl0uAcndw+7qvtTF9fqgT+PTPdM="},{"file":"0001-tar-fix-16018-masking-of-potentially-malicious-tar-cpio-content.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0001-tar-fix-16018-masking-of-potentially-malicious-tar-cpio-content.patch","hash":"sha256-i0Ji/7qqch08HWorHeuEp5SpklKxsV6XTsdsy56zxRc="},{"file":"0001-mount-fix-parsing-proc-mounts-with-long-lines.patch","url":"https://raw.githubusercontent.com/alpinelinux/aports/35f5eb2864e50dd4448758d31f3e2a32f733ab84/main/busybox/0001-mount-fix-parsing-proc-mounts-with-long-lines.patch","hash":"sha256-WXECatnkslI3C/S+YV99pqsUbMzFin5cs/IbksMq5Q0="}]}
  '';
  busyboxNative = pkgs.pkgsMusl.stdenv.mkDerivation {
    pname = "sonarr-busybox-native";
    version = busyboxInputs.version;
    src = pkgs.fetchurl { inherit (busyboxInputs.source) url hash; };
    patches = map (p: pkgs.fetchurl { inherit (p) url hash; }) busyboxInputs.patches
      ++ [
        (pkgs.path + "/pkgs/os-specific/linux/busybox/CVE-2025-60876.patch")
        # Required by Nix's fortify headers; build helper only, no applet change.
        (pkgs.path + "/pkgs/os-specific/linux/busybox/build-system-buffer-overflow.patch")
      ];
    nativeBuildInputs = [ pkgs.perl pkgs.patchelf ];
    hardeningDisable = [ "format" ];
    enableParallelBuilding = true;
    postPatch = "patchShebangs .";
    configurePhase = ''
      runHook preConfigure
      cp ${pkgs.fetchurl { inherit (busyboxInputs.config) url hash; }} .config
      export KCONFIG_NOTIMESTAMP=1
      make silentoldconfig
      runHook postConfigure
    '';
    buildPhase = ''
      runHook preBuild
      make -j"$NIX_BUILD_CORES" SKIP_STRIP=y \
        CONFIG_EXTRA_CFLAGS="-I${pkgs.pkgsMusl.utmps.dev}/include/utmps -I${pkgs.pkgsMusl.skalibs.dev}/include" \
        CONFIG_EXTRA_LDLIBS="${pkgs.pkgsMusl.utmps.lib}/lib/libutmps.a ${pkgs.pkgsMusl.skalibs.lib}/lib/libskarnet.a"
      runHook postBuild
    '';
    installPhase = ''
      mkdir -p "$out/bin"
      cp busybox "$out/bin/"
    '';
    postFixup = ''
      patchelf --set-interpreter /lib/ld-musl-x86_64.so.1 \
        --replace-needed libc.so libc.musl-x86_64.so.1 --remove-rpath "$out/bin/busybox"
      test "$(patchelf --print-needed "$out/bin/busybox")" = libc.musl-x86_64.so.1
    '';
  };
  # The pinned coreutils package carries both upstream 9.11 security backports.
  # Copy only the affected commands. Remove when the vendor includes the fixes.
  coreutilsNative = pkgs.pkgsMusl.coreutils.override {
    singleBinary = false;
    gmpSupport = false;
    aclSupport = false;
    attrSupport = false;
  };
  utilityPayload = pkgs.runCommand "sonarr-utility-payload" { nativeBuildInputs = [ pkgs.patchelf ]; } ''
    mkdir -p "$out"
    cp ${busyboxNative}/bin/busybox "$out/"
    for name in uniq unexpand; do
      cp ${coreutilsNative}/bin/"$name" "$out/"
      chmod u+w "$out/$name"
      patchelf --set-interpreter /lib/ld-musl-x86_64.so.1 \
        --replace-needed libc.so libc.musl-x86_64.so.1 --remove-rpath "$out/$name"
      test "$(patchelf --print-needed "$out/$name")" = libc.musl-x86_64.so.1
    done
  '';
  dependencyInputs = builtins.fromJSON ''
{"schemaVersion":1,"nuget":[{"name":"SixLabors.ImageSharp","version":"3.2.0","url":"https://api.nuget.org/v3-flatcontainer/sixlabors.imagesharp/3.2.0/sixlabors.imagesharp.3.2.0.nupkg","hash":"sha256-MeTyx2EoMmytE5XUl+COl2JBWQFvyVBktG9ig9hbtE0=","dependencies":{},"asset":"lib/net6.0/SixLabors.ImageSharp.dll","sha512":"5h7v5TVMDuu1jKHCuI7l1Oy1MrrERA8d4fFM3AHRrfuu/lfC44RN1+/wFJ01u3uzXb2pc2jC3ex+ZMsgDcqZPg==","dllSha256":"60d345f55451db74bbefb3231950c2524c12fe038173b08dabce4a844f22b179"},{"name":"System.Text.Json","version":"6.0.10","url":"https://api.nuget.org/v3-flatcontainer/system.text.json/6.0.10/system.text.json.6.0.10.nupkg","hash":"sha256-UijYh0dxFjFinMPSTJob96oaRkNm+Wsa+7Ffg6mRnsc=","dependencies":{"System.Runtime.CompilerServices.Unsafe":"6.0.0","System.Text.Encodings.Web":"6.0.0"},"asset":"lib/net6.0/System.Text.Json.dll","sha512":"CaQcnKNSM0DnDcAldC/sEv6XnodjeOb4pl2ebxjkEXkDIq393oh6d7FqKsTaDExNflMamwF6BBksReZQ3ljibQ==","dllSha256":"1546a1a36e7a94b944d7754d57b00d31abb8afbc3fd21d069685f0b7461196cb"},{"name":"System.Security.Cryptography.Pkcs","version":"8.0.2","url":"https://api.nuget.org/v3-flatcontainer/system.security.cryptography.pkcs/8.0.2/system.security.cryptography.pkcs.8.0.2.nupkg","hash":"sha256-NytlLOsMNKd+/2U4HvJDW5vJPoJhIWz13nEfx9nqcgA=","dependencies":{"System.Formats.Asn1":"8.0.2"},"asset":"lib/net6.0/System.Security.Cryptography.Pkcs.dll","sha512":"b7bL+Ge4ysa+tTvMmCF4kH4dV9cHTchWUgWCWOwEpoUjEn0jS+YOsKelvrtdTEemF9w6qCJtgsPoNFntBkSsRg==","dllSha256":"9adabedab3e739f8c689c8b3cf688d3d2c0b8ff787e1e7e649e39926353fe878"},{"name":"Microsoft.IdentityModel.JsonWebTokens","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/microsoft.identitymodel.jsonwebtokens/6.36.0/microsoft.identitymodel.jsonwebtokens.6.36.0.nupkg","hash":"sha256-oqh2tUnCvSgJgh/q2OOi0gacEftQ6UcS8EVSawev2Yw=","dependencies":{"Microsoft.IdentityModel.Tokens":"6.36.0"},"asset":"lib/net6.0/Microsoft.IdentityModel.JsonWebTokens.dll","sha512":"aE1/AeaMAY6QHLtVbU00iJp2ahN8h6qtxhYm2n3gj3ABW0RyqtgKcWwA1cZj25GqJEDlSv8XsbMU5AL1EhLE0w==","dllSha256":"0f3423ef4fe42d41fc41dde31e9ba73c7ebe2a6e966ef0c06d519ed7aa54556f"},{"name":"Microsoft.IdentityModel.Logging","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/microsoft.identitymodel.logging/6.36.0/microsoft.identitymodel.logging.6.36.0.nupkg","hash":"sha256-tPf3KaXBUAJ1Ot5OOZNDgw0zvSFg8ETPF0brnFc88cc=","dependencies":{"Microsoft.IdentityModel.Abstractions":"6.36.0"},"asset":"lib/net6.0/Microsoft.IdentityModel.Logging.dll","sha512":"Wl7NsaKNg2+2eIV0n8etB4SZd/plcv00tO/k89c67U86zHjwkX4NSb9tlJBjbzlIv0c45IAOM5JhUWahemPvYA==","dllSha256":"7c5efdfa85d6ad4be4d469c3308a944ee74c735930c9ad062ee19d19c2f2f6d0"},{"name":"Microsoft.IdentityModel.Protocols","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/microsoft.identitymodel.protocols/6.36.0/microsoft.identitymodel.protocols.6.36.0.nupkg","hash":"sha256-9gEc4Cf8TAfw0LMml0NPOuPg5m3HLKQO+Bn4Zlme4LM=","dependencies":{"Microsoft.IdentityModel.Logging":"6.36.0","Microsoft.IdentityModel.Tokens":"6.36.0"},"asset":"lib/net6.0/Microsoft.IdentityModel.Protocols.dll","sha512":"iIVrtmrBbwKwdu53W6lT7mRNeX5cGyrj+92T+KNBlgY8I4f8LHNzoce//zmoW6Wy6mW9ld2ENQbehzoqzYcm7g==","dllSha256":"78fdb1220fae418f15c62eff37e389924be71cc8074e8a6b35da2f7eda44b65a"},{"name":"Microsoft.IdentityModel.Protocols.OpenIdConnect","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/microsoft.identitymodel.protocols.openidconnect/6.36.0/microsoft.identitymodel.protocols.openidconnect.6.36.0.nupkg","hash":"sha256-eDd4LlsG2I3M8V5R8udeJo9IfwLsBIO137mRO60WeSs=","dependencies":{"Microsoft.IdentityModel.Protocols":"6.36.0","System.IdentityModel.Tokens.Jwt":"6.36.0"},"asset":"lib/net6.0/Microsoft.IdentityModel.Protocols.OpenIdConnect.dll","sha512":"yVL3z7fuvpKGFmTCwoG+BEwIccCPsVAIaswEUmmwn2TiPTNV7Al6k4YbUopN+MW49u3CJdLtMMPI441ka8oh+Q==","dllSha256":"41a5a6b903816670f15870db1840136466faefb7b1230c7b42d2420fc3f6f005"},{"name":"Microsoft.IdentityModel.Tokens","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/microsoft.identitymodel.tokens/6.36.0/microsoft.identitymodel.tokens.6.36.0.nupkg","hash":"sha256-0hVk4HUGcxzOlrI2L9G6HBwaVSsa0k0wNd6ETNRvyL0=","dependencies":{"Microsoft.IdentityModel.Logging":"6.36.0","Microsoft.CSharp":"4.5.0","System.Security.Cryptography.Cng":"4.5.0"},"asset":"lib/net6.0/Microsoft.IdentityModel.Tokens.dll","sha512":"F81jfcaWSG2HSK7GqBM8mP4MATMXh38/Ew9EUKo0Gh9bqx5hfb1NOnOUiQfCy8WAm3YNQdXT6HUX7gHoNL42vQ==","dllSha256":"2c53c0466031c668ccb78cf0d6c66e648125d1fdd25ca08987d25f806bab6c50"},{"name":"Microsoft.IdentityModel.Abstractions","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/microsoft.identitymodel.abstractions/6.36.0/microsoft.identitymodel.abstractions.6.36.0.nupkg","hash":"sha256-4jnbHNxwAlzyrpWTqRbsbPNKEhih8PYnbJvluuv6eNs=","dependencies":{},"asset":"lib/net6.0/Microsoft.IdentityModel.Abstractions.dll","sha512":"wwy1M1iFUCJzOz8kiyToD0cshUgNcpxAOvYliRZklplxlW0qdB7jqGObvXlJkqKeK22CM5Ugs9b5W48lxiPA6Q==","dllSha256":"e6a6a1592dea2efb426773c30df4c8c7d1fb47486d70b2a915b0f27fe9ea8c1a"},{"name":"System.IdentityModel.Tokens.Jwt","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/system.identitymodel.tokens.jwt/6.36.0/system.identitymodel.tokens.jwt.6.36.0.nupkg","hash":"sha256-lxO4xMZjjb4NXfD+r+Ydiq/3BC62fx4lG9qx4k5/Vks=","dependencies":{"Microsoft.IdentityModel.JsonWebTokens":"6.36.0","Microsoft.IdentityModel.Tokens":"6.36.0"},"asset":"lib/net6.0/System.IdentityModel.Tokens.Jwt.dll","sha512":"8Yc5Jc0bQP5JKfLZ2jd6l0ypHn+sBJ+tQtmHinBYK85q0ZeDX2OCUuSpSSl6rR3RCzGT+oeKvcS0zzjhMVcfqQ==","dllSha256":"c1466f994356a36cb120246eda642981627415f176747ee523cd869867628d5c"},{"name":"System.Formats.Asn1","version":"8.0.2","url":"https://api.nuget.org/v3-flatcontainer/system.formats.asn1/8.0.2/system.formats.asn1.8.0.2.nupkg","hash":"sha256-TVoJN39csCza2XtzLEJ4zTis9CC5FFN5OqvIwhPkON8=","dependencies":{},"asset":"lib/net6.0/System.Formats.Asn1.dll","sha512":"X/gV01xizlbDzBXcO7rD78pC4kacScwKw1jp2RV5gvdVxThB3H1HNPzgPQCf20w5ePrLXEpeII2cSJf1e2GOcQ==","dllSha256":"d1f9e4d62664a43b348df6c3a27e49855790bc34ccc4b6282e77f8299fec7caa"}],"apks":[{"name":"curl","version":"8.23.0-r0","url":"https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/curl-8.23.0-r0.apk","hash":"sha256-UxrimEUaTBxE9WP8Oy7twsHX4KJqM738Dv5vqv9qWUI=","file":"curl.apk"},{"name":"libcurl","version":"8.23.0-r0","url":"https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/libcurl-8.23.0-r0.apk","hash":"sha256-H3DKQEgYgFpkZbYVu/6E74YUiKlj1+YwEI69f7qlFmU=","file":"libcurl.apk"}]}
  '';
  dependencyManifest = pkgs.writeText "sonarr-dependencies.json" (builtins.toJSON dependencyInputs.nuget);
  updateDepsText = ''
$packages[0] as $ps |
def package($name): first($ps[] | select(.name==$name));
def target($p): {dependencies:$p.dependencies,runtime:{($p.asset):{}}};
def library($p): {type:"package",serviceable:true,sha512:("sha512-"+$p.sha512),path:(($p.name|ascii_downcase)+"/"+$p.version),hashPath:(($p.name|ascii_downcase)+"."+$p.version+".nupkg.sha512")};
(.targets[] |= (with_entries(
 (.key | split("/")[0]) as $name |
 if any($ps[]; .name==$name) then package($name) as $p | .key=($p.name+"/"+$p.version) | .value=target($p) else . end
) | if has("Microsoft.IdentityModel.Logging/"+package("Microsoft.IdentityModel.Logging").version) then package("Microsoft.IdentityModel.Abstractions") as $p | . + {($p.name+"/"+$p.version):target($p)} else . end
| .[] |= (if has("dependencies") then .dependencies |= with_entries(.key as $name | if any($ps[];.name==$name) then .value=package($name).version else . end) else . end))) |
(.libraries |= (with_entries(
 (.key | split("/")[0]) as $name |
 if any($ps[];.name==$name) then package($name) as $p | .key=($p.name+"/"+$p.version) | .value=library($p) else . end
) | if has("Microsoft.IdentityModel.Logging/"+package("Microsoft.IdentityModel.Logging").version) then package("Microsoft.IdentityModel.Abstractions") as $p | . + {($p.name+"/"+$p.version):library($p)} else . end))
  '';
  updateDeps = pkgs.writeText "sonarr-update-deps.jq" updateDepsText;
  dependencyPayload = pkgs.runCommand "sonarr-dependency-payload" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    mkdir -p "$out"
    python3 - "$out" <<'PYTHON'
    import pathlib,zipfile,hashlib,sys
    out=pathlib.Path(sys.argv[1])
    ${lib.concatMapStrings (p: let package = pkgs.fetchurl { inherit (p) url hash; }; in ''
    with zipfile.ZipFile('${package}') as z:
      data=z.read('${p.asset}')
      assert hashlib.sha256(data).hexdigest()=='${p.dllSha256}'
      (out/'${p.name}.dll').write_bytes(data)
    '' ) dependencyInputs.nuget}
    PYTHON
    ${lib.concatMapStrings (p: let package = pkgs.fetchurl { inherit (p) url hash; }; in ''
      cp ${package} "$out/${p.file}"
    '' ) dependencyInputs.apks}
  '';
  # Temporary: the vendor still bundles EOL .NET 6. Remove this rehosting
  # boundary when its image uses a supported patched runtime and passes the
  # current-data old/new/old/new recovery and native SQLite/API checks.
  applyRuntimeText = ''
    set -eu
    cd /app/sonarr/bin
    printf '%s\n' '59249a28421932787ff6dc96904cacbc7126d8678a8592401651dff18d2e722b  Sonarr.deps.json' '76bb233960042c712ba12c5c7f2e86bfdd19d39d58ebb10a00cf3128a6f4aa6a  Sonarr.runtimeconfig.json' | sha256sum -c -
    # Ownership comes from the hash-bound vendor manifest. Never delete an
    # app-owned assembly even if a future vendor manifest changes ownership.
    jq -r '.targets[] | to_entries[] | select(.key | startswith("runtimepack.")) | .value | (.runtime // {}, .native // {}) | keys[]' Sonarr.deps.json | sort -u > /tmp/runtime-owned.txt
    jq -r '.targets[] | to_entries[] | select(.key | startswith("runtimepack.") | not) | .value | (.runtime // {}, .native // {}) | keys[]' Sonarr.deps.json | sort -u > /tmp/app-owned.txt
    test "$(wc -l < /tmp/runtime-owned.txt)" -eq 302
    test -z "$(comm -12 /tmp/runtime-owned.txt /tmp/app-owned.txt)"
    while IFS= read -r name; do
      case "$name" in ""|*/*|*..*) echo SONARR_RUNTIME_PATH_INVALID >&2; exit 1;; esac
      test -f "$name"
      rm -- "$name"
    done < /tmp/runtime-owned.txt
    jq '(.targets[] |= with_entries(select(.key | startswith("runtimepack.") | not))) | (.libraries |= with_entries(select(.key | startswith("runtimepack.") | not)))' Sonarr.deps.json > Sonarr.deps.json.new
    mv Sonarr.deps.json.new Sonarr.deps.json
    jq --arg version '${runtimeVersion}' '.runtimeOptions |= (del(.includedFrameworks) | .frameworks = [{name:"Microsoft.NETCore.App",version:$version},{name:"Microsoft.AspNetCore.App",version:$version}])' Sonarr.runtimeconfig.json > Sonarr.runtimeconfig.json.new
    mv Sonarr.runtimeconfig.json.new Sonarr.runtimeconfig.json
    mkdir -p /opt/hwc-dotnet
    tar -xzf /tmp/hwc-sonarr/runtime.tar.gz -C /opt/hwc-dotnet
    printf '%s\n' '#!/bin/sh' 'exec /opt/hwc-dotnet/dotnet /app/sonarr/bin/Sonarr.dll "$@"' > Sonarr
    chmod 0755 Sonarr
    case "$(/opt/hwc-dotnet/dotnet --list-runtimes)" in
      *"Microsoft.AspNetCore.App ${runtimeVersion} "*) ;; *) exit 1;;
    esac
    cd /tmp/hwc-sonarr
    jq -r '.[] | .dllSha256 + "  " + .name + ".dll"' manifest.json | sha256sum -c -
    apk verify ./*.apk
    apk --repositories-file /dev/null --no-network --no-cache add ./*.apk
    for file in /app/sonarr/bin/*.deps.json; do
      jq --slurpfile packages manifest.json -f update-deps.jq "$file" > "$file.new"
      mv "$file.new" "$file"
    done
    cp ./*.dll /app/sonarr/bin/
    apk --repositories-file /dev/null --no-network del sqlite-libs
    cp libsqlite3.so.0 /usr/lib/libsqlite3.so.0
    sha256sum -c utilities-sha256
    # Replace inodes: the shell executes BusyBox, and GNU applets are symlinks
    # to one shared coreutils binary. Never follow those links while writing.
    for name in busybox uniq unexpand; do
      target=/usr/bin/$name
      if [ "$name" = busybox ]; then target=/bin/busybox; fi
      install -m 0755 "$name" "$target.hwc-new"
      mv -fT "$target.hwc-new" "$target"
    done
    cd /
    rm -r /tmp/hwc-sonarr /tmp/runtime-owned.txt /tmp/app-owned.txt
  '';
  applyRuntime = pkgs.writeText "sonarr-apply-runtime.sh" applyRuntimeText;
  runtime = helpers.mkRuntimeImage {
    name = "sonarr";
    version = "${appVersion}-dotnet${runtimeVersion}";
    recipe = ''
      FROM ${upstreamImage}
      # Bound payload: ${builtins.hashString "sha256" (applyRuntimeText + toString archive + builtins.toJSON dependencyInputs + updateDepsText + toString sqliteNative + toString utilityPayload)}
      COPY . /tmp/hwc-sonarr/
      RUN sh /tmp/hwc-sonarr/apply-runtime.sh
    '';
  };
  runtimeContext = pkgs.runCommand "sonarr-runtime-context" {} ''
    mkdir -p "$out"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${applyRuntime} "$out/apply-runtime.sh"
    cp ${archive} "$out/runtime.tar.gz"
    cp ${dependencyManifest} "$out/manifest.json"
    cp ${updateDeps} "$out/update-deps.jq"
    cp ${dependencyPayload}/* "$out/"
    cp ${sqliteNative}/lib/libsqlite3.so.0 "$out/libsqlite3.so.0"
    printf '%s\n' '${sqliteNative.version}' > "$out/sqlite-version"
    sha256sum "$out/libsqlite3.so.0" | cut -d' ' -f1 > "$out/sqlite-sha256"
    cp ${utilityPayload}/* "$out/"
    (cd "$out"; sha256sum busybox uniq unexpand > utilities-sha256)
  '';

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.sonarr = {
    enable = lib.mkEnableOption "sonarr container";
    image = lib.mkOption { type = lib.types.str; default = runtime.image; description = "Qualified local image built from system.build.sonarrRuntimeImageContext"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = true; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.sonarrRuntimeImageRecipe = runtime.dockerfile;
    system.build.sonarrRuntimeImageContext = runtimeContext;
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
