# Default media listeners shared by optional service modules and the route
# registry. routes.nix is a NixOS module, so importing it for a pure default
# would also import its configuration and route dependencies.
{
  audiobookshelf = { port = 13378; option = [ "hwc" "media" "audiobookshelf" "port" ]; };
  books = { port = 5299; option = [ "hwc" "media" "books" "port" ]; };
  calibre = { port = 8083; option = [ "hwc" "media" "calibre" "ports" "desktop" ]; };
  calibre-server = { port = 8090; option = [ "hwc" "media" "calibre" "ports" "webserver" ]; };
  frigate = { port = 5000; option = [ "hwc" "media" "frigate" "port" ]; };
  jellyseerr = { port = 5055; option = [ "hwc" "media" "jellyseerr" "port" ]; };
  lidarr = { port = 8686; option = [ "hwc" "media" "lidarr" "port" ]; };
  mousehole = { port = 5010; option = [ "hwc" "media" "mousehole" "port" ]; };
  navidrome = { port = 4533; option = [ "hwc" "media" "navidrome" "port" ]; };
  organizr = { port = 9983; option = [ "hwc" "media" "organizr" "webPort" ]; };
  pinchflat = { port = 8945; option = [ "hwc" "media" "pinchflat" "port" ]; };
  prowlarr = { port = 9696; option = [ "hwc" "media" "prowlarr" "port" ]; };
  qbittorrent = { port = 8080; option = [ "hwc" "media" "qbittorrent" "webPort" ]; };
  radarr = { port = 7878; option = [ "hwc" "media" "radarr" "port" ]; };
  readarr = { port = 8787; option = [ "hwc" "media" "readarr" "port" ]; };
  sabnzbd = { port = 8081; option = [ "hwc" "media" "sabnzbd" "webPort" ]; };
  sonarr = { port = 8989; option = [ "hwc" "media" "sonarr" "port" ]; };
  tdarr = { port = 8265; option = [ "hwc" "media" "tdarr" "webPort" ]; };
  transcripts = { port = 8100; option = [ "hwc" "media" "youtube" "transcripts" "port" ]; };
}
