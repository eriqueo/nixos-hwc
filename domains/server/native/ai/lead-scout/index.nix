# domains/server/native/ai/lead-scout/index.nix
#
# Lead Scout — native systemd service
# Long-running HTTP + MCP server on port 8420. Human access is tailnet-only at
# lead-scout.hwc.iheartwoodcraft.com; the Access-protected `leads-origin`
# tunnel hostname exists only for the OAuth MCP gateway.
#
# Scrape/classify scheduling is owned by the in-process cron scheduler
# (src/shells/scheduler.ts) driven by the scrape_sources DB table.
# Per-source schedules are managed via the UI/MCP — no NixOS timers.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hwc.server.ai.leadScout;

  # One producer for the database name (research-scout precedent). Renamed from
  # `datax` on 2026-08-26: the scraper was built under a project called datax in
  # 2026-05 and the database kept that birth name for three months. It holds
  # fb_posts, fb_comments, post_classifications and scrape_sources — lead-scout
  # tables, all of them, and no DataX table. Do not confuse it with
  # `datax_monitor`, which IS DataX monitoring and is a different database
  # (domains/business/datax-monitor).
  dbName = "lead_scout";

  node = "/run/current-system/sw/bin/node";
  # Direct node + tsx loader: the main PID is the app (domains/lib/mkTsNode.nix).
  tsNode = import ../../../../lib/mkTsNode.nix { } cfg.workspaceRoot;
  cli = "${cfg.projectDir}/src/cli.ts";
  claudeModel = "opus";

  # Member instance (options.memberInstance). One composition root for its
  # compose invocation, preflight, health proof and trusted-peer check.
  member = cfg.memberInstance;
  # Temporary same-app library and browser-trust correction. Retire after an
  # upstream image passes the library, Chrome policy and saved-profile proofs.
  # Public certificates only; no user settings or test CA keys enter the store.
  memberChromePolicyText = ''
    {
      "CADistrustedCertificates": [
        "MIICTjCCAdOgAwIBAgIKPPYHqWhwDtqLhDAKBggqhkjOPQQDAzBrMQswCQYDVQQGEwJJTjETMBEGA1UECxMKZW1TaWduIFBLSTElMCMGA1UEChMcZU11ZGhyYSBUZWNobm9sb2dpZXMgTGltaXRlZDEgMB4GA1UEAxMXZW1TaWduIEVDQyBSb290IENBIC0gRzMwHhcNMTgwMjE4MTgzMDAwWhcNNDMwMjE4MTgzMDAwWjBrMQswCQYDVQQGEwJJTjETMBEGA1UECxMKZW1TaWduIFBLSTElMCMGA1UEChMcZU11ZGhyYSBUZWNobm9sb2dpZXMgTGltaXRlZDEgMB4GA1UEAxMXZW1TaWduIEVDQyBSb290IENBIC0gRzMwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAAQjpQy4LRL1KPOxst3iAhKAnjlfSU2fySU0WXTsuwYc58Byr+iuL+FBVIcUqEqy6HyC5ltqtdyzdc6LBtCGI79G1Y4PPwT01xySfvalY8L1X44uT6EYGQIrMgqCZH0Wk9GjQjBAMB0GA1UdDgQWBBR8XQKEE9TMipuBzhccLikenEhjQjAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAwNpADBmAjEAvvNhzwIQHWSVB7gYboiFBS+DCBeQyh+KTOgNG3qxrdWBCUfvO6wIBHxcmbHtRwfSAjEAnbpV/KlK6O3t5nYBQnvI+GDZjVGLVTv7jHvrZQnD+JbNR6iC8hZVdyR+EhCVBCyj",
        "MIIDczCCAlugAwIBAgILAK7PALrEzzL4Q7IwDQYJKoZIhvcNAQELBQAwVjELMAkGA1UEBhMCVVMxEzARBgNVBAsTCmVtU2lnbiBQS0kxFDASBgNVBAoTC2VNdWRocmEgSW5jMRwwGgYDVQQDExNlbVNpZ24gUm9vdCBDQSAtIEMxMB4XDTE4MDIxODE4MzAwMFoXDTQzMDIxODE4MzAwMFowVjELMAkGA1UEBhMCVVMxEzARBgNVBAsTCmVtU2lnbiBQS0kxFDASBgNVBAoTC2VNdWRocmEgSW5jMRwwGgYDVQQDExNlbVNpZ24gUm9vdCBDQSAtIEMxMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAz+upufGZBczYKCFK83M0UYRWEPWgTywS4/oTmifQz/l5GnRfHXk5/Fv4cI7gklL35CX5VIPZHdPIWoU/Xse2B+4+wM6ar6xWQio5JXDWv7V7Nq2s9nPczdcdioOl+yuQFTdrHCZH3DspVpNqs8FqOp099cGXOFgFixwR4+S0uF2FHYP+eF8LRWgYSKVGczQ7/g/IdrvHGPMF0Ybzhe3nudkyrVWIzqa2kbBPrH4VI5b2P/AgNBbeCsbEBEV5f6f9vtKppa+cxSMq9zwhbL2vj07FOrLzNBL834AaSaTUqZX3noleoomslMuoaJuvimUnzYnu3Yy1aylwQ6BpC+S5DwIDAQABo0IwQDAdBgNVHQ4EFgQU/qHgcB4qAzlSWkK+XJGFehiqTbUwDgYDVR0PAQH/BAQDAgEGMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAMJKVvoVIXsoounlHfv4LcQ5lkFMOycsxGwYFYDGrK9HWS8mC+M2sO87/kOXSTKZEhVb3xEp/6tT+LvBeA+snFOvV71ojD1pM/CjoCNjO2RnIkSt1XHLVip4kqNPEjE2NuLe/gDEo2APJ62gsIq1NnpSob0n9CAnYuhNlCQT5AoE6TyrLshDCUrGYQTlSTR+08TI9Q/Aqum6VF7zYytPT1DU/rl7mYw9wC68AivTxEDkigcxHpvOJpkT+xHqmiIMERnHXhuBUDDIlhJu58tBf5E7oke3VIAb3ADMmpDqw8NQBmIMMMAVSKeoWXzhriKi4gp6D/piq1JM4fHfyr6DDUI=",
        "MIICKzCCAbGgAwIBAgIKe3G2gla4EnycqDAKBggqhkjOPQQDAzBaMQswCQYDVQQGEwJVUzETMBEGA1UECxMKZW1TaWduIFBLSTEUMBIGA1UEChMLZU11ZGhyYSBJbmMxIDAeBgNVBAMTF2VtU2lnbiBFQ0MgUm9vdCBDQSAtIEMzMB4XDTE4MDIxODE4MzAwMFoXDTQzMDIxODE4MzAwMFowWjELMAkGA1UEBhMCVVMxEzARBgNVBAsTCmVtU2lnbiBQS0kxFDASBgNVBAoTC2VNdWRocmEgSW5jMSAwHgYDVQQDExdlbVNpZ24gRUNDIFJvb3QgQ0EgLSBDMzB2MBAGByqGSM49AgEGBSuBBAAiA2IABP2lYa57JhAd6bciMK4G9IGzsUJxlTm801Ljr6/58pc1kjZGDoeVjbk5Wum739D+yAdBPLtVb4OjavtisIGJAnB9SMVK4+kiVCJNk7tCDK93nCOmfddhEc5lx/h//vXyqaNCMEAwHQYDVR0OBBYEFPtaSNCAIEDyqOkAB2kZd6fmw/TPMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMDA2gAMGUCMQC02C8Cif22TGK6Q04ThHK1rt0c3ta13FaPWEBaLd4gTCKDypOofu4SQMfWh0/434UCMBwUZOR8loMRnLDRWmFLpg9J0wD8ofzkpf9/rdcw0Md3f76BB1UwUCAU9Vc4CqgxUQ=="
      ]
    }
  '';
  memberChromePolicy = pkgs.writeText "scout-chrome-distrust-policy.json" memberChromePolicyText;
  memberBrotliFile = "libbrotli1_1.0.9-2+deb12u1_amd64.deb";
  memberBrotliHash = "e27b3d655fa6fadd7a56f706687e94573c0af68b7d6df394a32a381a3a6c6d8b";
  memberBrotli = pkgs.fetchurl {
    url = "https://security.debian.org/debian-security/pool/updates/main/b/brotli/${memberBrotliFile}";
    sha256 = memberBrotliHash;
  };
  # Signed Google Release/Packages and authenticated Debian APT metadata were
  # verified before pinning these archives. Context builds/installers are offline.
  # REPLACEABLE: fetchurl hashes plus this catalog rebuild the qualified image.
  memberChrome = rec {
    version = "156.0.8078.79";
    archive = "google-chrome-stable_${version}-1_amd64.deb";
    url = "https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/${archive}";
    sha256 = "be1a1e161419f5c8272432f6860912550d8e29985e925913fa800493a0d0c955";
    source = pkgs.fetchurl { inherit url sha256; name = archive; };
  };
  memberDebianCatalog = builtins.fromJSON ''[
    {"archive":"scout-runtime-000.deb","url":"https://deb.debian.org/debian/pool/main/a/adwaita-icon-theme/adwaita-icon-theme_43-1_all.deb","sha256":"4b67610565d16b604d3efd9908e8e4b5d71873c5d0f9347433df509020f22af7"},
    {"archive":"scout-runtime-001.deb","url":"https://deb.debian.org/debian/pool/main/a/apparmor/libapparmor1_3.0.8-3_amd64.deb","sha256":"4b79f49eafc2017374da9ec206b5495433eadd2b1ea078c3895c99e72825e9d3"},
    {"archive":"scout-runtime-002.deb","url":"https://deb.debian.org/debian/pool/main/a/argon2/libargon2-1_0%7e20171227-0.3%2bdeb12u1_amd64.deb","sha256":"4a8155b06270b88eed34d132acfc8ccc0b85499e1c4bfd7f31f8b199af42b1de"},
    {"archive":"scout-runtime-003.deb","url":"https://deb.debian.org/debian/pool/main/c/cairo/libcairo-gobject2_1.16.0-7_amd64.deb","sha256":"5898b4c1093ff40bade7acb92affc4a5b5b76a1737cd41cfa2a09cdc2d864d4c"},
    {"archive":"scout-runtime-004.deb","url":"https://deb.debian.org/debian/pool/main/c/colord/libcolord2_1.4.6-2.2_amd64.deb","sha256":"6e5a48b72ae316301103d642c8881cc06205cb4b5f54c25c467b2847048d268f"},
    {"archive":"scout-runtime-005.deb","url":"https://deb.debian.org/debian/pool/main/c/cryptsetup/libcryptsetup12_2.6.1-4%7edeb12u2_amd64.deb","sha256":"b9a607c219be5ef04bc0fcfaec3752d9a1ba07df8d3bb2aed9bf348f90d1b6cc"},
    {"archive":"scout-runtime-006.deb","url":"https://deb.debian.org/debian/pool/main/c/curl/libcurl3-gnutls_7.88.1-10%2bdeb12u15_amd64.deb","sha256":"bf430ecf80f7808704e0187cddc582fd57fc98789ea356d4797651edad387ef3"},
    {"archive":"scout-runtime-007.deb","url":"https://deb.debian.org/debian/pool/main/d/dbus/dbus_1.14.10-1%7edeb12u1_amd64.deb","sha256":"35932ffdc1ae80348e93c1263c504e62cae8a2a1476f1541ef63a9cc0a271ef9"},
    {"archive":"scout-runtime-008.deb","url":"https://deb.debian.org/debian/pool/main/d/dbus/dbus-bin_1.14.10-1%7edeb12u1_amd64.deb","sha256":"7273d6f5ddcafa6bc81e319997f60e9b511a92c4414c1d4ecb05cba9e755da57"},
    {"archive":"scout-runtime-009.deb","url":"https://deb.debian.org/debian/pool/main/d/dbus/dbus-daemon_1.14.10-1%7edeb12u1_amd64.deb","sha256":"d35e43de83f7df870196d292a60a56d320c47ce503bc586b30e47a192090302e"},
    {"archive":"scout-runtime-010.deb","url":"https://deb.debian.org/debian/pool/main/d/dbus/dbus-session-bus-common_1.14.10-1%7edeb12u1_all.deb","sha256":"b19cb8e3581d6b09ff3f46fee23de2813811353228c666c9d1ad885598062e43"},
    {"archive":"scout-runtime-011.deb","url":"https://deb.debian.org/debian/pool/main/d/dbus/dbus-system-bus-common_1.14.10-1%7edeb12u1_all.deb","sha256":"2111d3d0c98ac68ee973274058447e6fab1c359fec1d4bb195f5fcc5833a19e2"},
    {"archive":"scout-runtime-012.deb","url":"https://deb.debian.org/debian/pool/main/d/dbus/dbus-user-session_1.14.10-1%7edeb12u1_amd64.deb","sha256":"4c3aaad251f876214fadb5580dd5f4925f73838832135e6d1dab981eb963be6b"},
    {"archive":"scout-runtime-013.deb","url":"https://deb.debian.org/debian/pool/main/d/dconf/dconf-gsettings-backend_0.40.0-4_amd64.deb","sha256":"790a8ad2a229b378bbda7a0f32d9d8a522c986b08c556210c0514978ad88e356"},
    {"archive":"scout-runtime-014.deb","url":"https://deb.debian.org/debian/pool/main/d/dconf/dconf-service_0.40.0-4_amd64.deb","sha256":"2650490642fb7e66da94943d381cea277cb811e3a4aadb6386fcd402a8390759"},
    {"archive":"scout-runtime-015.deb","url":"https://deb.debian.org/debian/pool/main/d/dconf/libdconf1_0.40.0-4_amd64.deb","sha256":"d438bb2e3b5afaee2a90bb3fb541dcd2e47eefbc43994b5d0461c18648741e36"},
    {"archive":"scout-runtime-016.deb","url":"https://deb.debian.org/debian/pool/main/g/gdk-pixbuf/libgdk-pixbuf-2.0-0_2.42.10%2bdfsg-1%2bdeb12u4_amd64.deb","sha256":"19673127f2530deb7cf637c688a4e16384e6887627296e16b8169038928cadc3"},
    {"archive":"scout-runtime-017.deb","url":"https://deb.debian.org/debian/pool/main/g/gdk-pixbuf/libgdk-pixbuf2.0-common_2.42.10%2bdfsg-1%2bdeb12u4_all.deb","sha256":"0f3df073ca7eed5564ea3faceff819d94932d924c56474f1e42799a8017a2d30"},
    {"archive":"scout-runtime-018.deb","url":"https://deb.debian.org/debian/pool/main/g/gtk%2b3.0/gtk-update-icon-cache_3.24.38-2%7edeb12u3_amd64.deb","sha256":"6df214515e719d9099f6df89f4581abe34b63ea9237b76e93843e83226b2e9cb"},
    {"archive":"scout-runtime-019.deb","url":"https://deb.debian.org/debian/pool/main/g/gtk%2b3.0/libgtk-3-0_3.24.38-2%7edeb12u3_amd64.deb","sha256":"0ff7375c98b5a8d6aafc6096b21d9f7bae4ecb581d31fce5d37be18f55b489a2"},
    {"archive":"scout-runtime-020.deb","url":"https://deb.debian.org/debian/pool/main/g/gtk%2b3.0/libgtk-3-common_3.24.38-2%7edeb12u3_all.deb","sha256":"f2642d127d85440acbfc2ed404d3932d8b2fbe8a576ead7f93f35ac1fa999c92"},
    {"archive":"scout-runtime-021.deb","url":"https://deb.debian.org/debian/pool/main/h/hicolor-icon-theme/hicolor-icon-theme_0.17-2_all.deb","sha256":"20304d34b85a734ec1e4830badf3a3a70a5dc5f9c1afc0b2230ecd760c81b5e0"},
    {"archive":"scout-runtime-022.deb","url":"https://deb.debian.org/debian/pool/main/i/iptables/libip4tc2_1.8.9-2_amd64.deb","sha256":"f2c48b367f9ec13f9aa577e7ccf81b371ce5d5fe22dddf9d7aa99f1e0bb7cfc4"},
    {"archive":"scout-runtime-023.deb","url":"https://deb.debian.org/debian/pool/main/j/jbigkit/libjbig0_2.1-6.1_amd64.deb","sha256":"6b07c77b700a615642888a82ba92a7e7c429d04b9c8669c62b2263f15c4c4059"},
    {"archive":"scout-runtime-024.deb","url":"https://deb.debian.org/debian/pool/main/j/json-c/libjson-c5_0.16-2_amd64.deb","sha256":"d0e1ed8637d1c26b9720f6057d6355f18378bba5cc2553e459d1632783c00d70"},
    {"archive":"scout-runtime-025.deb","url":"https://deb.debian.org/debian/pool/main/k/kmod/libkmod2_30%2b20221128-1_amd64.deb","sha256":"af63bbbfc15fbd1f254b15c393b3b95b18b18cc81348fc1b4f1c9c34b4d672d7"},
    {"archive":"scout-runtime-026.deb","url":"https://deb.debian.org/debian/pool/main/l/lcms2/liblcms2-2_2.14-2%2bdeb12u1_amd64.deb","sha256":"333efe13d165b8a98194d95e72fd10b502ebbee4dc2eb43fc2ab83e2b53e5f17"},
    {"archive":"scout-runtime-027.deb","url":"https://deb.debian.org/debian/pool/main/l/lerc/liblerc4_4.0.0%2bds-2_amd64.deb","sha256":"771f5c47ca69f24ca61e4be0c98c5912b182ce442f921697d17a472f3ded5c9c"},
    {"archive":"scout-runtime-028.deb","url":"https://deb.debian.org/debian/pool/main/libd/libdeflate/libdeflate0_1.14-1_amd64.deb","sha256":"3d4b39f94317b64a860db8a7a8b581b555124cd461fe07ec0d347edbdb9f6683"},
    {"archive":"scout-runtime-029.deb","url":"https://deb.debian.org/debian/pool/main/libe/libepoxy/libepoxy0_1.5.10-1_amd64.deb","sha256":"050cbedc9c2a5cce976151c720a3817f2103a01e6ac255bdd6f2c6a7509b04c3"},
    {"archive":"scout-runtime-030.deb","url":"https://deb.debian.org/debian/pool/main/libj/libjpeg-turbo/libjpeg62-turbo_2.1.5-2_amd64.deb","sha256":"95ec30140789a342add8f8371ed018924de51b539056522b66f207b25cba9cad"},
    {"archive":"scout-runtime-031.deb","url":"https://deb.debian.org/debian/pool/main/libp/libpsl/libpsl5_0.21.2-1_amd64.deb","sha256":"4f0d35610204e4e754b057748719744114621f2f6f4202d846c314860a981afb"},
    {"archive":"scout-runtime-032.deb","url":"https://deb.debian.org/debian/pool/main/libw/libwebp/libwebp7_1.2.4-0.2%2bdeb12u1_amd64.deb","sha256":"7259b7ce46444694ce536360ad53acb68eb3b47a7ff81d7b1b8a3939b2ac9918"},
    {"archive":"scout-runtime-033.deb","url":"https://deb.debian.org/debian/pool/main/libx/libxcursor/libxcursor1_1.2.1-1_amd64.deb","sha256":"49e167048661be4c614fff81429e9eaef38e54ef1d2150a5d2a8c53919217529"},
    {"archive":"scout-runtime-034.deb","url":"https://deb.debian.org/debian/pool/main/libx/libxinerama/libxinerama1_1.1.4-3_amd64.deb","sha256":"8dde8f74d2fc001f306fb1295a86850145e93191d35c983c7f52eb21b0a7f8cb"},
    {"archive":"scout-runtime-035.deb","url":"https://deb.debian.org/debian/pool/main/l/lvm2/dmsetup_1.02.185-2_amd64.deb","sha256":"c73fc490b93c83550ed272de69ec96c5da30d4456b889f9e93c7fd8e53860b85"},
    {"archive":"scout-runtime-036.deb","url":"https://deb.debian.org/debian/pool/main/l/lvm2/libdevmapper1.02.1_1.02.185-2_amd64.deb","sha256":"aaa78ca236055fedccf637eacf7bda02bf1980b2db668dccd202b04d0d2cfe04"},
    {"archive":"scout-runtime-037.deb","url":"https://deb.debian.org/debian/pool/main/n/ncurses/libncursesw6_6.4-4_amd64.deb","sha256":"98fa7a53dc565a38b65fb70422ad08001bf5361d8fbc74255280c329996a6bec"},
    {"archive":"scout-runtime-038.deb","url":"https://deb.debian.org/debian/pool/main/n/nghttp2/libnghttp2-14_1.52.0-1%2bdeb12u3_amd64.deb","sha256":"5a5736cee57e51c1baed869979e6ecdbc6495e939e33203d6cfe3b6e5a149e3f"},
    {"archive":"scout-runtime-039.deb","url":"https://deb.debian.org/debian/pool/main/o/openldap/libldap-2.5-0_2.5.13%2bdfsg-5_amd64.deb","sha256":"4b6c30f6554149c594628d945edc6003f0eea8d0cc1341638c0e71375db147ed"},
    {"archive":"scout-runtime-040.deb","url":"https://deb.debian.org/debian/pool/main/p/pango1.0/libpangocairo-1.0-0_1.50.12%2bds-1_amd64.deb","sha256":"96695f9cdd3bf346e3555cf0aa158e23a36114d6dec203b00ab4e93f1b77aab9"},
    {"archive":"scout-runtime-041.deb","url":"https://deb.debian.org/debian/pool/main/p/pango1.0/libpangoft2-1.0-0_1.50.12%2bds-1_amd64.deb","sha256":"78da3f494109f6e7a39c4626aaae7571c600c5854cecda0bc0c902224986a63b"},
    {"archive":"scout-runtime-042.deb","url":"https://deb.debian.org/debian/pool/main/p/procps/libproc2-0_4.0.2-3_amd64.deb","sha256":"e82ba5d01929eafb8b9954606a3c38b0332a987c2b3432388b4ee7365e54deae"},
    {"archive":"scout-runtime-043.deb","url":"https://deb.debian.org/debian/pool/main/p/procps/procps_4.0.2-3_amd64.deb","sha256":"d9d0e75779cb79af869181f17b93c5c263a2b89cac6a0193c436160a4483ddc1"},
    {"archive":"scout-runtime-044.deb","url":"https://deb.debian.org/debian/pool/main/r/rtmpdump/librtmp1_2.4%2b20151223.gitfa8646d.1-2%2bb2_amd64.deb","sha256":"e1f69020dc2c466e421ec6a58406b643be8b5c382abf0f8989011c1d3df91c87"},
    {"archive":"scout-runtime-045.deb","url":"https://deb.debian.org/debian/pool/main/s/shared-mime-info/shared-mime-info_2.2-1_amd64.deb","sha256":"dd026add873483566faefebbd8779a1e5e14ab2e44682ebfe238c3828a2b936b"},
    {"archive":"scout-runtime-046.deb","url":"https://deb.debian.org/debian/pool/main/s/systemd/libpam-systemd_252.39-1%7edeb12u2_amd64.deb","sha256":"5629028998971da269a165cdbeb1c7606e9c37e58030217ae93f55233388be32"},
    {"archive":"scout-runtime-047.deb","url":"https://deb.debian.org/debian/pool/main/s/systemd/libsystemd-shared_252.39-1%7edeb12u2_amd64.deb","sha256":"01458465c816b9eb63b92241869ddb46f332b8f498cf7a5979b84ec293cfdfda"},
    {"archive":"scout-runtime-048.deb","url":"https://deb.debian.org/debian/pool/main/s/systemd/systemd_252.39-1%7edeb12u2_amd64.deb","sha256":"286f879c537bfba92e59d580c075ad20ab49020244c79634656850a306dd462b"},
    {"archive":"scout-runtime-049.deb","url":"https://deb.debian.org/debian/pool/main/s/systemd/systemd-sysv_252.39-1%7edeb12u2_amd64.deb","sha256":"e3dc84316cfdf7e3feefe4eaf507758d2630ea131e1834e1f07525b3e537db2d"},
    {"archive":"scout-runtime-050.deb","url":"https://deb.debian.org/debian/pool/main/t/tiff/libtiff6_4.5.0-6%2bdeb12u4_amd64.deb","sha256":"255cd1d9f204355c366638ee21756234a8d43c03a3de18a5af6cdd94765b5053"},
    {"archive":"scout-runtime-051.deb","url":"https://deb.debian.org/debian/pool/main/u/util-linux/libfdisk1_2.38.1-5%2bdeb12u3_amd64.deb","sha256":"8af145cff6ca72529f63e0bf6d9c68c8512387e67f64e66d00e36f72bed99160"},
    {"archive":"scout-runtime-052.deb","url":"https://deb.debian.org/debian/pool/main/v/vulkan-loader/libvulkan1_1.3.239.0-1_amd64.deb","sha256":"622f28b807ba55a1f5ad1622ff83aa2c5b11fedbec074850e04c10a8f28b43d3"},
    {"archive":"scout-runtime-053.deb","url":"https://deb.debian.org/debian/pool/main/w/wayland/libwayland-client0_1.21.0-1_amd64.deb","sha256":"1f002d028b8b79eec9847c636d8886d10dfe8c884cc2bebe18086b1391c5a28d"},
    {"archive":"scout-runtime-054.deb","url":"https://deb.debian.org/debian/pool/main/w/wayland/libwayland-cursor0_1.21.0-1_amd64.deb","sha256":"0b684467ec795024fcaae99ea4384959cc4052b2da5adec38c9b76dfed9bcf41"},
    {"archive":"scout-runtime-055.deb","url":"https://deb.debian.org/debian/pool/main/w/wayland/libwayland-egl1_1.21.0-1_amd64.deb","sha256":"cb4225f0e15e00a3570d4cbc288c87ff477d73e741c3f1c5a6d47cf350d45378"},
    {"archive":"scout-runtime-056.deb","url":"https://deb.debian.org/debian/pool/main/w/wget/wget_1.21.3-1%2bdeb12u1_amd64.deb","sha256":"b389052d1d8a8cacec4f0380d9ee54e8082bfbebe374299be95b5286c9380f80"},
    {"archive":"scout-runtime-057.deb","url":"https://deb.debian.org/debian/pool/main/x/xdg-utils/xdg-utils_1.1.3-4.1_all.deb","sha256":"0e31caa8c34643f7eedb4d373ee61943c09061275b5fa727524fc568d0a9e332"},
    {"archive":"scout-runtime-058.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/ca-certificates/ca-certificates_20250419%7edeb12u2_all.deb","sha256":"b9f76b5271a7ac373fd5e7e1b5b826a71ddd702b42a0d104955ecb1acfffc94b"},
    {"archive":"scout-runtime-059.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/cyrus-sasl2/libsasl2-2_2.1.28%2bdfsg-10%2bdeb12u1_amd64.deb","sha256":"d6f20408e2be92ebd9f5e3b1c1935b075efb3f03abb5f48f7b991a0ad3e2d6a5"},
    {"archive":"scout-runtime-060.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/cyrus-sasl2/libsasl2-modules-db_2.1.28%2bdfsg-10%2bdeb12u1_amd64.deb","sha256":"6c86ca8fe9a7d652e618874b8753b4b6ec6b42ed7649b3f388e38d0a99047ba5"},
    {"archive":"scout-runtime-061.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/libs/libssh2/libssh2-1_1.10.0-3%2bdeb12u1_amd64.deb","sha256":"fff72a194e493f88e100a2567e22472bb4ab828d429c2956965c6f2f134f1b3a"},
    {"archive":"scout-runtime-062.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/o/openssl/libssl3_3.0.22-1%7edeb12u2_amd64.deb","sha256":"cb4784740daa9b3b0eaea2b444bbefa686794afbbf3d678d238c1fd9875f2efd"},
    {"archive":"scout-runtime-063.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/o/openssl/openssl_3.0.22-1%7edeb12u2_amd64.deb","sha256":"5cdf0b735b1c8a96ae0bf83ed328c83c2170f8320dedb035e98705b60b2d0cfe"},
    {"archive":"scout-runtime-064.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/p/perl/perl-base_5.36.0-7%2bdeb12u4_amd64.deb","sha256":"d7d1943aec9597629bf73075efcc5ef6dc9bda96d78e80d843156ecd448478b8"}
  ]'';
  memberDebian = map (p: p // {
    source = pkgs.fetchurl { inherit (p) url sha256; name = p.archive; };
  }) memberDebianCatalog;
  memberNpmCatalog = builtins.fromJSON ''[
    {"name":"playwright","version":"1.64.1","archive":"playwright-1.64.1.tgz","url":"https://registry.npmjs.org/playwright/-/playwright-1.64.1.tgz","hash":"sha512-HCrVhHr5QQuwYoswEUGTb7gGp522yflbv/ST8nF4sFWGuLjQCt17Q/EubpGGSNKYn1tsTCPZxqHhHCfVURu7UA==","target":"/app/apps/lead-scout/node_modules/playwright"},
    {"name":"playwright-core","version":"1.64.1","archive":"playwright-core-1.64.1.tgz","url":"https://registry.npmjs.org/playwright-core/-/playwright-core-1.64.1.tgz","hash":"sha512-BC4s8y6SEVA6Q1rSxZTto8hI1KUI3xXlHGZgvGqP4IqPdI/a6FX9H29IDNz7vKo9l21b6LfYosScPL6M3xxyDQ==","target":"/app/apps/lead-scout/node_modules/playwright-core"},
    {"name":"shell-quote","version":"1.11.0","archive":"shell-quote-1.11.0.tgz","url":"https://registry.npmjs.org/shell-quote/-/shell-quote-1.11.0.tgz","hash":"sha512-JdxDPD0DBTyu08pq0kPC0xSNet/qsU07qT6IsX1AS8oO2ICNRY4ldNa8OAI6PuwAH8tG3lxEhbqmyp4Dw4036g==","target":"/app/node_modules/shell-quote"},
    {"name":"proxy-addr","version":"2.0.8","archive":"proxy-addr-2.0.8.tgz","url":"https://registry.npmjs.org/proxy-addr/-/proxy-addr-2.0.8.tgz","hash":"sha512-5nnx0yGyVUcY6t9RnWcARWtwT9F1D8O9rt08htPvnd49W1IgZtmLkhu9WfMzQj1cFxjHIO6connUNVW5k7AVyQ==","target":"/app/node_modules/proxy-addr"}
  ]'';
  memberNpm = map (p: p // {
    source = pkgs.fetchurl { inherit (p) url hash; name = p.archive; };
  }) memberNpmCatalog;
  # The original private app-build digest has been retired locally. Retain the
  # exact qualified same-app parent currently serving the member; its Brotli
  # and trust fixes are idempotent below. Replace after upstream qualification.
  memberBaseImage = "localhost/scout-member-runtime@sha256:7ab46330eb8be78fa7870325422e6a5b58e65f8c6a9a73b351fd4d55c5cf4ea4";
  memberSecurityManifest = pkgs.writeText "scout-member-runtime-security.json" (builtins.toJSON {
    schemaVersion = 1;
    baseImage = memberBaseImage;
    chrome = { inherit (memberChrome) version archive url sha256; };
    debian = memberDebianCatalog;
    npm = memberNpmCatalog;
  });
  memberImage = (import ../../../../lib/mkContainer.nix { inherit lib pkgs; }).mkRuntimeImage {
    name = "scout-member";
    version = "51a6a0eb-chrome${memberChrome.version}";
    recipe = ''
      FROM ${memberBaseImage}
      COPY ${memberBrotliFile} /tmp/scout-brotli.deb
      RUN echo '${memberBrotliHash}  /tmp/scout-brotli.deb' | sha256sum -c - && dpkg -i /tmp/scout-brotli.deb && rm /tmp/scout-brotli.deb
      # Chromium policy SHA256: ${builtins.hashString "sha256" memberChromePolicyText}
      COPY chrome-distrust-policy.json /etc/opt/chrome_for_testing/policies/managed/hwc-emsign-distrust.json
      COPY chrome-distrust-policy.json /etc/opt/chrome/policies/managed/hwc-emsign-distrust.json
      COPY debian/ /tmp/scout-runtime/
      COPY ${memberChrome.archive} /tmp/scout-runtime/${memberChrome.archive}
      RUN DEBIAN_FRONTEND=noninteractive apt-get --no-download -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts=- install --no-install-recommends -y /tmp/scout-runtime/*.deb && apt-get clean && rm -rf /tmp/scout-runtime /var/lib/apt/lists/*
      COPY npm/ /tmp/scout-npm/
      ${lib.concatMapStringsSep "\n" (p: ''
        RUN rm -rf ${p.target} && mkdir -p ${p.target} && tar -xzf /tmp/scout-npm/${p.archive} --strip-components=1 -C ${p.target}
      '') memberNpm}
      RUN rm -rf /tmp/scout-npm /ms-playwright/chromium-1223 /ms-playwright/chromium_headless_shell-1223 /ms-playwright/.links
      ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome-stable
      RUN node -e "const fs=require('fs'),p='/app/apps/lead-scout/package.json',d=JSON.parse(fs.readFileSync(p));d.dependencies.playwright=require('playwright/package.json').version;fs.writeFileSync(p,JSON.stringify(d,null,2)+'\\n');"
    '';
  };
  # REPLACEABLE: built from fixed-hash input, public policy and exact recipe.
  # No build or image replacement runs during application startup.
  memberImageContext = pkgs.runCommand "scout-member-runtime-context" {} ''
    mkdir -p "$out/debian" "$out/npm"
    ${lib.concatMapStringsSep "\n" (p: ''cp ${p.source} "$out/debian/${p.archive}"'') memberDebian}
    ${lib.concatMapStringsSep "\n" (p: ''cp ${p.source} "$out/npm/${p.archive}"'') memberNpm}
    cp ${memberChrome.source} "$out/${memberChrome.archive}"
    cp ${memberSecurityManifest} "$out/manifest.json"
    cp ${memberImage.dockerfile} "$out/Dockerfile"
    cp ${memberChromePolicy} "$out/chrome-distrust-policy.json"
    cp ${memberBrotli} "$out/${memberBrotliFile}"
  '';
  invitationMail = member.invitationMail;
  memberUser = config.users.users.${cfg.user};
  # Law4 standard UID1000 applies when Nix delegates allocation. Verify the
  # actual account at the executable boundary before accessing rootless state.
  memberUid = if memberUser.uid == null then 1000 else memberUser.uid;
  memberRuntime = "/run/user/${toString memberUid}";
  memberGraph = "${memberUser.home}/.local/share/containers/storage";
  memberRunroot = "${memberRuntime}/containers";
  memberSnapshotPath = "/var/lib/backups/scout-member/current.dump";
  # The existing /var/lib/backups parent is root-only. Keep same-user bundles
  # beside member state; StateDirectory owns the private child, not its parent.
  memberBundleRoot = "${builtins.dirOf member.directory}/scout-member-browser";
  memberSnapshotUnit = "scout-member-snapshot";
  memberSnapshotConfig = pkgs.writeText "scout-member-snapshot-config.json" (builtins.toJSON {
    user = cfg.user;
    uid = memberUid;
    podman = [
      "${pkgs.podman}/bin/podman"
      "--root" memberGraph "--runroot" memberRunroot
    ];
    pg = [
      "${pkgs.podman}/bin/podman"
      "--root" memberGraph "--runroot" memberRunroot
      "exec" "-i" "${member.projectName}_db_1"
    ];
    app = "${member.projectName}_app_1";
    database = "${member.projectName}_db_1";
    directory = member.directory;
    data = "${member.directory}/data";
    containerData = "/app/apps/lead-scout/data";
    files = member.composeFiles ++ [ ".env" "config.yaml" ];
    health = "http://127.0.0.1:${toString member.port}/api/health";
    destination = memberBundleRoot;
    runtime = "/run/${memberSnapshotUnit}";
    tar = "${pkgs.gnutar}/bin/tar";
    # CRITICAL: current + previous + one pending slot, <=2GiB each.
    # Fail closed at the bound; existing Borg owns encrypted archive retention.
    maxBundleBytes = 2147483648;
    minFreeBytes = 21474836480;
    copySeconds = 9;
  });
  # One implementation for capture and failure cleanup. The wrapper exposes
  # the established SQL core to its existing focused regression check.
  memberSnapshot = pkgs.writeScript "scout-member-snapshot" ''
    #!${pkgs.python3}/bin/python3
    import runpy, sys
    core = runpy.run_path("${./member-snapshot.py}")
    snapshot = core['snapshot']
    if __name__ == '__main__':
        try:
            core['main']("${memberSnapshotConfig}", sys.argv[1:])
        except Exception as error:
            code = error.code if isinstance(error, core['BackupError']) else 'snapshot_failed'
            print('[scout-member-backup] ' + code + '; inspect scout-member-snapshot.service', file=sys.stderr)
            raise SystemExit(1)
  '';
  # REPLACEABLE runtime files, rebuilt from the existing same-user pass store
  # and local Proton Bridge certificate. Stable directory inode for bind mount.
  invitationMailPrepare = pkgs.writeShellScript "lead-scout-invitation-mail-prepare" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.pass pkgs.gnupg pkgs.coreutils ]}:$PATH
    exec ${pkgs.python3}/bin/python3 - <<'PY'
    import os, pathlib, ssl, smtplib, subprocess, time, random
    root = pathlib.Path(os.environ['XDG_RUNTIME_DIR']) / 'lead-scout-invitation-mail'
    root.mkdir(mode=0o700, exist_ok=True)
    root.chmod(0o700)
    # Bootstrap trust only over fixed same-host loopback to the user's Bridge.
    # Scout then requires STARTTLS and validates against this pinned certificate.
    try:
        password = subprocess.check_output(['pass', 'show', ${builtins.toJSON invitationMail.passwordEntry}], timeout=20, stderr=subprocess.DEVNULL).splitlines()[0]
        # Type=simple does not imply SMTP readiness. Total deadline 30s,
        # jittered probes; no mail is submitted by preparation.
        deadline = time.monotonic() + 30
        while True:
            try:
                with smtplib.SMTP('127.0.0.1', 1025, timeout=min(3, max(0.1, deadline-time.monotonic()))) as smtp:
                    smtp.starttls(context=ssl._create_unverified_context())
                    certificate = ssl.DER_cert_to_PEM_cert(smtp.sock.getpeercert(binary_form=True)).encode()
                break
            except (OSError, smtplib.SMTPException):
                if time.monotonic() >= deadline:
                    raise
                time.sleep(min(random.uniform(0.5, 1), max(0, deadline-time.monotonic())))
        for name, content in [('password', password), ('certificate.pem', certificate), ('sender', ${builtins.toJSON invitationMail.from}.encode())]:
            temporary = root / (name + '.tmp')
            fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, 'wb') as output:
                output.write(content)
            os.replace(temporary, root / name)
    except Exception:
        raise SystemExit('[invitation-email] preparation failed; check Proton Bridge and pass access')
    PY
  '';
  memberCompose = "${pkgs.podman-compose}/bin/podman-compose "
    + lib.concatMapStringsSep " " (file: "-f ${lib.escapeShellArg file}") member.composeFiles;
  # Permanent by design: startup consumes a previously qualified local image.
  # Compose still owns runtime settings and the paired backup saves those files.
  memberImageCheck = pkgs.writeShellScript "lead-scout-member-image-check" ''
    set -euo pipefail
    image=$(${memberCompose} config | ${pkgs.yq-go}/bin/yq '.services.app.image // ""' -)
    pull=$(${memberCompose} config | ${pkgs.yq-go}/bin/yq '.services.app.pull_policy // ""' -)
    [ -n "$image" ] && [ "$pull" = never ] \
      || { echo "[lead-scout-member] configure the qualified local image with pull_policy: never" >&2; exit 1; }
    for selected in "$image" ${lib.escapeShellArg memberImage.image}; do
      ${pkgs.podman}/bin/podman image exists "$selected" \
        || { echo "[lead-scout-member] build and qualify the local runtime image before starting" >&2; exit 1; }
    done
    expected=$(${pkgs.podman}/bin/podman image inspect -f '{{.Id}}' ${lib.escapeShellArg memberImage.image})
    selected=$(${pkgs.podman}/bin/podman image inspect -f '{{.Id}}' "$image")
    [ "$selected" = "$expected" ] \
      || { echo "[lead-scout-member] compose image differs from the qualified local image" >&2; exit 1; }
    name="''${COMPOSE_PROJECT_NAME:?}_app_1"
    if ${pkgs.podman}/bin/podman container exists "$name"; then
      actual=$(${pkgs.podman}/bin/podman inspect -f '{{.Image}}' "$name")
      [ "$actual" = "$expected" ] \
        || { echo "[lead-scout-member] existing app image differs; use the qualified release procedure" >&2; exit 1; }
    fi
  '';
  # Inputs must exist and podman must be rootless before anything starts.
  # Resolve only the recovery fields; never print the full compose config.
  memberPreflight = pkgs.writeShellScript "lead-scout-member-preflight" ''
    set -euo pipefail
    for file in ${lib.escapeShellArgs (member.composeFiles ++ [ ".env" "config.yaml" ])}; do
      [ -f "${member.directory}/$file" ] || { echo "[lead-scout-member] missing $file" >&2; exit 1; }
    done
    [ "$(${pkgs.podman}/bin/podman info --format '{{.Host.Security.Rootless}}')" = true ] \
      || { echo "[lead-scout-member] podman is not rootless for this user" >&2; exit 1; }
    # Compose owns these facts. Never print its resolved config (it can contain
    # secrets); project only the recovery fields through yq.
    for service in app db; do
      policy=$(${memberCompose} config | SERVICE="$service" ${pkgs.yq-go}/bin/yq '.services[strenv(SERVICE)].restart // "no"' -)
      [ "$policy" = no ] || { echo "[lead-scout-member] $service restart policy must be no" >&2; exit 1; }
      name="''${COMPOSE_PROJECT_NAME}_''${service}_1"
      if ${pkgs.podman}/bin/podman container exists "$name"; then
        policy=$(${pkgs.podman}/bin/podman inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$name")
        [ "$policy" = no ] || { echo "[lead-scout-member] live $service has another restart authority" >&2; exit 1; }
      fi
    done
    ${memberImageCheck}
    configured=$(${pkgs.yq-go}/bin/yq '.server.trusted_proxies // [] | .[]' config.yaml)
    if [ -n "$configured" ]; then
      declared=$(${memberCompose} config | ${pkgs.yq-go}/bin/yq '.services.app.networks[] | .ipv4_address // ""' -)
      subnet=$(${memberCompose} config | ${pkgs.yq-go}/bin/yq '.networks[].ipam.config[].subnet // ""' -)
      [ -n "$subnet" ] && [ "$configured" = "$declared" ] \
        || { echo "[lead-scout-member] exact trust requires the compose static app address and subnet" >&2; exit 1; }
    fi
  '';
  # StopPost alone owns the drain, including failed starts. No down/recreate.
  memberStopSteps = pkgs.writeShellScript "lead-scout-member-stop-steps" ''
    set -uo pipefail
    status=0
    ${memberCompose} stop -t 15 app || status=$?
    ${memberCompose} stop -t 30 db || status=$?
    exit "$status"
  '';
  # Bounded: 30 attempts, 5 s each, 2.000-2.999 s jittered gaps (~4.5 min
  # worst case, inside TimeoutStartSec). A miss fails the unit; no retry.
  memberHealth = pkgs.writeShellScript "lead-scout-member-health" ''
    for attempt in $(${pkgs.coreutils}/bin/seq 1 30); do
      ${pkgs.curl}/bin/curl -fsS -o /dev/null --max-time 5 \
        http://127.0.0.1:${toString member.port}/api/health && exit 0
      ${pkgs.coreutils}/bin/sleep "$(printf '2.%03d' $((RANDOM % 1000)))"
    done
    echo "[lead-scout-member] /api/health not reached after 30 attempts" >&2
    exit 1
  '';
  # Rootless publishing makes every client's socket peer the app's own
  # address (measured 10.89.2.4), so trust is sound only as that one exact
  # address. Empty trusted_proxies (trust off) passes. Anything else must equal
  # the live app address, or the unit fails and says why. Reads that one key.
  memberTrustCheck = pkgs.writeShellScript "lead-scout-member-trust-check" ''
    set -euo pipefail
    configured=$(${pkgs.yq-go}/bin/yq '.server.trusted_proxies // [] | .[]' config.yaml)
    if [ -z "$configured" ]; then
      echo "[lead-scout-member] trusted_proxies empty: forwarded client addresses ignored"
      exit 0
    fi
    ids=$(${pkgs.podman}/bin/podman ps -q \
      --filter "label=io.podman.compose.project=$COMPOSE_PROJECT_NAME" \
      --filter label=com.docker.compose.service=app)
    if [ -z "$ids" ] || [ "$(echo "$ids" | ${pkgs.coreutils}/bin/wc -l)" -ne 1 ]; then
      echo "[lead-scout-member] expected exactly one running app container" >&2
      exit 1
    fi
    live=$(${pkgs.podman}/bin/podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$ids" | ${pkgs.findutils}/bin/xargs)
    if [ "$configured" != "$live" ]; then
      echo "[lead-scout-member] trusted_proxies ($configured) is not the app address ($live); refusing" >&2
      exit 1
    fi
  '';

  memberPrepareSteps = pkgs.writeShellScript "lead-scout-member-prepare-steps" ''
    set -euo pipefail
    ${restartJitter}
    ${memberPreflight}
    # Start the retained DB before compose creates a missing replacement app.
    # Otherwise that app can claim the stopped DB's previous IPAM allocation.
    # Permanent by design: one supervisor still owns both container starts.
    ${memberCompose} up -d --no-build --no-recreate db
    ${memberCompose} up -d --no-build --no-recreate
    ${memberHealth}
    ${memberTrustCheck}
  '';
  # One elapsed deadline around the entire sequence, not a fresh timeout per
  # systemd command. The unit passes the budget; scaled tests run this same
  # helper. KILL cancels the helper group without another grace period.
  boundedMemberPhase = name: steps: pkgs.writeShellScript name ''
    set -euo pipefail
    [ "$#" -eq 1 ] && [[ "$1" =~ ^[1-9][0-9]*$ ]] \
      || { echo "Expected one positive phase budget in seconds" >&2; exit 2; }
    exec ${pkgs.coreutils}/bin/timeout --signal=KILL "$1" ${steps}
  '';
  memberPrepare = boundedMemberPhase "lead-scout-member-prepare" memberPrepareSteps;
  memberStop = boundedMemberPhase "lead-scout-member-stop" memberStopSteps;

  chromiumBin = "${pkgs.chromium}/bin/chromium";

  # Model bridge (options.modelBridge). The token never appears in the unit
  # file: the wrapper reads the agenix mount at start and passes it as an
  # argument to the bridge process, which runs as cfg.user like the server.
  bridge = cfg.modelBridge;
  bridgeScript = "${cfg.projectDir}/bridge/lead-scout-model-bridge.mjs";
  bridgeTokenFile = "/run/agenix/${toString bridge.tokenSecret}";
  bridgeStart = pkgs.writeShellScript "lead-scout-model-bridge-start" ''
    set -eu
    exec ${node} ${bridgeScript} \
      --backend ${bridge.backend} --host ${bridge.host} --port ${toString bridge.port} \
      --model ${lib.escapeShellArg bridge.model} \
      --max-in-flight ${toString bridge.maxInFlight} --max-queue ${toString bridge.maxQueue} \
      ${lib.optionalString (bridge.tokenSecret != null) ''--token "$(cat ${bridgeTokenFile})"''}
  '';
  modelBridgeService = lib.optionalAttrs bridge.enable {
    lead-scout-model-bridge = {
      description = "Lead Scout model bridge (claude/codex/pi -> OpenAI-compatible)";
      after = [
        "network-online.target"
        "tailscaled.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # The bridge resolves the backend binary on PATH only; the per-user
      # profile is where `claude` lives on this host (same binary the server
      # unit pins via CLAUDE_BIN).
      path = [
        pkgs.nodejs
        "/etc/profiles/per-user/${cfg.user}"
      ];
      environment = {
        NODE_ENV = "production";
        # Same reason as the server unit: ProtectHome makes ~/.config read-only.
        XDG_CONFIG_HOME = "${cfg.projectDir}/data/xdg-config";
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = bridgeStart;
        WorkingDirectory = cfg.projectDir;
        User = cfg.user;
        SupplementaryGroups = [ "secrets" ];
        # A non-loopback bind fails until the address exists (tailnet up);
        # on-failure restarts cover boot ordering.
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "30s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        ReadWritePaths = [
          "${cfg.projectDir}/data"
          "/tmp"
        ];
      };
    };
  };

  enabledApprovalBots = lib.filterAttrs (_: bot: bot.enable) cfg.discordApprovalBots;
  # Only bots whose Gateway this module owns get an approval unit here. A bot
  # delegated to the HWC control bot (gateway = "hwc-control-bot") still gets
  # its card-delivery route below — delivery is REST, not Gateway — but its
  # buttons and modals are consumed by domains/server/native/ai/hwc-control-bot,
  # so rendering a second Gateway client for the same token is refused.
  gatewayOwnedBots = lib.filterAttrs (_: bot: bot.gateway == "lead-scout") enabledApprovalBots;
  delegatedBots = lib.filterAttrs (_: bot: bot.gateway == "hwc-control-bot") enabledApprovalBots;
  controlTokenFile = "/run/agenix/${toString cfg.controlTokenSecret}";
  approvalBotTokenFile = bot: "/run/agenix/${bot.botTokenSecret}";
  approvalBotUnitName =
    programId:
    if programId == "datax-jtpros" then
      "lead-scout-discord-approvals"
    else
      "lead-scout-discord-approvals-${programId}";

  approvalProfileIds = lib.concatMap (programId: enabledApprovalBots.${programId}.profileIds) (
    builtins.attrNames enabledApprovalBots
  );
  approvalRouteEntries = lib.concatMap (
    programId:
    let
      bot = enabledApprovalBots.${programId};
    in
    map (profileId: {
      name = profileId;
      value = {
        tokenFile = approvalBotTokenFile bot;
        channelId = bot.channelId;
        inherit programId;
      };
    }) bot.profileIds
  ) (builtins.attrNames enabledApprovalBots);
  approvalRoutes = builtins.listToAttrs approvalRouteEntries;

  # Discord is a control plane for explicit human approval, not a dependency
  # of the HTTP/MCP server. The main unit only needs this environment to author
  # review cards; the separate gateway unit owns buttons and modals. Keeping the
  # shared protocol in one attrset prevents sender/consumer configuration drift.
  discordApprovalEnvironment = lib.optionalAttrs (enabledApprovalBots != { }) {
    DISCORD_APPROVAL_BOT_FILE_MAP = builtins.toJSON approvalRoutes;
  };

  # systemd restart delays are deterministic. Add 0–5 seconds at the
  # composition root for both Discord and member recovery. Member jitter is
  # inside its aggregate preparation deadline, not another systemd phase.
  restartJitter = pkgs.writeShellScript "lead-scout-restart-jitter" ''
    exec ${pkgs.coreutils}/bin/sleep "$((RANDOM % 6))"
  '';

  approvalBotServices = lib.mapAttrs' (
    programId: bot:
    lib.nameValuePair (approvalBotUnitName programId) {
      description = "Lead Scout Discord reply approval bot (${programId})";
      after = [
        "network-online.target"
        "postgresql.service"
      ];
      wants = [ "network-online.target" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];

      # Five failed starts in five minutes leave the unit visibly failed. This
      # sheds reconnect churn during a sustained Discord/configuration outage;
      # an operator or the next deployment can restart it explicitly.
      startLimitIntervalSec = 300;
      startLimitBurst = 5;

      environment = {
        DATABASE_URL = cfg.databaseUrl;
        LOG_LEVEL = "info";
        NODE_ENV = "production";
        CLAUDE_MODEL = claudeModel;
        PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = chromiumBin;
        PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
        # Chromium creates its crash database under $XDG_CONFIG_HOME/chromium at
        # startup and aborts (SIGTRAP) when that mkdir fails; ProtectHome makes
        # ~/.config read-only, so the config home lives inside the writable data dir.
        XDG_CONFIG_HOME = "${cfg.projectDir}/data/xdg-config";
        DISCORD_BOT_TOKEN_FILE = approvalBotTokenFile bot;
        DISCORD_APPROVAL_GUILD_ID = bot.guildId;
        DISCORD_APPROVAL_CHANNEL_ID = bot.channelId;
        DISCORD_APPROVAL_ALLOWED_USER_ID = bot.allowedUserId;
        REPLY_REVIEW_PROGRAM_ID = programId;
      };

      path = [ pkgs.nodejs ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = [
          "${pkgs.coreutils}/bin/test -f ${cli}"
          "${pkgs.coreutils}/bin/test -f ${tsNode.loader}"
          "${pkgs.coreutils}/bin/test -r ${approvalBotTokenFile bot}"
          "${pkgs.coreutils}/bin/test -s ${approvalBotTokenFile bot}"
          restartJitter
        ];
        ExecStart = tsNode.run node cli "discord:approvals";
        WorkingDirectory = cfg.projectDir;
        User = lib.mkForce "eric";
        Group = "users";
        Restart = "on-failure";
        RestartSec = "15s";
        TimeoutStopSec = "30s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;

        ReadWritePaths = [
          "${cfg.projectDir}/data"
          "/tmp"
        ];
      };
    }
  ) gatewayOwnedBots;
  # The old inline `lead-scout-deploy` command (pull + npm install + frontend
  # build + restart) is retired: it predated the standard `deploy` dispatcher
  # and its per-repo layout assumptions are wrong for the scout monorepo.
  # Deploys go through ~/600_apps/scout/deploy.sh (`deploy scout`).
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.server.ai.leadScout = {
    enable = lib.mkEnableOption "Lead Scout MCP server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8420;
      description = "Port the Lead Scout HTTP/MCP server listens on";
    };

    projectDir = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.workspaceRoot}/apps/lead-scout";
      description = "Path to the lead-scout app in the Scout monorepo";
    };

    workspaceRoot = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.paths.user.home}/600_apps/scout";
      description = ''
        Scout monorepo root whose node_modules carries hoisted tooling (tsx).
      '';
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "postgresql://${dbName}@localhost/${dbName}";
      description = "PostgreSQL connection string";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the service as";
    };

    discordWebhookSecret = lib.mkOption {
      type = lib.types.str;
      default = "datax-discord-webhook";
      description = ''
        agenix secret NAME containing the Discord webhook URL used by the
        in-process classifier (src/notifications/discord.ts). Legacy filename
        retained (datax-discord-webhook.age) to avoid re-encryption.
      '';
    };

    channelMap = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        hwc_bozeman_v1 = "discord-webhook-lead-scout";
      };
      description = ''
        Per-profile Discord routing: classifier profile id → agenix secret
        NAME of that profile's webhook. Rendered into the app's
        DISCORD_WEBHOOK_FILE_MAP env (JSON of profileId → secret path);
        profiles not listed fall through to discordWebhookSecret.
      '';
    };

    controlTokenSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "hwc-control-lead-scout-token";
      description = ''
        agenix secret NAME of the bearer token accepted ONLY by the app's
        named /api/control/v1/* routes (the HWC control bot's adapter). It
        authorizes nothing else: not the general API, not review-card
        delivery, not any publisher. null leaves the control API answering
        503 `unavailable` (fail closed).
      '';
    };

    discordApprovalBots = lib.mkOption {
      default = { };
      description = ''
        Profile-scoped Discord approval bots keyed by the application's review
        program id. Each enabled bot gets an isolated Gateway service and token,
        unless its `gateway` delegates the Gateway to the HWC control bot.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "this Discord reply-review bot";
            botTokenSecret = lib.mkOption {
              type = lib.types.str;
              description = "Generated agenix secret name containing only this bot token.";
            };
            guildId = lib.mkOption {
              type = lib.types.str;
              description = "Only this Discord guild may issue review actions.";
            };
            channelId = lib.mkOption {
              type = lib.types.str;
              description = "Discord channel where this program's review cards are sent.";
            };
            allowedUserId = lib.mkOption {
              type = lib.types.str;
              description = "Only this Discord user may act on review cards.";
            };
            profileIds = lib.mkOption {
              type = lib.types.nonEmptyListOf lib.types.str;
              description = "Classifier profiles delivered through this bot.";
            };
            gateway = lib.mkOption {
              type = lib.types.enum [
                "lead-scout"
                "hwc-control-bot"
              ];
              default = "lead-scout";
              description = ''
                Which service consumes this bot's Discord Gateway (buttons and
                modals). `lead-scout` renders a per-program approval unit here;
                `hwc-control-bot` delegates to hwc.server.ai.hwcControlBot, which
                must then be enabled. Card delivery is unaffected either way.
              '';
            };
          };
        }
      );
    };

    modelBridge = {
      enable = lib.mkEnableOption ''
        the Lead Scout model bridge: a host-side OpenAI-compatible endpoint
        (scout apps/lead-scout/bridge/lead-scout-model-bridge.mjs) that forwards
        chat completions to the Claude CLI, Codex or Pi under this user's login,
        so a containerised Lead Scout instance can classify with no API key
      '';
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          Bind address. Anything but loopback requires tokenSecret (the bridge
          refuses to start otherwise). Rootless podman containers cannot reach
          host loopback or host.containers.internal (pasta); bind the tailnet
          address for them.
        '';
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8431;
        description = "Bridge port; Lead Scout's base_url is http://<host>:<port>/v1.";
      };
      backend = lib.mkOption {
        type = lib.types.enum [ "claude" "codex" "pi" ];
        default = "claude";
        description = "Which CLI harness the bridge forwards to.";
      };
      model = lib.mkOption {
        type = lib.types.str;
        default = claudeModel;
        description = "Model name passed to the backend CLI (--model).";
      };
      maxInFlight = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = "Concurrent backend calls; further requests queue.";
      };
      maxQueue = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 8;
        description = "Queued requests beyond which the bridge answers 503.";
      };
      tokenSecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          agenix secret NAME holding the bearer token the bridge requires on
          every request. Lead Scout's config.yaml llm.api_key carries the same
          value. Required when host is not loopback.
        '';
      };
    };

    memberInstance = {
      invitationMail = {
        enable = lib.mkEnableOption "private invitation SMTP relay for the member instance";
        from = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Sender address and SMTP login for the existing Proton Bridge account.";
        };
        passwordEntry = lib.mkOption {
          type = lib.types.str;
          default = "email/proton/bridge";
          description = "Existing pass entry; only its first line is copied into private runtime storage.";
        };
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8430;
        description = ''
          Loopback publish of the rootless member instance. The one producer
          for its vhost upstream and its health proof.
        '';
      };
      vhost.enable = lib.mkEnableOption ''
        the lead-scout-datax vhost to the member instance, with a per-route
        bare-IP X-Forwarded-For (routeOwners assigns the name to work)
      '';
      enable = lib.mkEnableOption ''
        rootless member supervision: detached adoption, health and exact trust
        on each start, then wait for either container to exit. Consecutive
        failed starts terminate at the start limit; stable operation may begin
        a new incident. Disabled until separately accepted for live activation
      '';
      directory = lib.mkOption {
        type = lib.types.path;
        default = "${config.hwc.paths.state}/lead-scout-datax";
        description = "Runtime compose directory (compose files, .env, config.yaml; secrets stay there, never in Nix).";
      };
      composeFiles = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        default = [ "docker-compose.yml" "compose.override.yml" ];
        description = ''
          Compose files, in order, relative to `directory` — the same set the
          deployment uses. Default discovery would drop the override.
        '';
      };
      projectName = lib.mkOption {
        type = lib.types.str;
        description = ''
          Compose project name of the containers already running, read from
          their io.podman.compose.project label. A different name would make
          `up --no-recreate` start a second copy that collides on ports.
        '';
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    #--------------------------------------------------------------------------
    # Database on the shared Postgres instance
    #--------------------------------------------------------------------------
    # Moved here on 2026-08-26 from domains/business/datax/{index,database}.nix,
    # which was deleted. That module's name violated Law 2: after the database
    # rename it owned nothing called datax. home-scout and research-scout each
    # declare their own database inline; lead-scout now does the same.
    #
    # ensureDBOwnership runs `ALTER DATABASE lead_scout OWNER TO lead_scout` on
    # every postgresql start. lead_scout was owned by `postgres` (the other two
    # scout databases are owned by their own role), so this DOES change live
    # state once. Verified safe before writing it: all 18 tables and every
    # sequence in lead_scout.public are ALREADY owned by the lead_scout role,
    # so no object ownership moves and no privilege is withdrawn — `postgres`
    # is a superuser and keeps full access, and `eric` (also superuser, the
    # role hwc.business.crm's read-only ingest connects as) is unaffected.
    # What the role GAINS is schema public's UC via pg_database_owner, which is
    # how home_scout and research_scout get CREATE for their app migrations.
    services.postgresql = {
      ensureDatabases = [ dbName ];
      ensureUsers = [
        {
          name = dbName;
          ensureDBOwnership = true;
        }
      ];
    };

    # NO postStart grant — the `GRANT ${dbName} TO eric` line here was dead
    # (`$PSQL` undefined, `|| true` swallowing it) and unnecessary (trust auth
    # plus a superuser `eric`). Removed 2026-08-28; see
    # domains/data/databases/README.md.

    # The old module's six raw GRANT/ALTER DEFAULT PRIVILEGES statements are
    # deliberately NOT carried over. They were written when the role did not own
    # the objects; it does now, and an owner's privileges are implicit. Checked
    # against the live cluster: the only relacl entries are self-grants
    # (`lead_scout=arwdDxt/lead_scout`), pg_default_acl is empty, and the one
    # substantive grant — CREATE on schema public — is what ensureDBOwnership
    # supplies above. Nothing the app queries depends on them.
    #
    # The old module's `$PSQL -f fb-monitor-bak/schema.sql` is also NOT carried
    # over. That file is the original 2026-05 three-table fb-monitor schema
    # (fb_posts/fb_comments/fb_capture_log, all CREATE TABLE IF NOT EXISTS). The
    # app owns its schema now via ~/600_apps/scout/apps/lead-scout/src/db/
    # migrations and the live `_migrations` table; the database has 18 tables
    # and the file's columns are stale. It is a no-op today and a hazard on a
    # rebuilt cluster, where it would seed a wrong fb_posts ahead of migration 1.

    # NO per-database backup registration, matching home-scout and
    # research-scout.
    #
    # This block was written to KEEP the registration, reasoning that dropping
    # it would silently retire a running backup. That reasoning was correct when
    # written and went stale within the hour: postgresql-db-backup was retired
    # wholesale later the same day (machines/home/config.nix,
    # `backup.perDatabase.enable = false`) because it wrote to
    # /home/eric/backups/postgres, a path in no borg source. A registration into
    # a disabled option is dead config that reads as a backup, so it is removed
    # rather than left to mislead.
    #
    # lead_scout IS backed up, by the mechanism that covers every database: the
    # borg pre-hook's nightly `pg_dumpall` into /var/lib/backups, which borg
    # carries. Verify there — `zcat /var/lib/backups/postgresql-<date>.sql.gz |
    # rg '^CREATE DATABASE'` — not in postgresql-db-backup.

    # Chromium kept on global PATH so interactive `npm run scrape` from a user
    # shell can find it; the service itself uses PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH.
    environment.systemPackages = [ pkgs.chromium ];

    # Discord webhook secret (cfg.discordWebhookSecret = "datax-discord-webhook")
    # consumed by the in-process classifier (src/notifications/discord.ts). It is
    # now mounted by the generated secrets layer from
    # parts/services/datax-discord-webhook.age — no inline age.secrets here.

    systemd.services = {
      # No WantedBy/timer: only the existing Borg hook starts this producer.
      # Deadline and cleanup exist before capture begins. Direct User=eric
      # keeps pause children in this unit's cgroup; runuser/PAM is unnecessary.
      scout-member-snapshot = lib.mkIf (member.enable && config.hwc.data.borg.enable) {
        description = "Consistent Scout SQL and browser profile snapshot";
        after = [ "user@${toString memberUid}.service" ];
        environment = {
          XDG_RUNTIME_DIR = memberRuntime;
          DBUS_SESSION_BUS_ADDRESS = "unix:path=${memberRuntime}/bus";
          PATH = lib.mkForce "${lib.makeBinPath [ pkgs.podman pkgs.coreutils pkgs.util-linux ]}:/run/wrappers/bin:/run/current-system/sw/bin";
        };
        serviceConfig = {
          Type = "oneshot";
          User = lib.mkForce "eric";
          Group = "users";
          StateDirectory = lib.removePrefix "/var/lib/" memberBundleRoot;
          StateDirectoryMode = "0700";
          RuntimeDirectory = memberSnapshotUnit;
          RuntimeDirectoryMode = "0700";
          RuntimeDirectoryPreserve = "yes";
          # Each startup phase has its own 15-second deadline. Preparation
          # reads while the app runs; capture retains its original pause bound.
          ExecStartPre = "${memberSnapshot} prepare";
          ExecStart = "${memberSnapshot} bundle";
          ExecStopPost = "${memberSnapshot} thaw";
          TimeoutStartSec = "15s";
          TimeoutStopSec = "5s";
          KillMode = "control-group";
          KillSignal = "SIGKILL";
          # Preparation and capture share this page-cache budget. The 9-second
          # copy and 15+5-second capture/cleanup bounds stay fixed.
          MemoryMax = "2G";
          CPUQuota = "200%";
          TasksMax = 128;
        };
      };
      lead-scout = {
        description = "Lead Scout MCP + HTTP Server";
        after = [
          "network-online.target"
          "postgresql.service"
        ]
        ++ lib.optional config.hwc.business.crm.enable "hwc-crm.service";
        wants = [
          "network-online.target"
        ]
        ++ lib.optional config.hwc.business.crm.enable "hwc-crm.service";
        wantedBy = [ "multi-user.target" ];

        # HWC_PIPELINE marker: the workspace-guard only reports on the headless
        # classifier agent this unit launches (producer: agent-harness sys.nix).
        environment = (config.hwc.system.apps.agent-harness.pipelineEnvironment or { }) // {
          DATABASE_URL = cfg.databaseUrl;
          LOG_LEVEL = "info";
          NODE_ENV = "production";
          # Playwright defaults to its bundled chromium under
          # ~/.cache/ms-playwright, which is a generic-Linux dynamic binary
          # NixOS can't load. Point it at the Nix-built chromium.
          PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = chromiumBin;
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
          # Chromium creates its crash database under $XDG_CONFIG_HOME/chromium at
          # startup and aborts (SIGTRAP) when that mkdir fails; ProtectHome makes
          # ~/.config read-only, so the config home lives inside the writable data
          # dir. Measured 2026-09-26: every scheduled scrape since 2026-09-25 died
          # this way (agent/lead-scout/personal-service-chromium-sigtrap.md).
          XDG_CONFIG_HOME = "${cfg.projectDir}/data/xdg-config";
          DISCORD_WEBHOOK_FILE = config.age.secrets.${cfg.discordWebhookSecret}.path;
        }
        // discordApprovalEnvironment
        // lib.optionalAttrs (cfg.controlTokenSecret != null) {
          # Bearer token for /api/control/v1/* only (src/shells/control-routes.ts);
          # read once at the app's composition root.
          LEAD_SCOUT_CONTROL_TOKEN_FILE = controlTokenFile;
        }
        // lib.optionalAttrs (cfg.channelMap != { }) {
          # Per-profile channel routing (src/notifications/discord.ts
          # resolveWebhookUrl): JSON of profileId → webhook secret path.
          DISCORD_WEBHOOK_FILE_MAP = builtins.toJSON (
            lib.mapAttrs (_: secretName: config.age.secrets.${secretName}.path) cfg.channelMap
          );
        }
        //
          lib.optionalAttrs (config.hwc.business.crm.enable && config.hwc.business.crm.leadscoutIngest.enable)
            {
              # CRM owns handoff eligibility and funnel state. Lead Scout receives
              # the same route contract plus a read-only evidence endpoint; no CRM
              # mutation credential crosses this boundary.
              HWC_CRM_URL = "http://${config.hwc.business.crm.bindAddr}:${toString config.hwc.business.crm.port}";
              HWC_CRM_INGEST_ROUTES = config.hwc.business.crm.leadscoutIngest.routesJson;
            }
        // {

          # The classifier shells out to the `claude` CLI. Upstream lead_scout
          # used to hardcode /etc/profiles/per-user/eric/bin/claude as a fallback;
          # it now late-binds via CLAUDE_BIN → `which claude` → candidate paths.
          # This unit's PATH carries only nodejs (no `claude`), so we MUST declare
          # the binary here or classification silently fails to spawn it.
          CLAUDE_BIN = "/etc/profiles/per-user/eric/bin/claude";
          CLAUDE_MODEL = claudeModel;

          # The server (ExecStart → `serve`) can auto-build the frontend on boot if
          # dist/ is stale, but this unit is hardened (ProtectSystem = "strict";
          # only data/ + /tmp are writable) so a build write to frontend/dist would
          # crash startup. Deploy (lead-scout-deploy) prebuilds the frontend; the
          # service must never try. Hence skip the in-process build entirely.
          SKIP_FRONTEND_BUILD = "1";
        };

        # Needed so detached subprocesses spawned by /api/pipeline tool
        # handlers (mcp/tools.ts) can resolve bare `node` via $PATH.
        path = [ pkgs.nodejs ];

        serviceConfig = {
          Type = "simple";
          ExecStart = tsNode.run node cli "serve --port ${toString cfg.port}";
          WorkingDirectory = cfg.projectDir;
          User = cfg.user;
          Restart = "on-failure";
          RestartSec = "5s";

          # Backstop for the app's own 10s SIGTERM drain; deliberately NOT
          # SuccessExitStatus=143. Rationale in domains/server/README.md
          # (2026-08-15) — it governs all three scouts, so it lives one layer up.
          TimeoutStopSec = "30s";

          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          SystemCallArchitectures = "native";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;

          # Read/write access needed for browser profile and data
          ReadWritePaths = [
            "${cfg.projectDir}/data"
            "/tmp"
          ];
        };
      };
    }
    // approvalBotServices
    // modelBridgeService;

    # Member instance vhost. Per-route override only: mkProxyBlock's default
    # {remote} renders `ip:port`, which Express cannot use as a client address;
    # {remote_host} is the bare IP and replaces any client-supplied value
    # (measured with real Caddy + Express, 2026-09-29). The global default is
    # unchanged because firefly-explorer consumes it.
    hwc.networking.shared.routes = lib.mkIf member.vhost.enable [{
      name = "lead-scout-datax";
      mode = "vhost";
      upstream = "http://127.0.0.1:${toString member.port}";
      headers = {
        "X-Forwarded-For" = "{remote_host}";
        "X-Real-IP" = "{remote_host}";
      };
    }];

    system.build.scoutMemberImageCheck = lib.mkIf member.enable memberImageCheck;
    system.build.scoutMemberRuntimeImageContext = lib.mkIf member.enable memberImageContext;
    system.build.scoutMemberRuntimeSecurityManifest = lib.mkIf member.enable memberSecurityManifest;
    system.build.scoutMemberSnapshot = lib.mkIf member.enable memberSnapshot;
    system.build.scoutMemberSnapshotConfig = lib.mkIf member.enable memberSnapshotConfig;
    # The complete bundle carries logs/WAL inside its tar. Global *.log/raw
    # database exclusions cannot omit those records or archive changing data.
    # Retain the SQL-only artifact as legacy recovery; never delete it here.
    hwc.data.borg = lib.mkIf (member.enable && config.hwc.data.borg.enable) {
      preBackupScript = lib.mkAfter ''
        ${pkgs.systemd}/bin/systemctl start ${memberSnapshotUnit}.service || exit "$?"
      '';
      excludePatterns = [
        "pp:${member.directory}/pgdata"
        "pp:${member.directory}/data"
        "pp:${memberBundleRoot}/pending"
        "pp:${memberBundleRoot}/previous"
        "pf:${memberSnapshotPath}"
      ];
    };

    # Member instance: rootless, so a user unit in eric's manager (linger is on
    # via the server role). Activation remains separate — see memberInstance.enable.
    # --no-recreate leaves running containers untouched and --no-build never
    # builds from the runtime directory, so a start against the live instance
    # preserves container identity. Every retry repeats preparation.
    systemd.user.services.lead-scout-member-instance = lib.mkIf member.enable {
      description = "Lead Scout member instance (rootless compose recovery)";
      wantedBy = [ "default.target" ];
      # No extra network-wait job outside the incident budget. Preparation
      # owns readiness and fails within its elapsed deadline if unavailable.
      unitConfig = {
        ConditionUser = cfg.user;
        StartLimitIntervalSec = 5400;
        StartLimitBurst = 5;
        OnFailure = "hwc-service-failure-notifier@lead-scout-member-instance.service";
      };
      path = [ pkgs.podman pkgs.podman-compose ];
      environment.COMPOSE_PROJECT_NAME = member.projectName;
      serviceConfig = {
        Type = "exec";
        WorkingDirectory = member.directory;
        ExecStartPre = "${memberPrepare} 300";
        # Only the waiter ignores exit status (podman returns1 on TERM).
        # Restart=always still retries every main exit. Never use a service-wide
        # SuccessExitStatus override: that also accepts preparation failures.
        ExecStart = "-${pkgs.podman}/bin/podman wait --condition=stopped --exit-first-match ${member.projectName}_app_1 ${member.projectName}_db_1";
        # App first so its 10 s drain runs while the database is still up.
        ExecStopPost = "${memberStop} 90";
        TimeoutStartSec = 300;
        TimeoutStopSec = 90;
        TimeoutStartFailureMode = "kill";
        TimeoutStopFailureMode = "kill";
        KillSignal = "SIGTERM";
        # Group TERM would signal conmon and stop DB before app. Mixed sends
        # TERM only to the waiter, retaining group KILL for timeout containment.
        KillMode = "mixed";
        Restart = "always";
        RestartSec = 15;
        RestartSteps = 4;
        RestartMaxDelaySec = 240;
      };
    };

    systemd.user.services.lead-scout-invitation-mail-prepare = lib.mkIf invitationMail.enable {
      description = "Prepare private Scout invitation mail credentials";
      after = [ "protonmail-bridge.service" ];
      requires = [ "protonmail-bridge.service" ];
      unitConfig.ConditionUser = cfg.user;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = invitationMailPrepare;
        TimeoutStartSec = 60;
        TimeoutStopSec = 10;
        UMask = "0077";
      };
    };
    systemd.user.sockets.lead-scout-invitation-mail = lib.mkIf invitationMail.enable {
      description = "Private Scout invitation SMTP socket";
      wantedBy = [ "default.target" ];
      requires = [ "lead-scout-invitation-mail-prepare.service" ];
      after = [ "default.target" "lead-scout-invitation-mail-prepare.service" ];
      before = [ "shutdown.target" ];
      conflicts = [ "shutdown.target" ];
      unitConfig = {
        ConditionUser = cfg.user;
        # Proton starts after default.target. Do not order this optional
        # socket before sockets.target/basic.target and create a boot cycle.
        DefaultDependencies = false;
      };
      socketConfig = {
        ListenStream = "%t/lead-scout-invitation-mail/smtp.sock";
        SocketMode = "0600";
        DirectoryMode = "0700";
        RemoveOnStop = true;
      };
    };
    systemd.user.services.lead-scout-invitation-mail = lib.mkIf invitationMail.enable {
      description = "Private Scout invitation SMTP relay";
      requires = [ "lead-scout-invitation-mail.socket" ];
      after = [ "lead-scout-invitation-mail.socket" ];
      unitConfig.ConditionUser = cfg.user;
      serviceConfig = {
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --connections-max=2 --exit-idle-time=30s 127.0.0.1:1025";
        TimeoutStopSec = 20;
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };

    # VALIDATION
    assertions = [
      {
        assertion = !invitationMail.enable || (member.enable && builtins.match "[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+" invitationMail.from != null);
        message = "Scout invitation mail requires the member instance and a sender address.";
      }
      {
        assertion = !member.enable || (config.hwc.monitoring.alerts.enable
          && config.hwc.monitoring.alerts.sources.serviceFailures.enable);
        message = "Member recovery requires the existing user failure notifier.";
      }
      {
        assertion = !member.enable || (let
          unit = config.systemd.user.services.lead-scout-member-instance;
          s = unit.serviceConfig;
          u = unit.unitConfig;
          seconds = command: lib.toInt (lib.last (lib.splitString " " command));
        # Preparation + main activation + waiter termination + cleanup + delay.
        # The manager fields are NOT aggregate lifecycle deadlines. Defaults:
        # 5*(300+300+90+90+240)=5100 <5400. Stable operation starts a new incident.
        in builtins.isString s.ExecStartPre && !(s ? ExecStartPost) && !(s ? ExecStop)
          && u.StartLimitIntervalSec > u.StartLimitBurst * (
            seconds s.ExecStartPre + s.TimeoutStartSec + s.TimeoutStopSec
            + seconds s.ExecStopPost + s.RestartMaxDelaySec));
        message = "Member start window must contain every failed-start startup/cleanup/backoff budget.";
      }
      {
        assertion =
          !cfg.modelBridge.enable
          || cfg.modelBridge.tokenSecret == null
          || builtins.hasAttr cfg.modelBridge.tokenSecret config.age.secrets;
        message = "Lead Scout modelBridge.tokenSecret ${toString cfg.modelBridge.tokenSecret} has no generated agenix mount.";
      }
      {
        assertion =
          !cfg.modelBridge.enable
          || cfg.modelBridge.tokenSecret != null
          || lib.hasPrefix "127." cfg.modelBridge.host
          || cfg.modelBridge.host == "localhost"
          || cfg.modelBridge.host == "::1";
        message = "Lead Scout modelBridge binds ${cfg.modelBridge.host} without a tokenSecret; the bridge refuses non-loopback binds without a token.";
      }
      {
        assertion = builtins.length approvalProfileIds == builtins.length (lib.unique approvalProfileIds);
        message = "Lead Scout Discord approval profileIds must be owned by exactly one bot.";
      }
      {
        assertion =
          delegatedBots == { }
          || (config.hwc.server.ai ? hwcControlBot && config.hwc.server.ai.hwcControlBot.enable);
        message = "Lead Scout bot(s) ${lib.concatStringsSep ", " (builtins.attrNames delegatedBots)} delegate their Gateway to hwc-control-bot, which is not enabled — their buttons would have no consumer.";
      }
      {
        assertion =
          cfg.controlTokenSecret == null || builtins.hasAttr cfg.controlTokenSecret config.age.secrets;
        message = "Lead Scout controlTokenSecret ${toString cfg.controlTokenSecret} has no generated agenix mount.";
      }
    ]
    ++ lib.concatLists (
      lib.mapAttrsToList (programId: bot: [
        {
          assertion = builtins.hasAttr bot.botTokenSecret config.age.secrets;
          message = "Lead Scout Discord bot ${programId} has no generated agenix token mount.";
        }
        {
          assertion = bot.guildId != "" && bot.channelId != "" && bot.allowedUserId != "";
          message = "Lead Scout Discord bot ${programId} requires guildId, channelId, and allowedUserId.";
        }
      ]) enabledApprovalBots
    );
  };
}
