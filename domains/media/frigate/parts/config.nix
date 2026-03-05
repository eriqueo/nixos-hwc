# domains/media/frigate/parts/config.nix
#
# Frigate NVR configuration — nix-native structured config
# Generates YAML config template with ${VARIABLE} placeholders for secrets
# Runtime service substitutes secrets via envsubst
{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.media.frigate;
  yaml = pkgs.formats.yaml { };

  # Camera RTSP URL template (secrets substituted at runtime)
  rtspUrl = camIpVar: "rtsp://\${RTSP_USER}:\${RTSP_PASS_ENCODED}@\${${camIpVar}}:554/ch01/0";

  # Shared ffmpeg configuration
  ffmpegDefaults = {
    global_args = [ "-hide_banner" "-loglevel" "warning" ];
    hwaccel_args = [
      "-hwaccel" "nvdec"
      "-hwaccel_device" "0"
      "-hwaccel_output_format" "yuv420p"
    ];
    input_args = [
      "-avoid_negative_ts" "make_zero"
      "-fflags" "nobuffer"
      "-flags" "low_delay"
      "-strict" "experimental"
      "-rtsp_transport" "tcp"
      "-timeout" "5000000"
      "-analyzeduration" "5000000"
      "-probesize" "5000000"
    ];
    output_args = {
      record = "preset-record-generic";
    };
  };

  # Full config structure
  frigateConfig = {
    version = "0.16.0";

    mqtt.enabled = false;

    telemetry.stats = {
      amd_gpu_stats = false;
      intel_gpu_stats = false;
      network_bandwidth = false;
    };

    detectors.onnx = {
      type = "onnx";
      device = "0";
      num_threads = 4;
      execution_providers = [ "cuda" "cpu" ];
    };

    model = {
      path = "/config/models/yolov9-s-320.onnx";
      model_type = "yolo-generic";
      input_tensor = "nchw";
      input_pixel_format = "bgr";
      input_dtype = "float";
      width = 320;
      height = 320;
      labelmap_path = "/labelmap/coco-80.txt";
    };

    record = {
      enabled = true;
      retain = {
        days = 7;
        mode = "motion";
      };
    };

    snapshots = {
      enabled = true;
      retain = {
        default = 10;
        objects = {
          person = 30;
          car = 14;
          truck = 14;
        };
      };
    };

    objects = {
      track = [ "person" "dog" "cat" "car" "truck" ];
      filters = {
        person = { min_score = 0.65; threshold = 0.7; min_area = 3000; };
        dog    = { min_score = 0.6;  threshold = 0.7; min_area = 2000; };
        cat    = { min_score = 0.6;  threshold = 0.7; min_area = 2000; };
      };
    };

    cameras = {
      cobra_cam_1 = {
        enabled = true;
        audio.enabled = false;
        ffmpeg = ffmpegDefaults // {
          inputs = [
            { path = rtspUrl "CAM1_IP"; roles = [ "detect" ]; }
            { path = rtspUrl "CAM1_IP"; roles = [ "record" ]; }
          ];
        };
        detect = { width = 1280; height = 720; fps = 5; };
        motion.mask = [
          "0,0,1280,100"
          "0,620,200,720"
          "1080,620,1280,720"
        ];
        zones.yard_gate = {
          coordinates = "200,700,1000,700,1000,500,200,500";
          objects = [ "person" "dog" "cat" ];
          filters.person = { min_area = 5000; threshold = 0.75; };
        };
      };

      cobra_cam_2 = {
        enabled = true;
        audio.enabled = false;
        ffmpeg = ffmpegDefaults // {
          inputs = [
            { path = rtspUrl "CAM2_IP"; roles = [ "detect" ]; }
            { path = rtspUrl "CAM2_IP"; roles = [ "record" ]; }
          ];
        };
        detect = { width = 640; height = 360; fps = 3; };
        motion.mask = [ "0,0,640,60" ];
        zones.porch_area = {
          coordinates = "50,340,590,340,590,200,50,200";
          objects = [ "person" "dog" "cat" ];
          filters.person = { min_area = 3000; threshold = 0.75; };
        };
      };

      cobra_cam_3 = {
        enabled = true;
        audio.enabled = false;
        ffmpeg = ffmpegDefaults // {
          inputs = [
            { path = rtspUrl "CAM3_IP"; roles = [ "detect" ]; }
            { path = rtspUrl "CAM3_IP"; roles = [ "record" ]; }
          ];
        };
        detect = { width = 640; height = 480; fps = 3; };
        objects = {
          track = [ "person" "car" "truck" "dog" "cat" ];
          filters = {
            car   = { min_score = 0.7; threshold = 0.75; min_area = 10000; };
            truck = { min_score = 0.7; threshold = 0.75; min_area = 12000; };
          };
        };
        motion.mask = [ "0,0,640,80" ];
        zones = {
          driveway_truck = {
            coordinates = "50,450,400,450,400,350,50,350";
            objects = [ "person" "car" "truck" ];
            filters = {
              car   = { min_area = 10000; };
              truck = { min_area = 12000; };
            };
          };
          sidewalk_front = {
            coordinates = "50,300,590,300,590,360,50,360";
            objects = [ "person" "dog" "cat" ];
          };
        };
      };
    };

    go2rtc.streams = {
      cobra_cam_1 = [ (rtspUrl "CAM1_IP") ];
      cobra_cam_2 = [ (rtspUrl "CAM2_IP") ];
      cobra_cam_3 = [ (rtspUrl "CAM3_IP") ];
    };

    ui.timezone = "America/Denver";
    detect.enabled = true;
  };

  # Generate the YAML config template file
  configTemplate = yaml.generate "frigate-config.yml" frigateConfig;
in
{
  config = lib.mkIf cfg.enable {
    # Export the generated config template for the runtime service to use
    hwc.media.frigate._configTemplate = configTemplate;
  };
}
