#!/usr/bin/env python3
"""
One-shot setup script for Uptime Kuma monitors on hwc-server.

Usage:
    nix-shell -p 'python3.withPackages (ps: [ ps.uptime-kuma-api ])' --run \
        'python3 setup-uptime-kuma.py --password YOUR_PASSWORD'

Connects to local Uptime Kuma instance, creates ntfy notification,
tags, all monitors, and a status page.
"""

import argparse
import sys
import time

from uptime_kuma_api import UptimeKumaApi, MonitorType

# Since Uptime Kuma runs in bridge-networked container,
# use host.containers.internal to reach host services.
H = "host.containers.internal"


def parse_args():
    p = argparse.ArgumentParser(description="Setup Uptime Kuma monitors")
    p.add_argument("--url", default="http://127.0.0.1:3010",
                    help="Uptime Kuma URL (default: http://127.0.0.1:3010)")
    p.add_argument("--username", default="eric")
    p.add_argument("--password", required=True)
    p.add_argument("--dry-run", action="store_true",
                    help="Print what would be created without doing it")
    return p.parse_args()


# ---------------------------------------------------------------------------
# Monitor definitions
# ---------------------------------------------------------------------------

def get_monitors():
    """Return all monitor definitions grouped by tag."""
    return {
        "infrastructure": [
            {"name": "Caddy", "type": MonitorType.HTTP, "url": f"http://{H}:2019/config/", "interval": 60},
            {"name": "Prometheus", "type": MonitorType.HTTP, "url": f"http://{H}:9090/-/healthy", "interval": 60},
            {"name": "Alertmanager", "type": MonitorType.HTTP, "url": f"http://{H}:9093/-/healthy", "interval": 60},
            {"name": "Grafana", "type": MonitorType.HTTP, "url": f"http://{H}:3000/healthz", "interval": 60},
            {"name": "PostgreSQL", "type": MonitorType.PORT, "hostname": H, "port": 5432, "interval": 60},
            {"name": "Redis", "type": MonitorType.PORT, "hostname": H, "port": 6379, "interval": 60},
            {"name": "SSH", "type": MonitorType.PORT, "hostname": H, "port": 22, "interval": 120},
            {"name": "Mosquitto", "type": MonitorType.PORT, "hostname": H, "port": 1883, "interval": 120},
            {"name": "Node Exporter", "type": MonitorType.HTTP, "url": f"http://{H}:9100/metrics", "interval": 120},
            {"name": "Blackbox Exporter", "type": MonitorType.HTTP, "url": f"http://{H}:9115/metrics", "interval": 120},
        ],
        "business": [
            {"name": "n8n", "type": MonitorType.HTTP, "url": f"http://{H}:5678/healthz", "interval": 60, "critical": True},
            {"name": "Vaultwarden", "type": MonitorType.HTTP, "url": f"http://{H}:8222/alive", "interval": 60, "critical": True},
            {"name": "Authentik", "type": MonitorType.HTTP, "url": f"http://{H}:9200/-/health/live/", "interval": 60, "critical": True},
            {"name": "Paperless-NGX", "type": MonitorType.HTTP, "url": f"http://{H}:8102/api/", "interval": 120},
            {"name": "Firefly III", "type": MonitorType.HTTP, "url": f"http://{H}:8085/", "interval": 120,
             "accepted_statuscodes": ["200-299", "300-399"]},
            {"name": "Firefly-Pico", "type": MonitorType.HTTP, "url": f"http://{H}:8086/", "interval": 120},
            {"name": "CloudBeaver", "type": MonitorType.HTTP, "url": f"http://{H}:8978/", "interval": 300},
            {"name": "Transcript API", "type": MonitorType.HTTP, "url": f"http://{H}:8099/health", "interval": 120},
            {"name": "Heartwood MCP", "type": MonitorType.HTTP, "url": f"http://{H}:6100/", "interval": 300},
            {"name": "Estimator", "type": MonitorType.HTTP, "url": "https://hwc.ocelot-wahoo.ts.net:13443", "interval": 300},
        ],
        "media": [
            {"name": "Jellyfin", "type": MonitorType.HTTP, "url": f"http://{H}:8096/health", "interval": 120,
             "keyword": "Healthy"},
            {"name": "Jellyseerr", "type": MonitorType.HTTP, "url": f"http://{H}:5055/api/v1/status", "interval": 120},
            {"name": "Sonarr", "type": MonitorType.HTTP, "url": f"http://{H}:8989/sonarr/ping", "interval": 120},
            {"name": "Radarr", "type": MonitorType.HTTP, "url": f"http://{H}:7878/radarr/ping", "interval": 120},
            {"name": "Lidarr", "type": MonitorType.HTTP, "url": f"http://{H}:8686/lidarr/ping", "interval": 120},
            {"name": "Readarr", "type": MonitorType.HTTP, "url": f"http://{H}:8787/readarr/ping", "interval": 120},
            {"name": "Prowlarr", "type": MonitorType.HTTP, "url": f"http://{H}:9696/prowlarr/ping", "interval": 120},
            {"name": "Navidrome", "type": MonitorType.HTTP, "url": f"http://{H}:4533/ping", "interval": 120},
            {"name": "Audiobookshelf", "type": MonitorType.HTTP, "url": f"http://{H}:13378/healthcheck", "interval": 120},
            {"name": "SABnzbd", "type": MonitorType.HTTP, "url": f"http://{H}:8081/", "interval": 120},
            {"name": "qBittorrent", "type": MonitorType.HTTP, "url": f"http://{H}:8080/", "interval": 120},
            {"name": "slskd", "type": MonitorType.HTTP, "url": f"http://{H}:5031/", "interval": 120},
            {"name": "Pinchflat", "type": MonitorType.HTTP, "url": f"http://{H}:8945/", "interval": 120},
            {"name": "Organizr", "type": MonitorType.HTTP, "url": f"http://{H}:9983/", "interval": 300},
            {"name": "LazyLibrarian", "type": MonitorType.HTTP, "url": f"http://{H}:5299/books", "interval": 120},
            {"name": "Calibre Desktop", "type": MonitorType.HTTP, "url": f"http://{H}:8083/", "interval": 300},
            {"name": "Calibre Content Server", "type": MonitorType.HTTP, "url": f"http://{H}:8090/", "interval": 300},
            {"name": "Mousehole", "type": MonitorType.HTTP, "url": f"http://{H}:5010/", "interval": 300,
             "accepted_statuscodes": ["200-299", "300-399"]},
            {"name": "Gluetun VPN", "type": MonitorType.HTTP, "url": f"http://{H}:8000/v1/publicip/ip", "interval": 120,
             "keyword": "public_ip"},
        ],
        "home": [
            {"name": "Frigate NVR", "type": MonitorType.HTTP, "url": f"http://{H}:5001/", "interval": 60, "critical": True},
            {"name": "Immich", "type": MonitorType.HTTP, "url": f"http://{H}:2283/api/server/ping", "interval": 60,
             "keyword": "pong"},
            {"name": "Immich Redis", "type": MonitorType.PORT, "hostname": H, "port": 6380, "interval": 120},
            {"name": "Immich ML", "type": MonitorType.DOCKER, "docker_container": "immich-machine-learning",
             "docker_host": None, "interval": 120},
            {"name": "CouchDB", "type": MonitorType.HTTP, "url": f"http://{H}:5984/", "interval": 120,
             "accepted_statuscodes": ["200-299", "400-499"]},
            {"name": "ntfy", "type": MonitorType.HTTP, "url": f"http://{H}:2586/v1/health", "interval": 60, "critical": True},
        ],
        "ai": [
            {"name": "Ollama", "type": MonitorType.HTTP, "url": f"http://{H}:11434/", "interval": 120},
            {"name": "Open WebUI", "type": MonitorType.HTTP, "url": f"http://{H}:3001/health", "interval": 120},
            {"name": "AI Router", "type": MonitorType.HTTP, "url": f"http://{H}:11435/", "interval": 120},
            {"name": "AI Agent", "type": MonitorType.HTTP, "url": f"http://{H}:6020/", "interval": 120},
            {"name": "Workflows API", "type": MonitorType.HTTP, "url": f"http://{H}:6021/", "interval": 120},
            {"name": "NanoClaw", "type": MonitorType.DOCKER, "docker_container": "nanoclaw",
             "docker_host": None, "interval": 300},
        ],
        "internal": [
            {"name": "Soularr", "type": MonitorType.DOCKER, "docker_container": "soularr",
             "docker_host": None, "interval": 300},
            {"name": "Homepage", "type": MonitorType.HTTP, "url": f"http://{H}:3080/", "interval": 300},
            {"name": "cAdvisor", "type": MonitorType.DOCKER, "docker_container": "cadvisor",
             "docker_host": None, "interval": 300},
            {"name": "Exportarr Sonarr", "type": MonitorType.DOCKER, "docker_container": "exportarr-sonarr",
             "docker_host": None, "interval": 300},
            {"name": "Exportarr Radarr", "type": MonitorType.DOCKER, "docker_container": "exportarr-radarr",
             "docker_host": None, "interval": 300},
            {"name": "Exportarr Lidarr", "type": MonitorType.DOCKER, "docker_container": "exportarr-lidarr",
             "docker_host": None, "interval": 300},
            {"name": "Exportarr Prowlarr", "type": MonitorType.DOCKER, "docker_container": "exportarr-prowlarr",
             "docker_host": None, "interval": 300},
            {"name": "Samba", "type": MonitorType.PORT, "hostname": H, "port": 445, "interval": 300},
            {"name": "NFS", "type": MonitorType.PORT, "hostname": H, "port": 2049, "interval": 300},
        ],
    }


