{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.business.paperless;
  paths = config.hwc.paths;
  # Temporary browser patch: retire when a qualified vendor image includes
  # Chromium >=156.0.8078.79 and passes the Paperless conversion contracts.
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  gotenbergPackages = builtins.fromJSON ''
    [{"name":"chromium-common","version":"156.0.8078.79-1~deb13u1","file":"chromium-common_156.0.8078.79-1~deb13u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/chromium/chromium-common_156.0.8078.79-1~deb13u1_amd64.deb","hash":"sha256-KdmjMSO8xaukd0briactlzv3pzfjggQlx0lpBPcjX70="},{"name":"chromium","version":"156.0.8078.79-1~deb13u1","file":"chromium_156.0.8078.79-1~deb13u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/chromium/chromium_156.0.8078.79-1~deb13u1_amd64.deb","hash":"sha256-kyV3f7hC6vo/mSIJ7m8babrXbDMRqI79TXdyzsIuN5U="},{"name":"libnss3","version":"2:3.110-1+deb13u5","file":"libnss3_2%3a3.110-1+deb13u5_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/n/nss/libnss3_3.110-1+deb13u5_amd64.deb","hash":"sha256-cFmDkWXDnnNP9ZxxL96D716gEyiHKBnfur0cCOdfMRY="},{"name":"tzdata","version":"2026f-0+deb13u1","file":"tzdata_2026f-0+deb13u1_all.deb","url":"https://deb.debian.org/debian/pool/main/t/tzdata/tzdata_2026f-0+deb13u1_all.deb","hash":"sha256-LBxWEJFAKINDDQ1HxXo8CqALRK/IpiOSZQZahyEaXBE="}]
  '';
  gotenbergRuntime = helpers.mkRuntimeImage {
    name = "paperless-gotenberg";
    version = "8.39.0-chromium156.0.8078.79";
    recipe = ''
      FROM docker.io/gotenberg/gotenberg@sha256:5a9c6b8e5e65c35236f99ff1b55f16a3bbc2fb6d9518292a7c15ca433d5bab24
      # Fixed APT inputs ${builtins.hashString "sha256" (builtins.toJSON gotenbergPackages)}
      USER root
      COPY debian/ /tmp/hwc-gotenberg-debs/
      RUN DEBIAN_FRONTEND=noninteractive apt-get --no-download --yes -o Dir::Cache::archives=/tmp/hwc-gotenberg-debs -o Dpkg::Options::=--force-confold install /tmp/hwc-gotenberg-debs/*.deb && test -z "$(dpkg --audit)" && rm -r /tmp/hwc-gotenberg-debs
      USER gotenberg
    '';
  };
  gotenbergManifest = pkgs.writeText "gotenberg-runtime-packages.json" (builtins.toJSON gotenbergPackages);
  gotenbergContext = pkgs.runCommand "gotenberg-runtime-context" {} ''
    mkdir -p "$out/debian"
    cp ${gotenbergRuntime.dockerfile} "$out/Dockerfile"
    cp ${gotenbergManifest} "$out/manifest.json"
    ${lib.concatMapStrings (p: let source = pkgs.fetchurl { inherit (p) url hash; }; in ''
      cp ${source} "$out/debian/${p.file}"
    '') gotenbergPackages}
  '';
  # Temporary same-app repair. Remove when a qualified vendor image includes
  # Python >=3.14.10, these fixed wheels, the current Debian security packages,
  # and passes the actual Office/mail/OCR and PostgreSQL recovery contracts.
  paperlessDebs = builtins.fromJSON ''
    [
      {"name":"base-files","version":"13.8+deb13u7","file":"base-files_13.8+deb13u7_amd64.deb","url":"https://deb.debian.org/debian/pool/main/b/base-files/base-files_13.8%2bdeb13u7_amd64.deb","hash":"sha256-/NQrtctj97/EMmqSVBJHhyIG1goZL9/2XKFOuD7UCLk="},
      {"name":"bash","version":"5.2.37-2+b10","file":"bash_5.2.37-2+b10_amd64.deb","url":"https://deb.debian.org/debian/pool/main/b/bash/bash_5.2.37-2%2bb10_amd64.deb","hash":"sha256-L9ewTxt8qinE5oP1IW5q81SkHjzc9udTlNfNpoD5q4I="},
      {"name":"bsdutils","version":"1:2.41.5-0+deb13u1","file":"bsdutils_1%3a2.41.5-0+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/u/util-linux/bsdutils_2.41.5-0%2bdeb13u1_amd64.deb","hash":"sha256-2TWlECdSoRCL3x6BXImoSsiNGUm/BJp4QXj5RqCbFNo="},
      {"name":"ca-certificates","version":"20250419+deb13u1","file":"ca-certificates_20250419+deb13u1_all.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/ca-certificates/ca-certificates_20250419%2bdeb13u1_all.deb","hash":"sha256-wQWFrCLH9henPTlO6im6cdA1bzUK6XOxkEPRsBf4D1Q="},
      {"name":"curl","version":"8.14.1-2+deb13u7","file":"curl_8.14.1-2+deb13u7_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/curl/curl_8.14.1-2%2bdeb13u7_amd64.deb","hash":"sha256-E1Y2vYtxPFgtM+UOxONupVzDxdo/Ervra4fSvL06Bkk="},
      {"name":"dirmngr","version":"2.4.7-21+deb13u1+b5","file":"dirmngr_2.4.7-21+deb13u1+b5_amd64.deb","url":"https://deb.debian.org/debian/pool/main/g/gnupg2/dirmngr_2.4.7-21%2bdeb13u1%2bb5_amd64.deb","hash":"sha256-OFtGifQ2eNvQl62gAuwZczF5d3rCpsAimuKSyuF/CDM="},
      {"name":"ghostscript","version":"10.05.1~dfsg-1+deb13u3","file":"ghostscript_10.05.1~dfsg-1+deb13u3_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/g/ghostscript/ghostscript_10.05.1%7edfsg-1%2bdeb13u3_amd64.deb","hash":"sha256-i6y0/BpAm5n7jztBgjJAaJeeNziGOfOu4D64ueb04lI="},
      {"name":"gpg-agent","version":"2.4.7-21+deb13u1+b5","file":"gpg-agent_2.4.7-21+deb13u1+b5_amd64.deb","url":"https://deb.debian.org/debian/pool/main/g/gnupg2/gpg-agent_2.4.7-21%2bdeb13u1%2bb5_amd64.deb","hash":"sha256-68RAwF3Vxbo18LADXXZThmzibEfIJv+7WjRAdz8o2gM="},
      {"name":"gpg","version":"2.4.7-21+deb13u1+b5","file":"gpg_2.4.7-21+deb13u1+b5_amd64.deb","url":"https://deb.debian.org/debian/pool/main/g/gnupg2/gpg_2.4.7-21%2bdeb13u1%2bb5_amd64.deb","hash":"sha256-Ou7fPSI+Xmr/CPAyJ69s4wj0MXRyYJ84M1D9LsINM64="},
      {"name":"gpgconf","version":"2.4.7-21+deb13u1+b5","file":"gpgconf_2.4.7-21+deb13u1+b5_amd64.deb","url":"https://deb.debian.org/debian/pool/main/g/gnupg2/gpgconf_2.4.7-21%2bdeb13u1%2bb5_amd64.deb","hash":"sha256-FGaPP0hH0lRL3/A8LKjb3S/grRvH3tAJQdspGVTGDxs="},
      {"name":"gpgsm","version":"2.4.7-21+deb13u1+b5","file":"gpgsm_2.4.7-21+deb13u1+b5_amd64.deb","url":"https://deb.debian.org/debian/pool/main/g/gnupg2/gpgsm_2.4.7-21%2bdeb13u1%2bb5_amd64.deb","hash":"sha256-CS9GdaGBDKe1Gh1TWV+eDDq2UhDBWAV0npEDB2niMBs="},
      {"name":"gzip","version":"1.13-1+deb13u1","file":"gzip_1.13-1+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/g/gzip/gzip_1.13-1%2bdeb13u1_amd64.deb","hash":"sha256-dM8SISvu5KuNRzvcAQer+ejO9zdJIZji9JRKGfFCsKw="},
      {"name":"imagemagick-7-common","version":"8:7.1.1.43+dfsg1-1+deb13u13","file":"imagemagick-7-common_8%3a7.1.1.43+dfsg1-1+deb13u13_all.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/i/imagemagick/imagemagick-7-common_7.1.1.43%2bdfsg1-1%2bdeb13u13_all.deb","hash":"sha256-rKtOCjTerdUPB6oWbEl7HByLls6HIQfWZn6oA68+LXo="},
      {"name":"imagemagick-7.q16","version":"8:7.1.1.43+dfsg1-1+deb13u13","file":"imagemagick-7.q16_8%3a7.1.1.43+dfsg1-1+deb13u13_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/i/imagemagick/imagemagick-7.q16_7.1.1.43%2bdfsg1-1%2bdeb13u13_amd64.deb","hash":"sha256-SP0uYK7HIpltkSQELK0R2jZz5ulug2IjKXoZI8i6NfU="},
      {"name":"imagemagick","version":"8:7.1.1.43+dfsg1-1+deb13u13","file":"imagemagick_8%3a7.1.1.43+dfsg1-1+deb13u13_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/i/imagemagick/imagemagick_7.1.1.43%2bdfsg1-1%2bdeb13u13_amd64.deb","hash":"sha256-B7n3LYSjn0FLunreMug9YppjOJuf8QNIH/91r9gSyQY="},
      {"name":"jbig2dec","version":"0.20-1+deb13u1","file":"jbig2dec_0.20-1+deb13u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/j/jbig2dec/jbig2dec_0.20-1%2bdeb13u1_amd64.deb","hash":"sha256-m400AC4CTEDbd1bRV6SX5ZYM39uXyk/piJ8wVhpxkyU="},
      {"name":"libaudit-common","version":"1:4.0.2-2+deb13u1","file":"libaudit-common_1%3a4.0.2-2+deb13u1_all.deb","url":"https://deb.debian.org/debian/pool/main/a/audit/libaudit-common_4.0.2-2%2bdeb13u1_all.deb","hash":"sha256-udMuX/BP10eqy31rPru79zTd77LxaV8LGypLXlGxBS4="},
      {"name":"libaudit1","version":"1:4.0.2-2+deb13u1","file":"libaudit1_1%3a4.0.2-2+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/a/audit/libaudit1_4.0.2-2%2bdeb13u1_amd64.deb","hash":"sha256-PR3T8DGlbwG3R+KswOFFdSElgOb6Y9gAxEywox8e39c="},
      {"name":"libblkid1","version":"2.41.5-0+deb13u1","file":"libblkid1_2.41.5-0+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/u/util-linux/libblkid1_2.41.5-0%2bdeb13u1_amd64.deb","hash":"sha256-gVNfPCwO/HMpZZB8h0kQOgomN3x2FiLJzjm0yS3N5S8="},
      {"name":"libbrotli1","version":"1.1.0-2+deb13u1","file":"libbrotli1_1.1.0-2+deb13u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/b/brotli/libbrotli1_1.1.0-2%2bdeb13u1_amd64.deb","hash":"sha256-20aCTGD+5Gr/PMC+Pl9za8YGyuZpsfsXUWpB6AcyUak="},
      {"name":"libc-bin","version":"2.41-12+deb13u4","file":"libc-bin_2.41-12+deb13u4_amd64.deb","url":"https://deb.debian.org/debian/pool/main/g/glibc/libc-bin_2.41-12%2bdeb13u4_amd64.deb","hash":"sha256-3Ix5ZH/jpfN/cqQAQU9wJj0CEvAQ/ywJ+ZDjDZHjjRw="},
      {"name":"libc6","version":"2.41-12+deb13u4","file":"libc6_2.41-12+deb13u4_amd64.deb","url":"https://deb.debian.org/debian/pool/main/g/glibc/libc6_2.41-12%2bdeb13u4_amd64.deb","hash":"sha256-lnqmJgVyEIHD6yoXZQYRp5KqgC12plEdGEAkJiPSBMk="},
      {"name":"libcap2","version":"1:2.75-10+deb13u1+b3","file":"libcap2_1%3a2.75-10+deb13u1+b3_amd64.deb","url":"https://deb.debian.org/debian/pool/main/libc/libcap2/libcap2_2.75-10%2bdeb13u1%2bb3_amd64.deb","hash":"sha256-ifxNNPx6KK1vD80MVhqyU7ne32939aAAtHwnbIKVv2c="},
      {"name":"libcom-err2","version":"1.47.2-3+b12","file":"libcom-err2_1.47.2-3+b12_amd64.deb","url":"https://deb.debian.org/debian/pool/main/e/e2fsprogs/libcom-err2_1.47.2-3%2bb12_amd64.deb","hash":"sha256-vUPgILj+05nbPuvwmBEfEPukxDb/+ZzK1yzH4nyXZOw="},
      {"name":"libcurl3t64-gnutls","version":"8.14.1-2+deb13u7","file":"libcurl3t64-gnutls_8.14.1-2+deb13u7_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/curl/libcurl3t64-gnutls_8.14.1-2%2bdeb13u7_amd64.deb","hash":"sha256-lHXFkbM4uBhZ7m0GvyqfuwG1LxhMI1r6f25/FlITblU="},
      {"name":"libcurl4t64","version":"8.14.1-2+deb13u7","file":"libcurl4t64_8.14.1-2+deb13u7_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/curl/libcurl4t64_8.14.1-2%2bdeb13u7_amd64.deb","hash":"sha256-T4m9Pnozu9j3QigXqKjiIzyeGU/anDMeM7+YcF9SW/w="},
      {"name":"libde265-0","version":"1.0.15-1+deb13u2","file":"libde265-0_1.0.15-1+deb13u2_amd64.deb","url":"https://deb.debian.org/debian/pool/main/libd/libde265/libde265-0_1.0.15-1%2bdeb13u2_amd64.deb","hash":"sha256-SnbPD/RQIXbngL/t/ISK7fShpVsdFUsnFkykzmmMGq0="},
      {"name":"libexpat1","version":"2.9.0-1~deb13u1","file":"libexpat1_2.9.0-1~deb13u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/e/expat/libexpat1_2.9.0-1%7edeb13u1_amd64.deb","hash":"sha256-/v+HR3LK6QSuTSTpF7NWZJUr7EtK6RAKTt2lp/p0aDI="},
      {"name":"libglib2.0-0t64","version":"2.84.4-3~deb13u5","file":"libglib2.0-0t64_2.84.4-3~deb13u5_amd64.deb","url":"https://deb.debian.org/debian/pool/main/g/glib2.0/libglib2.0-0t64_2.84.4-3%7edeb13u5_amd64.deb","hash":"sha256-4rr5LFfR2xdT5XgaYUUNmgHngzx70t/od3amgRwR7MI="},
      {"name":"libgs-common","version":"10.05.1~dfsg-1+deb13u3","file":"libgs-common_10.05.1~dfsg-1+deb13u3_all.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/g/ghostscript/libgs-common_10.05.1%7edfsg-1%2bdeb13u3_all.deb","hash":"sha256-NF0+ugTAD2UpA+KqxZxTR+p0BU5T/PXQ28dQDqXpOkg="},
      {"name":"libgs10-common","version":"10.05.1~dfsg-1+deb13u3","file":"libgs10-common_10.05.1~dfsg-1+deb13u3_all.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/g/ghostscript/libgs10-common_10.05.1%7edfsg-1%2bdeb13u3_all.deb","hash":"sha256-0Gg1ao5yhc+OdNLGazwZiCJXASBwS+z3IRvu0vBcCU8="},
      {"name":"libgs10","version":"10.05.1~dfsg-1+deb13u3","file":"libgs10_10.05.1~dfsg-1+deb13u3_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/g/ghostscript/libgs10_10.05.1%7edfsg-1%2bdeb13u3_amd64.deb","hash":"sha256-azBNVYATVN4/uuwLAAyLMaolM16+olWTtygyr/IihlU="},
      {"name":"libheif-plugin-dav1d","version":"1.23.6-2~deb13u1","file":"libheif-plugin-dav1d_1.23.6-2~deb13u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/libh/libheif/libheif-plugin-dav1d_1.23.6-2%7edeb13u1_amd64.deb","hash":"sha256-lSGUBy/Q+2a/iSP6smLzi7AI367lPzUYKMJ7kH4PpM0="},
      {"name":"libheif-plugin-libde265","version":"1.23.6-2~deb13u1","file":"libheif-plugin-libde265_1.23.6-2~deb13u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/libh/libheif/libheif-plugin-libde265_1.23.6-2%7edeb13u1_amd64.deb","hash":"sha256-h87KUVAAVYE/tPQ1Qj3wKQRh5eEQS4WB7XGvuGIFgcU="},
      {"name":"libheif1","version":"1.23.6-2~deb13u1","file":"libheif1_1.23.6-2~deb13u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/libh/libheif/libheif1_1.23.6-2%7edeb13u1_amd64.deb","hash":"sha256-ZumScF8p68RJm3ucFC8u2Sz8oeF9+Bt6ZGyC1CzSiGQ="},
      {"name":"libjbig2dec0","version":"0.20-1+deb13u1","file":"libjbig2dec0_0.20-1+deb13u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/j/jbig2dec/libjbig2dec0_0.20-1%2bdeb13u1_amd64.deb","hash":"sha256-fT+bTmK47Ed914EjS+ArhkncVj+OZ/kbvAJpGn6j1OM="},
      {"name":"libjxl0.11","version":"0.11.2-0.1~deb13u3","file":"libjxl0.11_0.11.2-0.1~deb13u3_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/j/jpeg-xl/libjxl0.11_0.11.2-0.1%7edeb13u3_amd64.deb","hash":"sha256-3csUn4dbLtarkWDFnB9G7vSLghAFAz5XTcgp5t6swm4="},
      {"name":"liblastlog2-2","version":"2.41.5-0+deb13u1","file":"liblastlog2-2_2.41.5-0+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/u/util-linux/liblastlog2-2_2.41.5-0%2bdeb13u1_amd64.deb","hash":"sha256-q7dq7L9RR55uGThz392qG4hmfcCx24KhEoamdVC6FVc="},
      {"name":"liblzma5","version":"5.8.1-1+deb13u2","file":"liblzma5_5.8.1-1+deb13u2_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/x/xz-utils/liblzma5_5.8.1-1%2bdeb13u2_amd64.deb","hash":"sha256-s4rKsw8pW/EGamYy4xy9ChmA8pJLOAQM2hMdXepThOw="},
      {"name":"libmagickcore-7.q16-10","version":"8:7.1.1.43+dfsg1-1+deb13u13","file":"libmagickcore-7.q16-10_8%3a7.1.1.43+dfsg1-1+deb13u13_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/i/imagemagick/libmagickcore-7.q16-10_7.1.1.43%2bdfsg1-1%2bdeb13u13_amd64.deb","hash":"sha256-dRnXijWVxJk07WtOgNw6x+BWlLVqKofEohtpu3iHelQ="},
      {"name":"libmagickwand-7.q16-10","version":"8:7.1.1.43+dfsg1-1+deb13u13","file":"libmagickwand-7.q16-10_8%3a7.1.1.43+dfsg1-1+deb13u13_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/i/imagemagick/libmagickwand-7.q16-10_7.1.1.43%2bdfsg1-1%2bdeb13u13_amd64.deb","hash":"sha256-bjCDfvi+TUU9BnDnfQVyMgPoHYEMQmZqOXOlhPp4jY4="},
      {"name":"libmbedcrypto16","version":"3.6.6-0.1~deb13u1","file":"libmbedcrypto16_3.6.6-0.1~deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/m/mbedtls/libmbedcrypto16_3.6.6-0.1%7edeb13u1_amd64.deb","hash":"sha256-s4uvLsrKeyizAF00uBCO6bF2gUJrIGYoE5lek5rqbfo="},
      {"name":"libmount1","version":"2.41.5-0+deb13u1","file":"libmount1_2.41.5-0+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/u/util-linux/libmount1_2.41.5-0%2bdeb13u1_amd64.deb","hash":"sha256-bQD0Xy6A4HjpBuPu3s07ppE+Of70m/82HuWD8X8A7AU="},
      {"name":"libnss3","version":"2:3.110-1+deb13u5","file":"libnss3_2%3a3.110-1+deb13u5_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/n/nss/libnss3_3.110-1%2bdeb13u5_amd64.deb","hash":"sha256-cFmDkWXDnnNP9ZxxL96D716gEyiHKBnfur0cCOdfMRY="},
      {"name":"libpcre2-8-0","version":"10.46-1~deb13u3","file":"libpcre2-8-0_10.46-1~deb13u3_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/p/pcre2/libpcre2-8-0_10.46-1%7edeb13u3_amd64.deb","hash":"sha256-4ib2YdkY8E2vOM28SAa37X1u+Vx+sK3mkvw1DjGXAEA="},
      {"name":"libpcre2-posix3","version":"10.46-1~deb13u3","file":"libpcre2-posix3_10.46-1~deb13u3_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/p/pcre2/libpcre2-posix3_10.46-1%7edeb13u3_amd64.deb","hash":"sha256-Sn919vO35nqafx3N/KY3fbZWQFe6wqIly9BYP+h4998="},
      {"name":"libperl5.40","version":"5.40.1-6+deb13u1","file":"libperl5.40_5.40.1-6+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/p/perl/libperl5.40_5.40.1-6%2bdeb13u1_amd64.deb","hash":"sha256-5Ed3/0etJI0d69V+H5arXokGGjQQCK45iAujtfwV8nM="},
      {"name":"libpng16-16t64","version":"1.6.48-1+deb13u6","file":"libpng16-16t64_1.6.48-1+deb13u6_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/libp/libpng1.6/libpng16-16t64_1.6.48-1%2bdeb13u6_amd64.deb","hash":"sha256-D4A00cJUd2BDDIHo2H5das1TOjSTyAz3bb7NA0O2dzw="},
      {"name":"libraw23t64","version":"0.21.4-2+deb13u1","file":"libraw23t64_0.21.4-2+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/libr/libraw/libraw23t64_0.21.4-2%2bdeb13u1_amd64.deb","hash":"sha256-YO5LWVwjBFMf8oD5xvLUpDcfojh4upUE0KFdMnEweWE="},
      {"name":"librsvg2-2","version":"2.60.0+dfsg-1+deb13u1","file":"librsvg2-2_2.60.0+dfsg-1+deb13u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/libr/librsvg/librsvg2-2_2.60.0%2bdfsg-1%2bdeb13u1_amd64.deb","hash":"sha256-X2j3IOzO/r2jhVowAHyrnXZiBCzLwBwSaqX2l65uV5E="},
      {"name":"libsmartcols1","version":"2.41.5-0+deb13u1","file":"libsmartcols1_2.41.5-0+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/u/util-linux/libsmartcols1_2.41.5-0%2bdeb13u1_amd64.deb","hash":"sha256-2WusnIgFaF8nNIhQmKIUuClQ2m67GCwnprehJKAyM5I="},
      {"name":"libsqlite3-0","version":"3.46.1-7+deb13u2","file":"libsqlite3-0_3.46.1-7+deb13u2_amd64.deb","url":"https://deb.debian.org/debian/pool/main/s/sqlite3/libsqlite3-0_3.46.1-7%2bdeb13u2_amd64.deb","hash":"sha256-CkWa2v/ZARCfeBGrZfWOepV7SQfQVTnPPRGE79zeBGg="},
      {"name":"libssh2-1t64","version":"1.11.1-1+deb13u2","file":"libssh2-1t64_1.11.1-1+deb13u2_amd64.deb","url":"https://deb.debian.org/debian/pool/main/libs/libssh2/libssh2-1t64_1.11.1-1%2bdeb13u2_amd64.deb","hash":"sha256-27ECTBktTSkrfPqQK5YHbP6BtWpe7U+yjaNui/VD5Jo="},
      {"name":"libssl3t64","version":"3.5.7-1~deb13u3","file":"libssl3t64_3.5.7-1~deb13u3_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/o/openssl/libssl3t64_3.5.7-1%7edeb13u3_amd64.deb","hash":"sha256-/xa8BIvNfRslYJRFC3nHeUfY52/iokvZm5ECHVkfoHQ="},
      {"name":"libuuid1","version":"2.41.5-0+deb13u1","file":"libuuid1_2.41.5-0+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/u/util-linux/libuuid1_2.41.5-0%2bdeb13u1_amd64.deb","hash":"sha256-wb9MTD/0jFf6v5MwfftWmWtgz6M5J6/EFYtds2+ych4="},
      {"name":"login","version":"1:4.16.0-2+really2.41.5-0+deb13u1","file":"login_1%3a4.16.0-2+really2.41.5-0+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/u/util-linux/login_4.16.0-2%2breally2.41.5-0%2bdeb13u1_amd64.deb","hash":"sha256-j8WGlTKnPVd8Srte2RfgSLvXIUhwLqHcrdOBcGTz6Ic="},
      {"name":"mount","version":"2.41.5-0+deb13u1","file":"mount_2.41.5-0+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/u/util-linux/mount_2.41.5-0%2bdeb13u1_amd64.deb","hash":"sha256-63CmFRFKxAEjdovrIOMCVU1ct+2zMpC+fkGOvhB1yHg="},
      {"name":"openssl-provider-legacy","version":"3.5.7-1~deb13u3","file":"openssl-provider-legacy_3.5.7-1~deb13u3_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/o/openssl/openssl-provider-legacy_3.5.7-1%7edeb13u3_amd64.deb","hash":"sha256-wS4CZsR4B0mkcCuJWayXlon0GC4Y7thail65DtDhbqs="},
      {"name":"openssl","version":"3.5.7-1~deb13u3","file":"openssl_3.5.7-1~deb13u3_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/o/openssl/openssl_3.5.7-1%7edeb13u3_amd64.deb","hash":"sha256-Q6nLzyqKDh8KHD9aM+4fVrJpaQ56ISnystBYLniVidc="},
      {"name":"perl-base","version":"5.40.1-6+deb13u1","file":"perl-base_5.40.1-6+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/p/perl/perl-base_5.40.1-6%2bdeb13u1_amd64.deb","hash":"sha256-t5VGQTeg9NRD/JKE9Lk+iD+4OIPLUzrfMArGYIB6NSo="},
      {"name":"perl-modules-5.40","version":"5.40.1-6+deb13u1","file":"perl-modules-5.40_5.40.1-6+deb13u1_all.deb","url":"https://deb.debian.org/debian/pool/main/p/perl/perl-modules-5.40_5.40.1-6%2bdeb13u1_all.deb","hash":"sha256-TEbN2PMTWqHJXwfoF/jl2b5ZBodEGsHCfjqMSUAPNc4="},
      {"name":"perl","version":"5.40.1-6+deb13u1","file":"perl_5.40.1-6+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/p/perl/perl_5.40.1-6%2bdeb13u1_amd64.deb","hash":"sha256-7xRcJHeH1vQNze/VtBdQJISCfN4NVVmYwX/Vsn7B4d0="},
      {"name":"tzdata","version":"2026f-0+deb13u1","file":"tzdata_2026f-0+deb13u1_all.deb","url":"https://deb.debian.org/debian/pool/main/t/tzdata/tzdata_2026f-0%2bdeb13u1_all.deb","hash":"sha256-LBxWEJFAKINDDQ1HxXo8CqALRK/IpiOSZQZahyEaXBE="},
      {"name":"util-linux","version":"2.41.5-0+deb13u1","file":"util-linux_2.41.5-0+deb13u1_amd64.deb","url":"https://deb.debian.org/debian/pool/main/u/util-linux/util-linux_2.41.5-0%2bdeb13u1_amd64.deb","hash":"sha256-fVsRdsw9jMaykLPsF69FjzYtkgCEXzDaIgV6gZh0RDA="}
    ]
  '';
  paperlessWheels = builtins.fromJSON ''
    [
      {"name":"tika-client","version":"2.0.0","file":"tika_client-2.0.0-py3-none-any.whl","url":"https://files.pythonhosted.org/packages/81/fe/ee25b47093fc1a71fa49bffdf8ede1f6dc0fde3212fa3568fac20d63e2ac/tika_client-2.0.0-py3-none-any.whl","hash":"sha256-RN16UierLSW8iLj/KCA5YC6qwFkuVC7gSG2VNewb6bI="},
      {"name":"pillow","version":"13.0.0","file":"pillow-13.0.0-cp314-cp314-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl","url":"https://files.pythonhosted.org/packages/1d/f2/1371707ce438ba9a43f9d24089828494ec6f9396e28cd7903aa704dd6306/pillow-13.0.0-cp314-cp314-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl","hash":"sha256-6RwrHL6udoyYdS5n5xfig9aNrkVxe0Hy2R6u5kjje30="},
      {"name":"anyio","version":"4.14.2","file":"anyio-4.14.2-py3-none-any.whl","url":"https://files.pythonhosted.org/packages/da/35/f2287558c17e29fafc8ef3daf819bb9834061cfa43bff8014f7df7f63bdc/anyio-4.14.2-py3-none-any.whl","hash":"sha256-n1Bd2lrJ8Mgwm16L1EWowr9yRvPOlQEh5F6hW8QdFJQ="},
      {"name":"PyJWT","version":"2.14.0","file":"pyjwt-2.14.0-py3-none-any.whl","url":"https://files.pythonhosted.org/packages/9c/97/672cb32ce0dfea44b740cb7b4f97038463b9cf7c0ead1aacf595572851d6/pyjwt-2.14.0-py3-none-any.whl","hash":"sha256-rQzvccdWpW50hjwpGc8Jhfct7Lz8tVDuL0IufGK17tw="},
      {"name":"certifi","version":"2026.10.18","file":"certifi-2026.10.18-py3-none-any.whl","url":"https://files.pythonhosted.org/packages/08/ba/95dd616042484f7c83a06974388b37b837732740ee70bc5dc715b5fcd55a/certifi-2026.10.18-py3-none-any.whl","hash":"sha256-cxkcR6qnnaOU6P7i28LsgnQyyrVjERIsnker9545D2I="},
      {"name":"Brotli","version":"1.2.1","file":"brotli-1.2.1-cp314-cp314-manylinux2014_x86_64.manylinux_2_17_x86_64.whl","url":"https://files.pythonhosted.org/packages/c4/07/8948582ce173e8e43cea9fadb8c3c3ea94800fb9814119c9239c1ae6c797/brotli-1.2.1-cp314-cp314-manylinux2014_x86_64.manylinux_2_17_x86_64.whl","hash":"sha256-qZiFevT80ZkgvfXzDw8aI/OEcqcD0z5JFozU/TJDg3c="}
    ]
  '';
  paperlessRuntime = helpers.mkRuntimeImage {
    name = "paperless";
    version = "3.1.3-python3.14.10";
    recipe = ''
      FROM docker.io/library/python@sha256:ec6a14df5b63e3fbb3498e3240f7f640c230f9dca67683d23265db3866697f2d AS patched-python
      RUN rm -r /usr/local/lib/python3.14/site-packages
      # Fixed runtime inputs ${builtins.hashString "sha256" (builtins.toJSON { inherit paperlessDebs paperlessWheels; })}
      FROM ghcr.io/paperless-ngx/paperless-ngx@sha256:aa810a36942c63d4ee70d00eda7236cd3d6acfb7eb3f7987fb568ed14df8817a
      COPY debian/ /tmp/hwc-debs/
      RUN DEBIAN_FRONTEND=noninteractive apt-get --no-download --yes -o Dir::Cache::archives=/tmp/hwc-debs -o Dpkg::Options::=--force-confold install /tmp/hwc-debs/*.deb && test -z "$(dpkg --audit)" && rm -r /tmp/hwc-debs
      RUN find /usr/local/lib/python3.14 -mindepth 1 -maxdepth 1 ! -name site-packages -exec rm -r -- {} +
      COPY --from=patched-python /usr/local/lib/python3.14/ /usr/local/lib/python3.14/
      COPY --from=patched-python /usr/local/bin/python3.14 /usr/local/bin/python3.14
      COPY --from=patched-python /usr/local/lib/libpython3.14.so.1.0 /usr/local/lib/libpython3.14.so.1.0
      COPY wheels/ /tmp/hwc-wheels/
      RUN python3 -m pip install --no-index --no-deps --no-cache-dir --force-reinstall /tmp/hwc-wheels/*.whl && rm -r /tmp/hwc-wheels
    '';
  };
  paperlessManifest = pkgs.writeText "paperless-runtime-packages.json" (builtins.toJSON {
    debian = paperlessDebs;
    wheels = paperlessWheels;
  });
  paperlessContext = pkgs.runCommand "paperless-runtime-context" {} ''
    mkdir -p "$out/debian" "$out/wheels"
    cp ${paperlessRuntime.dockerfile} "$out/Dockerfile"
    cp ${paperlessManifest} "$out/manifest.json"
    ${lib.concatMapStrings (p: let source = pkgs.fetchurl { inherit (p) url hash; }; in ''
      cp ${source} "$out/debian/${p.file}"
    '') paperlessDebs}
    ${lib.concatMapStrings (p: let source = pkgs.fetchurl { inherit (p) url hash; }; in ''
      cp ${source} "$out/wheels/${p.file}"
    '') paperlessWheels}
  '';
  # The vendor entrypoint directly starts Java; its unused Pebble supervisor
  # carries a separate outdated Go runtime. Remove that unused executable,
  # rather than exposing or treating it as a Java-server vulnerability.
  tikaRuntime = helpers.mkRuntimeImage {
    name = "paperless-tika";
    version = "4.2.0";
    recipe = ''
      FROM docker.io/apache/tika@sha256:b99f19c4fd76237dafe7d22f719b9bddfa9a449da687c597a41e2f6d9a595418
      USER root
      RUN test -f /usr/bin/pebble && rm /usr/bin/pebble
      USER 35002:35002
    '';
  };
in
{
  # OPTIONS
  options.hwc.business.paperless = {
    enable = lib.mkEnableOption "Paperless-NGX document management (containerized)";

    image = lib.mkOption {
      type = lib.types.str;
      # v3 renamed or requires several env vars (see parts/config.nix) and only
      # migrates a database already at 2.20.15 — do not jump from older 2.x.
      default = if cfg.officeIngest.enable then paperlessRuntime.image else "ghcr.io/paperless-ngx/paperless-ngx:3.1.3";
      description = "Paperless-NGX container image";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8102;
      description = "Internal HTTP port for Paperless";
    };

    network.mode = lib.mkOption {
      type = lib.types.enum [ "media" "host" ];
      default = "media";
      description = "Network mode for the container";
    };

    database = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "10.89.0.1";  # media-network gateway
        description = "PostgreSQL host (containers can't use localhost)";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "paperless";
        description = "PostgreSQL database name";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = cfg.database.name;
        description = "Restricted PostgreSQL owner (must match the database name)";
      };
      passwordSecret = lib.mkOption { type = lib.types.str; default = "paperless-db-env"; };
    };

    redis = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "10.89.0.1";  # media-network gateway
        description = "Redis host";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 6379;
        description = "Redis port";
      };
    };

    storage = {
      consumeDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.hot.root != null then "${paths.hot.root}/documents/consume" else null;
        description = "Consume directory (drop zone for auto-import)";
      };

      exportDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.hot.root != null then "${paths.hot.root}/documents/export" else null;
        description = "Export directory";
      };

      stagingDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.hot.root != null then "${paths.hot.root}/documents/staging" else null;
        description = "Staging directory for pre-processing";
      };

      mediaDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.media.root != null then "${paths.media.root}/documents/paperless" else null;
        description = "Archive storage (originals, archive, thumbnails)";
      };

      dataDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.apps.root != null then "${paths.apps.root}/paperless/data" else null;
        description = "Paperless data directory (index, db cache)";
      };
    };

    ocr = {
      languages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "eng" ];
        description = "Tesseract OCR language codes";
      };

      outputType = lib.mkOption {
        type = lib.types.enum [ "pdf" "pdfa" "pdfa-2" ];
        default = "pdfa";
        description = "OCR output format (pdf, pdfa, pdfa-2)";
      };

      # Ghostscript refuses to write a PDF/A copy of a PDF that breaks the
      # PDF/A rules — two Cancer Cell papers carry images with `Interpolate
      # true`, which PDF/A forbids — and ocrmypdf then fails the whole import.
      # This tells ocrmypdf to keep going after such a rejection, so the file
      # becomes a document. Only the archive copy can differ from the source;
      # the original file is stored either way. Upstream names this setting as
      # the fix for "Ghostscript PDF/A rendering failed" (docs/troubleshooting.md).
      continueOnSoftRenderError = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Import a PDF even when Ghostscript rejects its PDF/A archive copy";
      };

      # v3 default is "auto", which skips the archive copy for born-digital PDFs.
      # "always" keeps the v2 behaviour, where every document got a PDF/A archive.
      archiveFileGeneration = lib.mkOption {
        type = lib.types.enum [ "auto" "always" "never" ];
        default = "always";
        description = "When paperless creates a PDF/A archive copy (PAPERLESS_ARCHIVE_FILE_GENERATION)";
      };
    };

    consumer = {
      polling = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Seconds between consume folder scans";
      };

      deleteOriginals = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Delete originals after successful import";
      };

      # v2 rejected a file whose hash matched an existing document. v3 imports
      # it as a second document unless this is on, in which case the duplicate
      # is deleted from the consume dir. On keeps one document per file.
      deleteDuplicates = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Delete consume-dir files that duplicate an existing document instead of importing them";
      };

      # Subdirectory handling for bulk imports. With both on, a file dropped at
      # consume/230_admin/housing/lease.pdf is tagged `230_admin` and `housing`.
      # subdirsAsTags does nothing without recursive — paperless never looks
      # below the consume root — so the assertion in parts/config.nix ties them.
      recursive = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Consume files in subdirectories of the consume dir";
      };

      subdirsAsTags = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Tag consumed files with the names of their subdirectories";
      };
    };

    # Office-document ingest. Paperless parses PDFs and images on its own and
    # SKIPS everything else, silently — a .docx dropped in the consume dir is
    # not an error, it just never becomes a document. Tika extracts the text and
    # metadata; Gotenberg renders the file to PDF for the archive copy. Both are
    # sidecars on the private bridge reached by container DNS, so they publish no host
    # port and claim nothing in domains/networking/routes.nix.
    officeIngest = {
      enable = lib.mkEnableOption "Tika + Gotenberg sidecars for Office document ingest" // { default = true; };

      tikaImage = lib.mkOption {
        type = lib.types.str;
        default = tikaRuntime.image; # 4.2.0, CXF 4.2.4
        description = "Apache Tika server container image";
      };

      gotenbergImage = lib.mkOption {
        type = lib.types.str;
        # Qualified with the installed Paperless client: HTML/DOCX -> PDF/A-2B.
        default = gotenbergRuntime.image;
        description = "Gotenberg container image";
      };
    };

    # Mail ingest: expose Proton Bridge IMAP (loopback-only) on the podman
    # gateway so the paperless container's mail fetcher can poll it.
    mailIngest = {
      enable = lib.mkEnableOption "IMAP proxy for paperless mail ingest (Proton Bridge → podman gateway)" // { default = true; };

      gatewayAddr = lib.mkOption {
        type = lib.types.str;
        default = "10.89.0.1";
        description = "Podman media-network gateway address to bind the IMAP proxy on";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 1143;
        description = "IMAP port (same on loopback source and gateway bind)";
      };
    };

    # Phone receipts: watch the Syncthing mobile-inbox receipts folder and
    # move drops into the consume dir for OCR ingestion.
    serverAlias = lib.mkOption {
      type = lib.types.str;
      default = "work";  # service split wave 3
      description = ''
        hwc.networking.hosts alias of the host that runs Paperless. A receipts
        watcher on another host forwards into that host's consume dir, read
        from its evaluated config (one producer of the path).
      '';
    };
    receipts = {
      # Independent of `enable`: it runs on the host that holds the phone
      # folder, which need not be the host that runs Paperless.
      enable = lib.mkEnableOption "the phone receipts folder watcher (enable on the host that holds receipts.mobileDir)";

      mobileDir = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/vaults/inbox-mobile/receipts";
        description = "Phone-synced folder watched for receipt photos/PDFs";
      };
    };

    admin = {
      user = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "Initial admin username";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "eric@hwc.local";
        description = "Initial admin email";
      };
    };

    reverseProxy = {
      path = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Reverse proxy subpath. Empty is correct for the current name-based
          vhost (paperless.<vhostDomain>), where paperless serves at root; the
          option stays so it can be put back behind a prefix without a code
          change. When non-empty it emits PAPERLESS_FORCE_SCRIPT_NAME, which
          Django uses to prefix every generated URL — so it must match the
          route's `path` exactly or the app links to pages that do not route.
        '';
      };
    };

    resources = {
      memory = lib.mkOption {
        type = lib.types.str;
        default = "4g";
        description = "Memory limit for Paperless container";
      };

      cpus = lib.mkOption {
        type = lib.types.str;
        default = "2.0";
        description = "CPU limit for Paperless container";
      };
    };

    retention = {
      cleanup = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Paperless staging/export cleanup timer";
        };

        schedule = lib.mkOption {
          type = lib.types.str;
          default = "daily";
          description = "systemd OnCalendar schedule for cleanup";
        };

        stagingDays = lib.mkOption {
          type = lib.types.int;
          default = 7;
          description = "Delete staging files older than N days";
        };

        exportDays = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "Delete export files older than N days";
        };
      };
    };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
    ./parts/directories.nix
    ./parts/receipts.nix
  ];

  #=========================================================================
  # IMPLEMENTATION
  #=========================================================================
  config = lib.mkIf cfg.enable {
    system.build.paperlessRuntimeImageContext = paperlessContext;
    system.build.paperlessRuntimeImageRecipe = paperlessRuntime.dockerfile;
    system.build.tikaRuntimeImageRecipe = tikaRuntime.dockerfile;
    system.build.gotenbergRuntimeImageContext = gotenbergContext;
    system.build.gotenbergRuntimeImageRecipe = gotenbergRuntime.dockerfile;
    virtualisation.oci-containers.containers = lib.mkMerge [
      (lib.mkIf (cfg.image == paperlessRuntime.image) {
        paperless.pull = lib.mkForce "never";
      })
      (lib.mkIf (cfg.officeIngest.enable && cfg.officeIngest.tikaImage == tikaRuntime.image) {
        paperless-tika.pull = lib.mkForce "never";
      })
      (lib.mkIf
      (cfg.officeIngest.enable && cfg.officeIngest.gotenbergImage == gotenbergRuntime.image) {
      paperless-gotenberg.pull = lib.mkForce "never";
      })
    ];
    systemd.services.podman-paperless = lib.mkIf (cfg.image == paperlessRuntime.image) {
      preStart = lib.mkBefore ''
        ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg paperlessRuntime.image} || {
          echo "Paperless requires the qualified client image from ${paperlessContext}" >&2
          exit 1
        }
      '';
    };
    systemd.services.podman-paperless-tika = lib.mkIf
      (cfg.officeIngest.enable && cfg.officeIngest.tikaImage == tikaRuntime.image) {
      preStart = lib.mkBefore ''
        ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg tikaRuntime.image} || {
          echo "Tika requires the qualified image from ${tikaRuntime.dockerfile}" >&2
          exit 1
        }
      '';
    };
    systemd.services.podman-paperless-gotenberg = lib.mkIf
      (cfg.officeIngest.enable && cfg.officeIngest.gotenbergImage == gotenbergRuntime.image) {
      preStart = lib.mkBefore ''
        ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg gotenbergRuntime.image} || {
          echo "Gotenberg requires the qualified image from ${gotenbergContext}" >&2
          exit 1
        }
      '';
    };
  };

  #=========================================================================
  # VALIDATION
  #=========================================================================
  # Add assertions and validation logic here
}
