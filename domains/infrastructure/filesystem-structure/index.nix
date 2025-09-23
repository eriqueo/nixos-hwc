{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.infrastructure.filesystemStructure;
  paths = config.hwc.paths;
  mk = mode: path: "d ${path} ${mode} eric users -";
  mk0755 = path: mk "0755" path;
  baseDirs = [
    paths.user.home
    paths.user.inbox
    paths.user.work
    paths.user.personal
    paths.user.tech
    paths.user.reference
    paths.user.media
    paths.user.vaults
  ];
  xdgDirs = [
    paths.userDirs.documents
    paths.userDirs.templates
    paths.userDirs.pictures
    paths.userDirs.music
    paths.userDirs.videos
  ];
  mediaSubdirs = [
    paths.mediaPaths.screenshots
    paths.mediaPaths.picturesInbox
  ];
in {
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable (lib.mkMerge [

    {
      users.groups = {
        ${cfg.permissions.mediaGroup} = { gid = 2000; };
        hwc = { gid = 2001; };
      };
      environment.systemPackages = with pkgs; [ ncdu tree lsof psmisc ];
    }

    (lib.mkIf cfg.userDirectories.enable {
      systemd.tmpfiles.rules =
        [ "Z ${paths.nixos} - eric users - -" ]
        ++ map mk0755 baseDirs
        ++ map mk0755 xdgDirs
        ++ map mk0755 mediaSubdirs
        ++ [
          (mk "0755" paths.user.config)
          (mk "0755" "${paths.user.home}/.local")
          (mk "0755" "${paths.user.home}/.local/bin")
          (mk "0700" paths.user.ssh)
        ];

      environment.etc."skel/.config/user-dirs.dirs".text = ''
        XDG_DESKTOP_DIR="${paths.userDirs.desktop}"
        XDG_DOWNLOAD_DIR="${paths.userDirs.download}"
        XDG_TEMPLATES_DIR="${paths.userDirs.templates}"
        XDG_PUBLICSHARE_DIR="${paths.userDirs.publicShare}"
        XDG_DOCUMENTS_DIR="${paths.userDirs.documents}"
        XDG_MUSIC_DIR="${paths.userDirs.music}"
        XDG_PICTURES_DIR="${paths.userDirs.pictures}"
        XDG_VIDEOS_DIR="${paths.userDirs.videos}"
      '';
    })

    (lib.mkIf cfg.serverStorage.enable {
      assertions = [{
        assertion = paths.hot != null && paths.media != null;
        message = "Server storage requires hwc.paths.hot and hwc.paths.media to be configured";
      }];
      systemd.tmpfiles.rules = [
        "d ${paths.media} 0755 eric users -"
        "d ${paths.media}/tv 0755 eric users -"
        "d ${paths.media}/movies 0755 eric users -"
        "d ${paths.media}/music 0755 eric users -"
        "d ${paths.media}/pictures 0755 eric users -"
        "d ${paths.media}/downloads 0755 eric users -"
        "d ${paths.media}/surveillance 0755 eric users -"
        "d ${paths.media}/surveillance/frigate 0755 eric users -"
        "d ${paths.media}/surveillance/frigate/media 0755 eric users -"
        "d ${paths.hot} 0755 eric users -"
      ] ++ lib.optionals cfg.serverStorage.createDownloadZones [
        "d ${paths.hot}/downloads 0755 eric users -"
        "d ${paths.hot}/downloads/  eric users -"
        "d ${paths.hot}/downloads/music 0755 eric users -"
        "d ${paths.hot}/downloads/movies 0755 eric users -"
        "d ${paths.hot}/downloads/tv 0755 eric users -"
        "d ${paths.hot}/downloads/other 0755 eric users -"

      ] ++ lib.optionals cfg.serverStorage.createCacheDirectories [
        "d ${paths.hot}/cache 0755 eric users -"
        "d ${paths.hot}/cache/frigate 0755 eric users -"
        "d ${paths.hot}/cache/jellyfin 0755 eric users -"
        "d ${paths.hot}/cache/immich 0755 eric users -"
        "d ${paths.hot}/surveillance 0755 eric users -"
        "d ${paths.hot}/surveillance/buffer 0755 eric users -"
        "d ${paths.hot}/databases 0755 eric users -"
        "d ${paths.hot}/databases/postgresql 0755 eric users -"
        "d ${paths.hot}/databases/redis 0755 eric users -"
        "d ${paths.hot}/ai 0755 eric users -"
        "d ${paths.hot}/ai/ollama 0755 eric users -"
        "d ${paths.hot}/cache/gpu 0755 eric users -"
        "d ${paths.hot}/cache/tensorrt 0755 eric users -"
      ];
    })

    (lib.mkIf cfg.businessDirectories.enable {
      systemd.tmpfiles.rules = [
        "d ${paths.business.root} 0755 eric users -"
        "d ${paths.business.api} 0755 eric users -"
        "d ${paths.business.api}/app 0755 eric users -"
        "d ${paths.business.api}/models 0755 eric users -"
        "d ${paths.business.api}/routes 0755 eric users -"
        "d ${paths.business.api}/services 0755 eric users -"
        "d ${paths.business.root}/dashboard 0755 eric users -"
        "d ${paths.business.root}/config 0755 eric users -"
        "d ${paths.business.uploads} 0755 eric users -"
        "d ${paths.business.root}/receipts 0755 eric users -"
        "d ${paths.business.root}/processed 0755 eric users -"
        "d ${paths.business.backups} 0755 eric users -"
        "d ${paths.business.backups}/secrets 0755 eric users -"
        "d ${paths.ai.root} 0755 eric users -"
        "d ${paths.ai.models} 0755 eric users -"
        "d ${paths.ai.context} 0755 eric users -"
        "d ${paths.ai.root}/document-embeddings 0755 eric users -"
        "d ${paths.ai.root}/business-rag 0755 eric users -"
      ] ++ lib.optionals cfg.businessDirectories.createAdhd [
        "d ${paths.adhd.root} 0755 eric users -"
        "d ${paths.adhd.context} 0755 eric users -"
        "d ${paths.adhd.logs} 0755 eric users -"
        "d ${paths.adhd.root}/energy-tracking 0755 eric users -"
        "d ${paths.adhd.root}/scripts 0755 eric users -"
      ];
    })

    (lib.mkIf cfg.serviceDirectories.enable {
      systemd.tmpfiles.rules = [
        "d ${paths.arr.lidarr} 0755 eric users -"
        "d ${paths.arr.lidarr}/config 0755 eric users -"
        "d ${paths.arr.lidarr}/custom-services.d 0755 eric users -"
        "d ${paths.arr.lidarr}/custom-cont-init.d 0755 eric users -"
        "d ${paths.arr.radarr} 0755 eric users -"
        "d ${paths.arr.radarr}/config 0755 eric users -"
        "d ${paths.arr.radarr}/custom-services.d 0755 eric users -"
        "d ${paths.arr.radarr}/custom-cont-init.d 0755 eric users -"
        "d ${paths.arr.sonarr} 0755 eric users -"
        "d ${paths.arr.sonarr}/config 0755 eric users -"
        "d ${paths.arr.sonarr}/custom-services.d 0755 eric users -"
        "d ${paths.arr.sonarr}/custom-cont-init.d 0755 eric users -"
        "d ${paths.arr.prowlarr} 0755 eric users -"
        "d ${paths.arr.prowlarr}/config 0755 eric users -"
        "d ${paths.surveillance.root} 0755 eric users -"
        "d ${paths.surveillance.frigate} 0755 eric users -"
        "d ${paths.surveillance.frigate}/config 0755 eric users -"
        "d ${paths.surveillance.frigate}/media 0755 eric users -"
        "d ${paths.surveillance.root}/home-assistant 0755 eric users -"
        "d ${paths.surveillance.root}/home-assistant/config 0755 eric users -"
      ] ++ lib.optionals cfg.serviceDirectories.createLegacyPaths [
        "d ${paths.arr.downloads} 0755 eric users -"
        "d ${paths.arr.downloads}/qbittorrent 0755 eric users -"
        "d ${paths.arr.downloads}/sonarr 0755 eric users -"
        "d ${paths.arr.downloads}/radarr 0755 eric users -"
        "d ${paths.arr.downloads}/lidarr 0755 eric users -"
        "d ${paths.arr.downloads}/prowlarr 0755 eric users -"
        "d ${paths.arr.downloads}/navidrome 0755 eric users -"
        "d ${paths.arr.downloads}/immich 0755 eric users -"
        "d ${paths.arr.downloads}/sabnzbd 0755 eric users -"
        "d ${paths.arr.downloads}/slskd 0755 eric users -"
        "d ${paths.arr.downloads}/soularr 0755 eric users -"
        "d ${paths.arr.downloads}/gluetun 0755 root root -"
      ];
    })

  ]);
}