# ---------------------------------------------------------------------------
# Setup functions
# ---------------------------------------------------------------------------

def setup_notification(api):
    """Create ntfy notification provider. Returns notification ID."""
    existing = api.get_notifications()
    for n in existing:
        if n.get("name") == "ntfy-monitoring":
            print(f"  Notification 'ntfy-monitoring' already exists (id={n['id']})")
            return n["id"]

    result = api.add_notification(
        name="ntfy-monitoring",
        type="ntfy",
        isDefault=True,
        applyExisting=True,
        ntfyserverurl=f"http://{H}:2586",
        ntfytopic="monitoring",
        ntfyPriority=3,  # default priority
    )
    nid = result["id"]
    print(f"  Created notification 'ntfy-monitoring' (id={nid})")
    return nid


def setup_tags(api):
    """Create tags and return {name: id} mapping."""
    tag_colors = {
        "infrastructure": "#6c757d",
        "business": "#0d6efd",
        "media": "#6f42c1",
        "home": "#198754",
        "ai": "#fd7e14",
        "critical": "#dc3545",
        "internal": "#495057",
    }
    existing = api.get_tags()
    tag_map = {}
    for t in existing:
        if t["name"] in tag_colors:
            tag_map[t["name"]] = t["id"]

    for name, color in tag_colors.items():
        if name in tag_map:
            print(f"  Tag '{name}' already exists (id={tag_map[name]})")
            continue
        result = api.add_tag(name=name, color=color)
        tag_map[name] = result["id"]
        print(f"  Created tag '{name}' (id={result['id']})")

    return tag_map


