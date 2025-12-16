# domains/server/ai/local-workflows/parts/journaling.nix
#
# Automatic system event journaling with AI summaries

{ config, lib, pkgs, cfg }:

let
  journalingScript = pkgs.writers.writePython3Bin "ai-journal" {
    libraries = with pkgs.python3Packages; [ requests pyyaml ];
  } ''
import json
import subprocess
from pathlib import Path
from datetime import datetime, timedelta
import requests


# Configuration
OLLAMA_ENDPOINT = "${cfg.ollamaEndpoint}"
MODEL = "${cfg.journaling.model}"
OUTPUT_DIR = "${cfg.journaling.outputDir}"
SOURCES = json.loads('${builtins.toJSON cfg.journaling.sources}')
LOG_DIR = "${cfg.logDir}"


def log(message, level="INFO"):
    """Log to file and stdout"""
    timestamp = datetime.now().isoformat()
    log_line = f"[{timestamp}] [{level}] {message}"
    print(log_line)

    log_file = Path(LOG_DIR) / "journaling.log"
    log_file.parent.mkdir(parents=True, exist_ok=True)
    with open(log_file, "a") as f:
        f.write(log_line + "\\n")


def query_ollama(prompt, max_tokens=2000):
    """Query Ollama API for summarization"""
    try:
        response = requests.post(
            f"{OLLAMA_ENDPOINT}/api/generate",
            json={
                "model": MODEL,
                "prompt": prompt,
                "stream": False,
                "options": {
                    "temperature": 0.3,
                    "num_predict": max_tokens
                }
            },
            timeout=120
        )
        response.raise_for_status()
        return response.json()["response"].strip()
    except Exception as e:
        log(f"Error querying Ollama: {e}", "ERROR")
        return None


def get_systemd_events(since_hours=24):
    """Get systemd journal events from last N hours"""
    try:
        since = datetime.now() - timedelta(hours=since_hours)
        since_str = since.strftime("%Y-%m-%d %H:%M:%S")

        result = subprocess.run(
            [
                "journalctl",
                "--since", since_str,
                "--priority=warning",
                "-o", "json"
            ],
            capture_output=True,
            text=True,
            check=True
        )

        events = []
        for line in result.stdout.strip().split("\\n"):
            if not line:
                continue
            try:
                event = json.loads(line)
                events.append({
                    "timestamp": event.get(
                        "__REALTIME_TIMESTAMP", ""
                    ),
                    "unit": event.get("SYSLOG_IDENTIFIER", "system"),
                    "message": event.get("MESSAGE", ""),
                    "priority": event.get("PRIORITY", "6")
                })
            except json.JSONDecodeError:
                continue

        return events
    except Exception as e:
        log(f"Error getting systemd events: {e}", "ERROR")
        return []


def get_container_events(since_hours=24):
    """Get Podman container events"""
    try:
        result = subprocess.run(
            ["podman", "ps", "--all", "--format", "json"],
            capture_output=True,
            text=True,
            check=True
        )

        containers = json.loads(result.stdout)
        events = []

        for container in containers:
            name = container.get("Names", ["unknown"])[0]
            state = container.get("State", "unknown")
            status = container.get("Status", "unknown")

            events.append({
                "container": name,
                "state": state,
                "status": status
            })

        return events
    except Exception as e:
        log(f"Error getting container events: {e}", "ERROR")
        return []


def get_nixos_rebuild_events():
    """Get recent NixOS rebuild information"""
    try:
        # Check for recent builds in systemd journal
        result = subprocess.run(
            [
                "journalctl",
                "-u", "nixos-rebuild",
                "--since", "24 hours ago",
                "-o", "cat"
            ],
            capture_output=True,
            text=True,
            check=False
        )

        if result.returncode == 0 and result.stdout.strip():
            return [{
                "event": "nixos-rebuild",
                "output": result.stdout[:1000]
            }]

        # Alternative: check nix store for recent builds
        result = subprocess.run(
            [
                "nix", "profile", "history",
                "--profile", "/nix/var/nix/profiles/system"
            ],
            capture_output=True,
            text=True,
            check=False
        )

        if result.returncode == 0:
            return [{
                "event": "system-generations",
                "output": result.stdout[:500]
            }]

        return []
    except Exception as e:
        log(f"Error getting NixOS rebuild events: {e}", "ERROR")
        return []


def collect_events():
    """Collect events from all configured sources"""
    all_events = {}

    if "systemd-journal" in SOURCES:
        log("Collecting systemd journal events...")
        all_events["systemd"] = get_systemd_events()

    if "container-logs" in SOURCES:
        log("Collecting container events...")
        all_events["containers"] = get_container_events()

    if "nixos-rebuilds" in SOURCES:
        log("Collecting NixOS rebuild events...")
        all_events["nixos"] = get_nixos_rebuild_events()

    return all_events


