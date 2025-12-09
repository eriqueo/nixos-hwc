#!/usr/bin/env python3
import os
import sys
import json
import shutil
import subprocess
from pathlib import Path
import fnmatch
import re

def run(cmd, check=False, capture=True):
    try:
        p = subprocess.run(cmd, shell=True, check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return {'rc': p.returncode, 'out': p.stdout.strip(), 'err': p.stderr.strip()}
    except Exception as e:
        return {'rc': 99, 'out': '', 'err': str(e)}

def which(prog):
    return shutil.which(prog) is not None

# helpers
HOME = str(Path.home())
OUTPATH = os.environ.get("HWC_SUMMARY_OUT", os.path.join(HOME, "hwc_system_summary.json"))
NIX_REPO_ENV = os.environ.get("NIXOS_HWC_REPO", "").strip()

# find repo
def find_repo():
    candidates = []
    if NIX_REPO_ENV:
        candidates.append(NIX_REPO_ENV)
    candidates += [
        os.path.join(HOME, "nixos-hwc"),
        os.path.join(HOME, ".nixos"),
        os.path.join(HOME, "code", "nixos-hwc"),
        os.path.join(HOME, "workspace", "nixos-hwc"),
        "/etc/nixos",
        "/srv/nixos-hwc",
        "/opt/nixos-hwc",
        os.path.join(HOME, "projects", "nixos-hwc")
    ]
    for d in candidates:
        if d and os.path.isdir(d) and (os.path.exists(os.path.join(d, "CHARTER.md")) or os.path.exists(os.path.join(d, "flake.nix"))):
            return os.path.abspath(d)
    # last resort: scan home for CHARTER.md limited depth
    for root, dirs, files in os.walk(HOME):
        if "CHARTER.md" in files:
            return os.path.abspath(root)
        # avoid very deep recursion on typical home dirs
        if root.count(os.sep) - HOME.count(os.sep) > 4:
            dirs[:] = []
    return None

repo = find_repo()

# machine / basic info
hostname = run("hostnamectl --static")['out'] or run("hostname")['out']
os_info = run("hostnamectl | awk -F: '/Operating System/ {print substr($0, index($0,$2))}'")['out'] or ""
uptime = run("uptime -p")['out'] or ""
kernel = run("uname -r")['out'] or ""
uname = run("uname -a")['out'] or ""

# repo-linked machine check
in_repo = False
machine_role_hint = ""
if repo:
    machine_dir = os.path.join(repo, "machines", hostname)
    if os.path.isdir(machine_dir):
        in_repo = True
        # try read README or config for role hint
        for fname in ("README.md", "README", "config.nix", "home.nix"):
            p = os.path.join(machine_dir, fname)
            if os.path.exists(p):
                try:
                    with open(p, "r", errors="ignore") as f:
                        text = f.read(4096)
                        # take first paragraph or comment lines
                        lines = [l.strip() for l in text.splitlines() if l.strip()]
                        if lines:
                            machine_role_hint = " ".join(lines[:3])
                            break
                except Exception:
                    continue

# container strategy detection
podman_installed = which("podman")
docker_installed = which("docker")
podman_containers = []
podman_running = False
if podman_installed:
    r = run("podman ps --format json")
    if r['rc'] == 0 and r['out']:
        try:
            podman_containers = json.loads(r['out'])
            podman_running = len(podman_containers) > 0
        except Exception:
            podman_containers = []
    else:
        # try fallback
        r2 = run("podman ps -a --format json")
        if r2['rc'] == 0 and r2['out']:
            try:
                podman_containers = json.loads(r2['out'])
                podman_running = len(podman_containers) > 0
            except Exception:
                podman_containers = []

# docker-compose presence (repo scan + /opt)
docker_compose_files = []
if repo:
    for root, dirs, files in os.walk(repo):
        for f in files:
            if f in ("docker-compose.yml", "docker-compose.yaml"):
                docker_compose_files.append(os.path.join(root, f))
# also search /opt and /srv quickly
for base in ("/opt", "/srv", "/home"):
    for root, dirs, files in os.walk(base):
        for f in files:
            if f in ("docker-compose.yml", "docker-compose.yaml"):
                docker_compose_files.append(os.path.join(root, f))
        # avoid scanning system deeply
        if root.count(os.sep) > 6:
            dirs[:] = []

# nix-native container indicators in repo
nix_has_oci = False
canonical_container_dirs = []
if repo:
    # look for virtualisation.oci-containers or hwc.server containers
    r = run(f"rg -n --hidden -S \"virtualisation.oci-containers|virtualisation\\.oci-containers|hwc\\.server\\.containers|containers =\" {repo} 2>/dev/null")
    if r['rc'] == 0 and r['out']:
        nix_has_oci = True
        # extract directories near matches
        lines = [l for l in r['out'].splitlines() if l.strip()]
        dirs = set()
        for line in lines[:200]:
            m = re.split(r":\d+", line)[0]
            dirs.add(os.path.dirname(m))
        canonical_container_dirs = sorted(list(dirs))

# secrets system state
agenix_installed = which("agenix")
sops_installed = which("sops")
run_agenix_exists = os.path.isdir("/run/agenix")
age_key_exists = os.path.exists("/etc/age/keys.txt")
domains_secrets_dir = os.path.join(repo, "domains", "secrets") if repo else None
sops_config_files = []
if repo:
    for root, dirs, files in os.walk(repo):
        for f in files:
            if f == ".sops.yaml" or f.endswith(".sops.yaml") or f.endswith(".sops.yml"):
                sops_config_files.append(os.path.join(root, f))

# filesystems & storage (zfs)
zfs_available = which("zpool") and which("zfs")
zpools = []
zpool_details = {}
lsblk = {}
if zfs_available:
    zpl = run("zpool list -H -o name")
    if zpl['rc'] == 0 and zpl['out']:
        for p in zpl['out'].splitlines():
            pool = p.strip()
            if not pool:
                continue
            zpools.append(pool)
            status = run(f"zpool status -v {pool}")
            zfs_list = run(f"zfs list -t all -o name,used,available,refer,mountpoint,compressratio -r {pool}")
            # parse zfs_list into rows
            datasets = []
            if zfs_list['rc'] == 0 and zfs_list['out']:
                for ln in zfs_list['out'].splitlines():
                    parts = re.split(r'\s+', ln.strip(), maxsplit=5)
                    if len(parts) >= 6:
                        name, used, avail, refer, mountpoint, compressratio = parts[:6]
                    elif len(parts) >= 5:
                        name, used, avail, refer, mountpoint = parts[:5]
                        compressratio = ""
                    else:
                        continue
                    datasets.append({
                        "name": name,
                        "used": used,
                        "available": avail,
                        "refer": refer,
                        "mountpoint": mountpoint,
                        "compressratio": compressratio
                    })
            zpool_details[pool] = {
                "status": status['out'],
                "datasets": datasets
            }
# lsblk
if which("lsblk"):
    lb = run("lsblk -J -o NAME,SIZE,TYPE,MOUNTPOINT")
    if lb['rc'] == 0 and lb['out']:
        try:
            lsblk = json.loads(lb['out'])
        except Exception:
            lsblk = {"raw": lb['out']}

# heuristic: find datasets that look like docker/podman/media/backups
dataset_tags = {}
if zfs_available and zpool_details:
    for pool, info in zpool_details.items():
        for ds in info.get("datasets", []):
            name = ds.get("name", "")
            tags = []
            lname = name.lower()
            for k in ("docker", "podman", "containers", "volumes", "media", "backup", "backups", "immich", "jellyfin", "frigate"):
                if k in lname:
                    tags.append(k)
            if tags:
                dataset_tags[name] = tags

# core workloads: systemd services + podman containers
services_of_interest = ["frigate", "caddy", "tailscaled", "home-assistant", "jellyfin", "immich", "postgresql", "postgres", "sabnzbd", "qbittorrent", "sonarr", "radarr", "lidarr", "mosquitto", "nginx", "docker", "podman"]
service_states = {}
for svc in services_of_interest:
    r_active = run(f"systemctl is-active {svc} 2>/dev/null")
    r_enabled = run(f"systemctl is-enabled {svc} 2>/dev/null")
    service_states[svc] = {"active": r_active['out'] if r_active['out'] else r_active['err'], "enabled": r_enabled['out'] if r_enabled['out'] else r_enabled['err']}

# podman containers summary
podman_summary = []
if podman_installed:
    try:
        if isinstance(podman_containers, list):
            for c in podman_containers:
                podman_summary.append({
                    "Id": c.get("Id"),
                    "Names": c.get("Names"),
                    "Image": c.get("Image"),
                    "Command": c.get("Command"),
                    "State": c.get("State"),
                    "Status": c.get("Status"),
                    "Ports": c.get("Ports")
                })
    except Exception:
        podman_summary = []

# canonical server modules (domains/server)
server_modules = []
if repo:
    server_dir = os.path.join(repo, "domains", "server")
    if os.path.isdir(server_dir):
        for entry in sorted(os.listdir(server_dir)):
            p = os.path.join(server_dir, entry)
            if os.path.isdir(p):
                # note presence of index.nix or config dir
                has_index = os.path.exists(os.path.join(p, "index.nix"))
                has_config_dir = os.path.isdir(os.path.join(p, "config"))
                server_modules.append({"name": entry, "path": p, "index.nix": has_index, "config_dir": has_config_dir})

# frozen vs experimental / repo refactor phase extraction (CHARTER.md)
charter_status = {}
if repo:
    charter_path = os.path.join(repo, "CHARTER.md")
    if os.path.exists(charter_path):
        try:
            with open(charter_path, "r", errors="ignore") as f:
                charter = f.read()
            # find "Status" section and Phase lines
            phases = []
            for ln in charter.splitlines():
                m = re.match(r".*Phase\s*([0-9]+)[^\:]*[:\s]*([^\n\r]+)", ln)
                if m:
                    phases.append({"phase": m.group(1), "status": m.group(2).strip()})
            # fallback: look for lines like "Phase 1 (...)"
            if not phases:
                for ln in charter.splitlines():
                    if "Phase" in ln and ("complete" in ln.lower() or "in progress" in ln.lower() or "pending" in ln.lower()):
                        phases.append({"line": ln.strip()})
            charter_status = {"found": True, "phases": phases, "excerpt": "\n".join(charter.splitlines()[:200])}
        except Exception as e:
            charter_status = {"found": False, "err": str(e)}
    else:
        charter_status = {"found": False}

# assemble result
result = {
    "machine": {
        "hostname": hostname,
        "os_info": os_info,
        "uptime": uptime,
        "kernel": kernel,
        "uname": uname,
        "in_repo": in_repo,
        "machine_role_hint": machine_role_hint
    },
    "repo": {
        "path": repo,
        "server_modules_count": len(server_modules),
        "server_modules": server_modules[:200]  # cap
    },
    "container_strategy": {
        "podman_installed": podman_installed,
        "podman_running_containers": podman_running,
        "podman_containers": podman_summary[:200],
        "docker_installed": docker_installed,
        "docker_compose_files": docker_compose_files[:200],
        "nix_uses_oci_virtualisation": nix_has_oci,
        "canonical_container_dirs": canonical_container_dirs[:200]
    },
    "secrets": {
        "agenix_installed": agenix_installed,
        "sops_installed": sops_installed,
        "run_agenix_exists": run_agenix_exists,
        "age_key_exists": age_key_exists,
        "domains_secrets_dir": domains_secrets_dir,
        "sops_config_files": sops_config_files[:200]
    },
    "storage": {
        "zfs_available": bool(zfs_available),
        "zpools": zpools,
        "zpool_details": zpool_details,
        "lsblk": lsblk,
        "dataset_tags": dataset_tags
    },
    "core_workloads": {
        "service_states": service_states,
        "podman_containers": podman_summary[:200],
        "server_modules": server_modules[:200]
    },
    "charter": charter_status
}

# write file
try:
    with open(OUTPATH, "w") as f:
        json.dump(result, f, indent=2)
    print(f"Summary written to {OUTPATH}")
    print(json.dumps(result, indent=2))
except Exception as e:
    print("Failed to write output:", e, file=sys.stderr)
    sys.exit(2)