def get_docker_host_id(api):
    """Get or create the Docker host for Podman socket monitoring."""
    hosts = api.get_docker_hosts()
    for h in hosts:
        if h.get("name") == "podman-local":
            print(f"  Docker host 'podman-local' already exists (id={h['id']})")
            return h["id"]

    result = api.add_docker_host(
        name="podman-local",
        dockerType="socket",
        dockerDaemon="/var/run/docker.sock",
    )
    host_id = result["id"]
    print(f"  Created Docker host 'podman-local' (id={host_id})")
    return host_id


def create_monitors(api, notification_id, tag_map, docker_host_id):
    """Create all monitors with notification and tags."""
    monitors = get_monitors()

    # Get existing monitors to avoid duplicates
    existing = {m["name"]: m["id"] for m in api.get_monitors()}

    created = 0
    skipped = 0

    for group_name, group_monitors in monitors.items():
        print(f"\n  [{group_name}]")
        for mon in group_monitors:
            name = mon["name"]

            if name in existing:
                print(f"    {name}: already exists (id={existing[name]}), skipping")
                skipped += 1
                continue

            # Build monitor params
            params = {
                "type": mon["type"],
                "name": name,
                "interval": mon.get("interval", 120),
                "retryInterval": mon.get("retry_interval", 60),
                "maxretries": mon.get("max_retries", 3),
                "notificationIDList": {notification_id: True},
            }

            if mon["type"] == MonitorType.HTTP:
                params["url"] = mon["url"]
                if "keyword" in mon:
                    params["type"] = MonitorType.KEYWORD
                    params["keyword"] = mon["keyword"]
                if "accepted_statuscodes" in mon:
                    params["accepted_statuscodes"] = mon["accepted_statuscodes"]
            elif mon["type"] == MonitorType.PORT:
                params["hostname"] = mon["hostname"]
                params["port"] = mon["port"]
            elif mon["type"] == MonitorType.DOCKER:
                params["docker_container"] = mon["docker_container"]
                params["docker_host"] = docker_host_id

            result = api.add_monitor(**params)
            monitor_id = result["monitorID"]

            # Assign group tag
            if group_name in tag_map:
                api.add_monitor_tag(tag_id=tag_map[group_name], value="", monitor_id=monitor_id)

            # Assign critical tag if marked
            if mon.get("critical") and "critical" in tag_map:
                api.add_monitor_tag(tag_id=tag_map["critical"], value="", monitor_id=monitor_id)

            print(f"    {name}: created (id={monitor_id})")
            created += 1

            # Small delay to avoid overwhelming the socket
            time.sleep(0.1)

    print(f"\n  Summary: {created} created, {skipped} skipped (already existed)")
    return created


