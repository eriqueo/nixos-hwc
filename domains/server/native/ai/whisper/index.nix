# domains/server/native/ai/whisper/index.nix
#
# Implementation for hwc.server.ai.whisper — one resident `whisper-server`
# (whisper.cpp) on the loopback, OpenAI-compatible at
# POST /v1/audio/transcriptions. Fronted by the `whisper` Caddy vhost so the
# phone reaches it over the tailnet; consumed on-box by inbox-processor.
#
# Why resident rather than whisper-cli per call: model load is ~1-2 s per
# invocation and dominates a short utterance (measured 2026-09-05: 11 s clip,
# medium.en on the laptop GPU = 3.1 s wall, of which 1.9 s was load).
#
# Why the CUDA-arch override: the cached whisper-cpp binary targets sm_75+
# (CUDA : ARCHS = 750,800,...). On the Quadro P1000 (sm_61) every model
# larger than base.en aborts with "no kernel image is available for execution
# on the device" (surfaces as `ggml_cuda_compute_forward: IM2COL failed`).
# Same fix as llama-cpp: swap CMAKE_CUDA_ARCHITECTURES and rebuild locally.
#
# Why the model is a store path, not a lazily downloaded file: 0.5 GB is
# cheap in the store, a fixed-output derivation is reused across rebuilds,
# and the URL pins a Hugging Face revision so a re-upload cannot change the
# bytes under a stale hash. The llama-cpp ExecStartPre pattern exists for
# 14 GB models where a store copy would be the wrong trade.
#
# Sibling ruled out: llama-cpp/index.nix is "one llama-cpp binary drives N
# llama-server services". whisper is a different binary, protocol, and
# model format; folding it in would leave a file named after one program
# configuring two.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.ai.whisper;

  # ggml weights from https://huggingface.co/ggerganov/whisper.cpp, pinned to
  # one revision so `/resolve/main/` drift cannot break a clean rebuild.
  # Add an entry: download, `nix hash file --type sha256 --base32 <file>`.
  hfRevision = "5359861c739e955e79d9a303bcbc70fb988958b1";
  knownModels = {
    "base.en"              = "00nhqqvgwyl9zgyy7vk9i3n017q2wlncp5p7ymsk0cpkdp47jdx0";
    "small.en"             = "0p8yqkwvpl9lyy43yajk305bps0v5z1qgyg0jwh35j7cb1nqs4y6";
    "medium.en-q5_0"       = "1c4fv1n8r2k865alybhgyb0avchp37aajcbmpyjwgqcgmlk3wwvn";
    "large-v3-turbo-q5_0"  = "1qm7zxamlvac564c3270wqqqks5wc7532q3fqi01zbfmkiq22hir";
  };

  modelFile = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/${hfRevision}/ggml-${cfg.model}.bin";
    sha256 = knownModels.${cfg.model};
  };

  # CMake wants integers (61), not version strings (6.1).
  cmakeArchList =
    if cfg.cudaCapabilities == null then null
    else lib.concatStringsSep ";"
      (map (c: lib.replaceStrings [ "." ] [ "" ] c) cfg.cudaCapabilities);

  whisperPkg =
    if cmakeArchList == null then pkgs.whisper-cpp
    else pkgs.whisper-cpp.overrideAttrs (old: {
      cmakeFlags = map (f:
        if lib.hasPrefix "-DCMAKE_CUDA_ARCHITECTURES" f
        then "-DCMAKE_CUDA_ARCHITECTURES:STRING=${cmakeArchList}"
        else f
      ) (old.cmakeFlags or []);
    });

  runtimeDir = "/run/whisper-server";

  serverArgs =
    [
      "--model" "${modelFile}"
      "--host" "127.0.0.1"
      "--port" (toString cfg.port)
      "--inference-path" "/v1/audio/transcriptions"
      # Accept m4a (iOS), ogg/opus (Discord), mp3 — transcoded by ffmpeg into
      # the runtime dir, the only writable path under ProtectSystem=strict.
      "--convert"
      "--tmp-dir" runtimeDir
      "--threads" (toString cfg.threads)
    ]
    ++ lib.optionals (!cfg.gpu) [ "--no-gpu" ]
    ++ cfg.extraArgs;

  llamaPorts =
    let l = config.hwc.server.ai.llamaCpp or null;
    in if l == null || !(l.enable or false) then []
       else map (s: s.port) (lib.filter (s: s.enable) [ l.gpu l.cpu l.embed ]);

in
{
  #========================================================================
  # OPTIONS
  #========================================================================
  options.hwc.server.ai.whisper = {
    enable = lib.mkEnableOption "resident whisper.cpp speech-to-text server";

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "Service user (Charter: native services run as eric:users).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11503;
      description = "Loopback port. 11500-11502 belong to llama-cpp.";
    };

    model = lib.mkOption {
      type = lib.types.enum (lib.attrNames knownModels);
      default = "small.en";
      description = ''
        ggml model to serve. English-only variants; q5_0 quantisations keep
        the larger models under ~600 MB so they fit beside llama-gpu on the
        4 GB Quadro P1000.
      '';
    };

    gpu = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run the encoder on the GPU. false passes --no-gpu; on the i7-8700K
        that is ~5 s per 11 s clip for small.en and 17 s for medium.en, so
        CPU is a fallback, not a target.
      '';
    };

    cudaCapabilities = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      example = [ "6.1" ];
      description = ''
        Override CMAKE_CUDA_ARCHITECTURES and rebuild whisper-cpp locally.
        Required on Pascal (Quadro P1000 = "6.1"); the cached binary has no
        sm_61 kernels. null = use the cached package as-is.
      '';
    };

    threads = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Decoder / CPU threads (--threads).";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra whisper-server arguments appended verbatim.";
    };
  };

  #========================================================================
  # IMPLEMENTATION
  #========================================================================
  config = lib.mkIf cfg.enable {
    systemd.services.whisper-server = {
      description = "whisper.cpp speech-to-text server (${cfg.model})";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # --convert shells out to `ffmpeg` by name.
      path = [ pkgs.ffmpeg pkgs.coreutils ];

      serviceConfig = {
        Type = "simple";
        User = lib.mkForce cfg.user;
        Group = "users";
        ExecStart = lib.concatStringsSep " "
          ([ "${whisperPkg}/bin/whisper-server" ] ++ map lib.escapeShellArg serverArgs);

        RuntimeDirectory = "whisper-server";
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = runtimeDir;

        Restart = "on-failure";
        RestartSec = 5;

        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        # GPU access needs /dev/nvidia*; do not set PrivateDevices.
      };
    };

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = !(lib.elem cfg.port llamaPorts);
        message = "hwc.server.ai.whisper.port ${toString cfg.port} collides with an enabled llama-cpp service.";
      }
      {
        assertion = cfg.gpu -> (config.hwc.system.hardware.gpu.type or "none") == "nvidia";
        message = "hwc.server.ai.whisper.gpu = true requires hwc.system.hardware.gpu.type = \"nvidia\" (or set gpu = false).";
      }
    ];
  };
}
