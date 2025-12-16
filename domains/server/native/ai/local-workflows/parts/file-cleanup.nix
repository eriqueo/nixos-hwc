# domains/server/ai/local-workflows/parts/file-cleanup.nix
#
# AI-powered file cleanup and organization agent

{ config, lib, pkgs, cfg }:

let
  cleanupScript = pkgs.writers.writePython3Bin "ai-cleanup" {
    libraries = with pkgs.python3Packages; [ requests pyyaml ];
  } ''
import json
import shutil
from pathlib import Path
from datetime import datetime
import requests

# Configuration
OLLAMA_ENDPOINT = "${cfg.ollamaEndpoint}"
MODEL = "${cfg.fileCleanup.model}"
WATCH_DIRS = json.loads('${builtins.toJSON cfg.fileCleanup.watchDirs}')
RULES_DIR = "${cfg.fileCleanup.rulesDir}"
LOG_DIR = "${cfg.logDir}"
DRY_RUN = ${if cfg.fileCleanup.dryRun then "True" else "False"}


def log(message, level="INFO"):
    """Log to both stdout and file"""
    timestamp = datetime.now().isoformat()
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line)

    log_file = Path(LOG_DIR) / "file-cleanup.log"
    log_file.parent.mkdir(parents=True, exist_ok=True)
    with open(log_file, "a") as f:
        f.write(log_line + "\n")


def query_ollama(prompt, context=""):
    """Query Ollama API for file categorization"""
    try:
        response = requests.post(
            f"{OLLAMA_ENDPOINT}/api/generate",
            json={
                "model": MODEL,
                "prompt": prompt,
                "context": context,
                "stream": False,
                "options": {
                    "temperature": 0.1,
                    "top_p": 0.9,
                }
            },
            timeout=30
        )
        response.raise_for_status()
        return response.json()["response"].strip()
    except Exception as e:
        log(f"Error querying Ollama: {e}", "ERROR")
        return None


def load_rules():
    """Load organization rules from YAML or use defaults"""
    rules_file = Path(RULES_DIR) / "cleanup-rules.yaml"

    default_rules = {
        "documents": {
            "extensions": [".pdf", ".doc", ".docx", ".txt", ".md", ".odt"],
            "destination": "Documents"
        },
        "images": {
            "extensions": [".jpg", ".jpeg", ".png", ".gif", ".svg", ".webp"],
            "destination": "Pictures"
        },
        "videos": {
            "extensions": [".mp4", ".mkv", ".avi", ".mov", ".webm"],
            "destination": "Videos"
        },
        "audio": {
            "extensions": [".mp3", ".flac", ".wav", ".ogg", ".m4a"],
            "destination": "Music"
        },
        "archives": {
            "extensions": [".zip", ".tar", ".gz", ".7z", ".rar"],
            "destination": "Archives"
        },
        "code": {
            "extensions": [".py", ".nix", ".sh", ".js", ".ts", ".rs", ".go"],
            "destination": "Code"
        }
    }

    if rules_file.exists():
        import yaml
        with open(rules_file) as f:
            return yaml.safe_load(f)

    rules_file.parent.mkdir(parents=True, exist_ok=True)
    with open(rules_file, "w") as f:
        import yaml
        yaml.dump(default_rules, f)

    return default_rules


def categorize_file(file_path):
    """Use AI to categorize file if extension-based rules fail"""
    prompt = f"""Analyze this file and suggest a category folder:
File: {file_path.name}
Extension: {file_path.suffix}
Size: {file_path.stat().st_size} bytes

Categories: Documents, Pictures, Videos, Music, Archives, Code

Respond with ONLY the category name, nothing else."""

    category = query_ollama(prompt)
    return category if category else "Uncategorized"


def organize_files(watch_dir):
    """Organize files in a watch directory"""
    watch_path = Path(watch_dir)
    if not watch_path.exists():
        log(f"Watch directory does not exist: {watch_dir}", "WARN")
        return

    rules = load_rules()
    files_processed = 0

    for file_path in watch_path.iterdir():
        if file_path.is_dir():
            continue

        if file_path.name.startswith("."):
            continue

        age_seconds = datetime.now().timestamp() - file_path.stat().st_mtime
        if age_seconds < 300:
            log(f"Skipping recent file: {file_path.name}", "DEBUG")
            continue

        category = None
        for rule_name, rule_config in rules.items():
            if file_path.suffix.lower() in rule_config["extensions"]:
                category = rule_config["destination"]
                break

        if not category:
            log(f"Using AI to categorize: {file_path.name}", "INFO")
            category = categorize_file(file_path)

        dest_dir = watch_path / category
        dest_dir.mkdir(exist_ok=True)

        dest_file = dest_dir / file_path.name

        if dest_file.exists():
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            stem = file_path.stem
            suffix = file_path.suffix
            dest_file = dest_dir / f"{stem}_{timestamp}{suffix}"

        if DRY_RUN:
            msg = f"[DRY RUN] Would move: {file_path.name} -> {category}/"
            log(msg, "INFO")
        else:
            try:
                shutil.move(str(file_path), str(dest_file))
                log(f"Moved: {file_path.name} -> {category}/", "INFO")
                files_processed += 1
            except Exception as e:
                log(f"Error moving {file_path.name}: {e}", "ERROR")

    return files_processed


def main():
    """Main cleanup routine"""
    log(f"Starting AI file cleanup (model: {MODEL}, dry-run: {DRY_RUN})")

    total_processed = 0
    for watch_dir in WATCH_DIRS:
        log(f"Processing directory: {watch_dir}")
        try:
            count = organize_files(watch_dir)
            total_processed += count or 0
        except Exception as e:
            log(f"Error processing {watch_dir}: {e}", "ERROR")

    log(f"Cleanup complete. Files processed: {total_processed}")


if __name__ == "__main__":
    main()
  '';

  cleanupTimer = cfg.fileCleanup.schedule;
in
{
  # Create directories
  systemd.tmpfiles.rules = [
    "d ${cfg.fileCleanup.rulesDir} 0755 eric users -"
    "d ${cfg.logDir} 0755 eric users -"
  ];

  # Install cleanup script
  environment.systemPackages = [ cleanupScript ];

  # Systemd service
  systemd.services.ai-file-cleanup = {
    description = "AI-powered file cleanup and organization";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${cleanupScript}/bin/ai-cleanup";
      User = lib.mkForce "eric";
      Group = lib.mkForce "users";
    };
  };

  # Systemd timer
  systemd.timers.ai-file-cleanup = {
    description = "AI file cleanup timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = cleanupTimer;
      Persistent = true;
    };
  };
}