def create_status_page(api, tag_map):
    """Create a status page with grouped sections."""
    slug = "hwc-server"
    title = "hwc-server Status"

    try:
        existing = api.get_status_pages()
        for sp in existing:
            if sp.get("slug") == slug:
                print(f"  Status page '{slug}' already exists, skipping")
                return
    except Exception:
        pass

    # Get all monitors to build groups
    all_monitors = api.get_monitors()
    monitor_by_name = {m["name"]: m for m in all_monitors}

    monitors_def = get_monitors()

    # Build public group list for status page
    public_group_list = []
    group_order = ["infrastructure", "business", "media", "home", "ai", "internal"]
    group_titles = {
        "infrastructure": "Infrastructure",
        "business": "Business Apps",
        "media": "Media Services",
        "home": "Home & IoT",
        "ai": "AI Services",
        "internal": "Internal/Background",
    }

    for group_name in group_order:
        group_monitors = monitors_def.get(group_name, [])
        monitor_list = []
        for mon in group_monitors:
            if mon["name"] in monitor_by_name:
                monitor_list.append({"id": monitor_by_name[mon["name"]]["id"]})

        if monitor_list:
            public_group_list.append({
                "name": group_titles.get(group_name, group_name.title()),
                "weight": group_order.index(group_name),
                "monitorList": monitor_list,
            })

    api.add_status_page(slug=slug, title=title)
    api.save_status_page(
        slug=slug,
        publicGroupList=public_group_list,
        showPoweredBy=False,
    )
    print(f"  Created status page: /{slug}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    args = parse_args()

    print(f"Connecting to {args.url}...")
    api = UptimeKumaApi(args.url)

    try:
        api.login(args.username, args.password)
        print("Logged in successfully.\n")

        print("Setting up notification...")
        notification_id = setup_notification(api)

        print("\nSetting up tags...")
        tag_map = setup_tags(api)

        print("\nSetting up Docker host for container monitors...")
        docker_host_id = get_docker_host_id(api)

        print("\nCreating monitors...")
        create_monitors(api, notification_id, tag_map, docker_host_id)

        print("\nCreating status page...")
        create_status_page(api, tag_map)

        print("\nDone! Verify at the Uptime Kuma web UI.")

    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        api.disconnect()


if __name__ == "__main__":
    main()