def format_events_for_ai(events):
    """Format collected events for AI summarization"""
    formatted = []

    # Systemd events
    if "systemd" in events and events["systemd"]:
        formatted.append("## System Events (Warnings & Errors)")
        for event in events["systemd"][:50]:
            unit = event.get("unit", "unknown")
            msg = event.get("message", "")[:200]
            formatted.append(f"- [{unit}] {msg}")

    # Container events
    if "containers" in events and events["containers"]:
        formatted.append("\\n## Container Status")
        for event in events["containers"]:
            name = event.get("container", "unknown")
            state = event.get("state", "unknown")
            status = event.get("status", "unknown")
            formatted.append(f"- {name}: {state} ({status})")

    # NixOS events
    if "nixos" in events and events["nixos"]:
        formatted.append("\\n## NixOS Rebuilds")
        for event in events["nixos"]:
            output = event.get("output", "")[:500]
            formatted.append(f"```\\n{output}\\n```")

    return "\\n".join(formatted)


def generate_journal_entry(events_text):
    """Use AI to generate a journal entry"""
    today = datetime.now().strftime("%Y-%m-%d")

    prompt = (
        f"You are a system administrator's AI assistant. "
        f"Generate a concise daily journal entry summarizing "
        f"the following system events for {today}.\\n\\n"
        "Format your response as a markdown journal entry "
        "with:\\n"
        "1. A brief executive summary (2-3 sentences)\\n"
        "2. Notable events by category\\n"
        "3. Any issues requiring attention\\n"
        "4. System health status\\n\\n"
        "Be concise and actionable. "
        "Focus on anomalies and important events.\\n\\n"
        f"# System Events\\n\\n{events_text}\\n\\n"
        "# Your Journal Entry:\\n"
    )

    log("Generating AI summary...")
    summary = query_ollama(prompt, max_tokens=1500)

    if not summary:
        summary = f"# System Journal - {today}\\n\\n{events_text}"

    return summary


def save_journal_entry(content):
    """Save journal entry to file"""
    today = datetime.now().strftime("%Y-%m-%d")
    output_dir = Path(OUTPUT_DIR)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Save daily entry
    daily_file = output_dir / f"{today}.md"
    with open(daily_file, "w") as f:
        f.write(content)

    log(f"Journal saved: {daily_file}")

    # Update index
    index_file = output_dir / "README.md"
    update_index(index_file, today)


def update_index(index_file, today):
    """Update journal index with new entry"""
    entries = []

    if index_file.exists():
        with open(index_file) as f:
            content = f.read()
            for line in content.split("\\n"):
                if line.startswith("- ["):
                    entries.append(line)

    # Add today's entry
    new_entry = f"- [{today}](./{today}.md)"
    if new_entry not in entries:
        entries.insert(0, new_entry)

    # Keep only recent entries
    entries = entries[:90]

    # Write index
    with open(index_file, "w") as f:
        f.write("# HWC AI System Journal\\n\\n")
        f.write("Automated daily summaries of system events.\\n\\n")
        f.write("## Recent Entries\\n\\n")
        f.write("\\n".join(entries))


def main():
    """Main journaling routine"""
    log("Starting AI journaling...")

    # Collect events
    events = collect_events()

    if not any(events.values()):
        log("No events to journal", "WARN")
        return

    # Format for AI
    events_text = format_events_for_ai(events)

    # Generate summary
    journal_entry = generate_journal_entry(events_text)

    # Save
    save_journal_entry(journal_entry)

    log("Journaling complete")


if __name__ == "__main__":
    main()
  '';

  # Determine systemd timer schedule
  timerSchedule =
    if cfg.journaling.schedule == "daily" then
      "*-*-* ${cfg.journaling.timeOfDay}:00"
    else if cfg.journaling.schedule == "weekly" then
      "Mon *-*-* ${cfg.journaling.timeOfDay}:00"
    else
      cfg.journaling.schedule;
in
{
  # Create output directory
  systemd.tmpfiles.rules = [
    "d ${cfg.journaling.outputDir} 0755 eric users -"
  ];

  # Install journaling script
  environment.systemPackages = [ journalingScript ];

  # Systemd service
  systemd.services.ai-journal = {
    description = "AI-powered system event journaling";
    after = [ "network-online.target" "podman-ollama.service" ];
    wants = [ "network-online.target" "podman-ollama.service" ];
    path = with pkgs; [ podman nix systemd ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${journalingScript}/bin/ai-journal";
      User = lib.mkForce "eric";
      Group = lib.mkForce "users";
      Restart = "on-failure";
    };
  };

  # Systemd timer
  systemd.timers.ai-journal = {
    description = "AI journaling timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = timerSchedule;
      Persistent = true;
    };
  };
}
