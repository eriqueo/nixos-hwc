#!/usr/bin/env python3
"""
Wire sys:router:notify into n8n workflows.
Replaces dead ntfy nodes and Slack webhook nodes with Execute Sub-Workflow calls.

Usage: python3 wire-notify.py
Requires: N8N_API_KEY environment variable
"""

import json
import os
import sys
import urllib.request
import urllib.error
import copy
import uuid

API_BASE = "http://localhost:5678/api/v1"
NOTIFY_WORKFLOW_ID = "jR1mdRj1TnY0wN87"
WORKFLOWS_DIR = os.path.expanduser("~/.nixos/domains/automation/n8n/parts/workflows")

def api_key():
    """Read API key from agenix secret."""
    with open("/run/agenix/n8n-api-key") as f:
        return f.read().strip()

def api_get(path):
    req = urllib.request.Request(
        f"{API_BASE}{path}",
        headers={"X-N8N-API-KEY": api_key(), "Accept": "application/json"}
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

def api_put(path, data):
    body = json.dumps(data).encode()
    req = urllib.request.Request(
        f"{API_BASE}{path}",
        data=body,
        headers={
            "X-N8N-API-KEY": api_key(),
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="PUT",
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

def uid():
    return uuid.uuid4().hex[:16]

def make_notify_code_node(node_id, name, position, js_code):
    """Create a Code node that builds the taxonomy payload."""
    return {
        "id": node_id,
        "name": name,
        "type": "n8n-nodes-base.code",
        "typeVersion": 2,
        "position": position,
        "parameters": {"jsCode": js_code},
    }

def make_execute_subworkflow_node(node_id, name, position):
    """Create an Execute Sub-Workflow node pointing at sys:router:notify."""
    return {
        "id": node_id,
        "name": name,
        "type": "n8n-nodes-base.executeWorkflow",
        "typeVersion": 1.1,
        "position": position,
        "continueOnFail": True,
        "parameters": {
            "source": "database",
            "workflowId": NOTIFY_WORKFLOW_ID,
        },
    }

def find_node(nodes, name=None, node_id=None):
    for n in nodes:
        if name and n.get("name") == name:
            return n
        if node_id and n.get("id") == node_id:
            return n
    return None

def remove_node(wf, node_name):
    """Remove a node and its connections."""
    wf["nodes"] = [n for n in wf["nodes"] if n["name"] != node_name]
    wf["connections"].pop(node_name, None)
    # Remove connections TO this node
    for src, conns in list(wf["connections"].items()):
        for output_type, outputs in conns.items():
            for output_list in outputs:
                output_list[:] = [c for c in output_list if c["node"] != node_name]

def replace_node(wf, old_name, new_node):
    """Replace a node in-place, preserving incoming connections."""
    for i, n in enumerate(wf["nodes"]):
        if n["name"] == old_name:
            wf["nodes"][i] = new_node
            break
    # Update connections FROM old name
    if old_name in wf["connections"]:
        wf["connections"][new_node["name"]] = wf["connections"].pop(old_name)
    # Update connections TO old name
    for src, conns in wf["connections"].items():
        for output_type, outputs in conns.items():
            for output_list in outputs:
                for conn in output_list:
                    if conn["node"] == old_name:
                        conn["node"] = new_node["name"]

def add_node_after(wf, predecessor_name, new_node, output_index=0):
    """Add a new node connected after an existing node."""
    wf["nodes"].append(new_node)
    if predecessor_name not in wf["connections"]:
        wf["connections"][predecessor_name] = {"main": [[]]}
    main = wf["connections"][predecessor_name]["main"]
    while len(main) <= output_index:
        main.append([])
    main[output_index].append({
        "node": new_node["name"],
        "type": "main",
        "index": 0,
    })

def rewire_connection(wf, from_node, to_old, to_new, output_index=0):
    """Change a connection target from to_old to to_new."""
    if from_node in wf["connections"]:
        for conn in wf["connections"][from_node].get("main", [[]])[output_index]:
            if conn["node"] == to_old:
                conn["node"] = to_new

# ============================================================================
# WORKFLOW-SPECIFIC HANDLERS
# ============================================================================

def wire_mail_health(wf):
    """home:social:mail-health — replace Slack webhook with sys:router:notify"""
    # This workflow: webhook trigger → code (build alert) → HTTP POST to Slack
    # The code node builds {emoji, label, details, host, time, severity}
    # Replace the Slack HTTP POST with a code→execute pattern

    slack_node = find_node(wf["nodes"], name="Send a message")
    if not slack_node:
        print("  SKIP: 'Send a message' node not found")
        return False

    pos = slack_node["position"]

    # Build taxonomy payload code
    code = """// Build sys:router:notify payload from mail health data
const p = $input.first().json;
const severityMap = { 'CRITICAL': 'critical', 'WARNING': 'warning', 'OK': 'info' };
const severity = severityMap[p.severity] || severityMap[p.label] || 'warning';

return [{
  json: {
    universe: 'home',
    domain: 'admin',
    source: 'mail-health',
    category: 'infrastructure',
    severity: severity,
    summary: `Mail health ${p.label || p.severity}: ${p.details || 'check triggered'}`,
    timestamp: new Date().toISOString(),
    action_hint: severity === 'critical' ? 'restart-service' : 'none',
    metadata: {
      host: p.host || '',
      details: p.details || '',
      denver_time: p.time || ''
    }
  }
}];"""

    code_node = make_notify_code_node(
        uid(), "Build Notify Payload", [pos[0], pos[1]], code
    )
    exec_node = make_execute_subworkflow_node(
        uid(), "sys:router:notify", [pos[0] + 220, pos[1]]
    )

    # Replace send-slack with code node, then add exec after
    replace_node(wf, "Send a message", code_node)
    add_node_after(wf, code_node["name"], exec_node)

    print("  DONE: 'Send a message' → Build Notify Payload → sys:router:notify")
    return True


def wire_estimate_push(wf):
    """hwc:ops:jt:estimate-push — replace Slack webhook success/failure"""
    changed = False

    for old_name, sev, cat, summary_tpl in [
        ("Slack: Success", "info", "workflow",
         "Estimate pushed to JobTread: ${p.jobName || p.job_name || 'unknown'} (${p.itemsPushed || '?'} items)"),
        ("Slack: Failure", "warning", "workflow",
         "Estimate JT push FAILED: ${p.jobName || p.job_name || 'unknown'} — ${p.jtPushError || p.error || 'unknown error'}"),
    ]:
        node = find_node(wf["nodes"], name=old_name)
        if not node:
            print(f"  SKIP: {old_name} not found")
            continue

        pos = node["position"]
        code = f"""// Build sys:router:notify payload
const p = $input.first().json;
return [{{
  json: {{
    universe: 'hwc',
    domain: 'ops',
    source: 'estimate-router',
    category: '{cat}',
    severity: '{sev}',
    summary: `{summary_tpl}`,
    timestamp: new Date().toISOString(),
    action_hint: '{"retry-workflow" if sev == "warning" else "none"}',
    metadata: {{ ...p }}
  }}
}}];"""

        code_node = make_notify_code_node(uid(), f"Build Notify: {sev}", [pos[0], pos[1]], code)
        exec_node = make_execute_subworkflow_node(uid(), f"Notify: {old_name}", [pos[0] + 220, pos[1]])

        replace_node(wf, old_name, code_node)
        add_node_after(wf, code_node["name"], exec_node)
        changed = True
        print(f"  DONE: {old_name} → sys:router:notify ({sev})")

    return changed


def wire_frigate(wf):
    """home:security:frigate-detect — replace ntfy + slack + error-ntfy"""
    changed = False

    # Frigate has been heavily reworked in the UI — node names differ from repo.
    # Look for ntfy HTTP requests and Slack nodes by checking URL/type patterns.
    # From API: "Upload a file" (slack), "other" (slack), no ntfy nodes found by name.
    # The workflow may have already been partially migrated. Check for HTTP POST to ntfy.
    ntfy_nodes = [n for n in wf["nodes"]
                  if n.get("type") == "n8n-nodes-base.httpRequest"
                  and "ntfy" in json.dumps(n.get("parameters", {})).lower()]

    # 1. Replace ntfy HTTP request nodes
    node = ntfy_nodes[0] if ntfy_nodes else find_node(wf["nodes"], name="Send to ntfy")
    if node:
        pos = node["position"]
        code = """// Build sys:router:notify payload from Frigate detection
const p = $input.first().json;
const severityMap = { 5: 'critical', 4: 'warning', 3: 'info', 2: 'debug' };
const severity = severityMap[p.priority] || 'info';

return [{
  json: {
    universe: 'home',
    domain: 'security',
    source: 'frigate',
    category: 'detection',
    severity: severity,
    summary: p.title || p.message || 'Frigate detection event',
    timestamp: new Date().toISOString(),
    action_hint: severity === 'critical' ? 'escalate' : 'none',
    metadata: {
      camera: p.camera || '',
      object_type: p.object_type || p.label || '',
      confidence: p.confidence || 0,
      zone: p.zone || '',
      tags: p.tags || ''
    }
  }
}];"""
        code_node = make_notify_code_node(uid(), "Build Detect Notify", [pos[0], pos[1]], code)
        exec_node = make_execute_subworkflow_node(uid(), "Notify: Detection", [pos[0] + 220, pos[1]])
        replace_node(wf, node["name"], code_node)
        add_node_after(wf, code_node["name"], exec_node)
        changed = True
        print(f"  DONE: '{node['name']}' → sys:router:notify (detection)")

    # 2. Replace error-ntfy if exists
    error_nodes = [n for n in wf["nodes"]
                   if n.get("type") == "n8n-nodes-base.httpRequest"
                   and "error" in n.get("name", "").lower()
                   and "ntfy" in json.dumps(n.get("parameters", {})).lower()]
    node = error_nodes[0] if error_nodes else find_node(wf["nodes"], name="Send Error to ntfy")
    if node:
        pos = node["position"]
        code = """// Critical detection → already handled by router's Slack channel
// This node was a conditional Slack webhook for critical events.
// sys:router:notify now handles Slack routing via taxonomy channels.
const p = $input.first().json;
return [{
  json: {
    universe: 'home',
    domain: 'security',
    source: 'frigate',
    category: 'detection',
    severity: 'critical',
    summary: p.title || p.message || 'Critical Frigate detection',
    timestamp: new Date().toISOString(),
    action_hint: 'escalate',
    metadata: { critical: true, original_message: p.message || '' }
  }
}];"""
        code_node = make_notify_code_node(uid(), "Build Critical Notify", [pos[0], pos[1]], code)
        exec_node = make_execute_subworkflow_node(uid(), "Notify: Critical", [pos[0] + 220, pos[1]])
        replace_node(wf, "send-slack", code_node)
        add_node_after(wf, code_node["name"], exec_node)
        changed = True
        print("  DONE: send-slack → sys:router:notify (critical)")

    # 3. Replace send-error-ntfy
    node = find_node(wf["nodes"], name="send-error-ntfy")
    if node:
        pos = node["position"]
        code = """// Error notification
const p = $input.first().json;
return [{
  json: {
    universe: 'home',
    domain: 'security',
    source: 'frigate',
    category: 'workflow',
    severity: 'critical',
    summary: p.title || 'Frigate workflow error',
    timestamp: new Date().toISOString(),
    action_hint: 'retry-workflow',
    metadata: { error: p.message || '', tags: p.tags || '' }
  }
}];"""
        code_node = make_notify_code_node(uid(), "Build Error Notify", [pos[0], pos[1]], code)
        exec_node = make_execute_subworkflow_node(uid(), "Notify: Error", [pos[0] + 220, pos[1]])
        replace_node(wf, "send-error-ntfy", code_node)
        add_node_after(wf, code_node["name"], exec_node)
        changed = True
        print("  DONE: send-error-ntfy → sys:router:notify (error)")

    return changed


def wire_alertmanager(wf):
    """home:admin:alert-manager — replace ntfy + slack + error-ntfy"""
    changed = False

    node = find_node(wf["nodes"], name="send-ntfy")
    if node:
        pos = node["position"]
        code = """// Build sys:router:notify from Alertmanager enriched data
const p = $input.first().json;
const severityMap = { 5: 'critical', 4: 'warning', 3: 'info', 2: 'info', 1: 'debug' };
const severity = severityMap[p.priority] || 'warning';

return [{
  json: {
    universe: 'home',
    domain: 'admin',
    source: 'alertmanager',
    category: 'infrastructure',
    severity: severity,
    summary: p.title || p.message || 'System alert',
    timestamp: new Date().toISOString(),
    action_hint: severity === 'critical' ? 'restart-service' : 'none',
    metadata: {
      topic: p.topic || '',
      tags: p.tags || '',
      alertname: p.alertname || '',
      instance: p.instance || '',
      grafana_link: p.grafana_link || ''
    }
  }
}];"""
        code_node = make_notify_code_node(uid(), "Build Alert Notify", [pos[0], pos[1]], code)
        exec_node = make_execute_subworkflow_node(uid(), "Notify: Alert", [pos[0] + 220, pos[1]])
        replace_node(wf, "send-ntfy", code_node)
        add_node_after(wf, code_node["name"], exec_node)
        changed = True
        print("  DONE: send-ntfy → sys:router:notify")

    node = find_node(wf["nodes"], name="send-slack")
    if node:
        pos = node["position"]
        code = """// Critical alert → sys:router:notify
const p = $input.first().json;
return [{
  json: {
    universe: 'home',
    domain: 'admin',
    source: 'alertmanager',
    category: 'infrastructure',
    severity: 'critical',
    summary: p.title || p.message || 'Critical system alert',
    timestamp: new Date().toISOString(),
    action_hint: 'escalate',
    metadata: { critical: true, message: p.message || '' }
  }
}];"""
        code_node = make_notify_code_node(uid(), "Build Critical Notify", [pos[0], pos[1]], code)
        exec_node = make_execute_subworkflow_node(uid(), "Notify: Critical Alert", [pos[0] + 220, pos[1]])
        replace_node(wf, "send-slack", code_node)
        add_node_after(wf, code_node["name"], exec_node)
        changed = True
        print("  DONE: send-slack → sys:router:notify (critical)")

    node = find_node(wf["nodes"], name="send-error-ntfy")
    if node:
        pos = node["position"]
        code = """// Alertmanager workflow error
const p = $input.first().json;
return [{
  json: {
    universe: 'home',
    domain: 'admin',
    source: 'alertmanager',
    category: 'workflow',
    severity: 'critical',
    summary: p.title || 'Alertmanager router error',
    timestamp: new Date().toISOString(),
    action_hint: 'retry-workflow',
    metadata: { error: p.message || '' }
  }
}];"""
        code_node = make_notify_code_node(uid(), "Build Error Notify", [pos[0], pos[1]], code)
        exec_node = make_execute_subworkflow_node(uid(), "Notify: Router Error", [pos[0] + 220, pos[1]])
        replace_node(wf, "send-error-ntfy", code_node)
        add_node_after(wf, code_node["name"], exec_node)
        changed = True
        print("  DONE: send-error-ntfy → sys:router:notify")

    return changed


def wire_health_check(wf):
    """home:admin:health-check — replace ntfy + slack"""
    changed = False

    node = find_node(wf["nodes"], name="send-ntfy")
    if node:
        pos = node["position"]
        code = """// Health check notification
const p = $input.first().json;
const severityMap = { 5: 'critical', 4: 'warning', 3: 'info', 2: 'debug' };
const severity = severityMap[p.priority] || 'warning';

return [{
  json: {
    universe: 'home',
    domain: 'admin',
    source: 'health-check',
    category: 'infrastructure',
    severity: severity,
    summary: p.title || p.message || 'Service health check',
    timestamp: new Date().toISOString(),
    action_hint: severity === 'critical' ? 'restart-service' : 'none',
    metadata: {
      service: p.service || '',
      status: p.status || '',
      topic: p.topic || '',
      tags: p.tags || ''
    }
  }
}];"""
        code_node = make_notify_code_node(uid(), "Build Health Notify", [pos[0], pos[1]], code)
        exec_node = make_execute_subworkflow_node(uid(), "Notify: Health", [pos[0] + 220, pos[1]])
        replace_node(wf, "send-ntfy", code_node)
        add_node_after(wf, code_node["name"], exec_node)
        changed = True
        print("  DONE: send-ntfy → sys:router:notify")

    node = find_node(wf["nodes"], name="send-slack")
    if node:
        pos = node["position"]
        code = """// Critical health alert
const p = $input.first().json;
return [{
  json: {
    universe: 'home',
    domain: 'admin',
    source: 'health-check',
    category: 'infrastructure',
    severity: 'critical',
    summary: p.title || p.message || 'Critical service down',
    timestamp: new Date().toISOString(),
    action_hint: 'restart-service',
    metadata: { critical: true, message: p.message || '' }
  }
}];"""
        code_node = make_notify_code_node(uid(), "Build Critical Health", [pos[0], pos[1]], code)
        exec_node = make_execute_subworkflow_node(uid(), "Notify: Critical Health", [pos[0] + 220, pos[1]])
        replace_node(wf, "send-slack", code_node)
        add_node_after(wf, code_node["name"], exec_node)
        changed = True
        print("  DONE: send-slack → sys:router:notify (critical)")

    return changed


def wire_media_pipeline(wf):
    """home:media:jellyfin-alert — replace ntfy + error-ntfy"""
    changed = False

    node = find_node(wf["nodes"], name="send-ntfy")
    if node:
        pos = node["position"]
        code = """// Media available notification
const p = $input.first().json;
return [{
  json: {
    universe: 'home',
    domain: 'media',
    source: 'media-pipeline',
    category: 'workflow',
    severity: 'info',
    summary: p.title || p.message || 'New media available',
    timestamp: new Date().toISOString(),
    action_hint: 'none',
    metadata: {
      media_type: p.media_type || p.mediaType || '',
      quality: p.quality || '',
      path: p.path || '',
      tags: p.tags || ''
    }
  }
}];"""
        code_node = make_notify_code_node(uid(), "Build Media Notify", [pos[0], pos[1]], code)
        exec_node = make_execute_subworkflow_node(uid(), "Notify: Media", [pos[0] + 220, pos[1]])
        replace_node(wf, "send-ntfy", code_node)
        add_node_after(wf, code_node["name"], exec_node)
        changed = True
        print("  DONE: send-ntfy → sys:router:notify")

    node = find_node(wf["nodes"], name="send-error-ntfy")
    if node:
        pos = node["position"]
        code = """// Media pipeline error
const p = $input.first().json;
return [{
  json: {
    universe: 'home',
    domain: 'media',
    source: 'media-pipeline',
    category: 'workflow',
    severity: 'critical',
    summary: p.title || 'Media pipeline error',
    timestamp: new Date().toISOString(),
    action_hint: 'retry-workflow',
    metadata: { error: p.message || '' }
  }
}];"""
        code_node = make_notify_code_node(uid(), "Build Media Error", [pos[0], pos[1]], code)
        exec_node = make_execute_subworkflow_node(uid(), "Notify: Media Error", [pos[0] + 220, pos[1]])
        replace_node(wf, "send-error-ntfy", code_node)
        add_node_after(wf, code_node["name"], exec_node)
        changed = True
        print("  DONE: send-error-ntfy → sys:router:notify")

    return changed


def wire_lead_response(wf):
    """hwc:ops:leads:response — replace 3 ntfy Push nodes (port 2586)"""
    changed = False

    for old_name, sev, summary_tpl in [
        ("Push: New Lead", "info",
         "New lead: ${p.name || 'Unknown'} — ${p.service_type || 'home improvement'}"),
        ("Push: Scheduled Lead", "info",
         "Scheduled lead follow-up: ${p.name || 'Unknown'}"),
        ("Push: Follow-up Needed", "warning",
         "Lead needs follow-up (no response): ${p.name || 'Unknown'}"),
    ]:
        node = find_node(wf["nodes"], name=old_name)
        if not node:
            print(f"  SKIP: '{old_name}' not found")
            continue

        pos = node["position"]
        hint = 'draft-response' if 'Follow-up' in old_name else 'classify'
        code = f"""// Lead notification → sys:router:notify
const p = $input.first().json;
return [{{
  json: {{
    universe: 'hwc',
    domain: 'ops',
    source: 'lead-response',
    category: 'lead',
    severity: '{sev}',
    summary: `{summary_tpl}`,
    timestamp: new Date().toISOString(),
    action_hint: '{hint}',
    metadata: {{
      name: p.name || '',
      phone: p.phone_e164 || p.phone || '',
      email: p.email || '',
      service_type: p.service_type || '',
      lead_id: p.id || p.lead_id || ''
    }}
  }}
}}];"""

        code_node = make_notify_code_node(
            uid(), f"Build: {old_name}", [pos[0], pos[1]], code
        )
        exec_node = make_execute_subworkflow_node(
            uid(), f"Notify: {old_name}", [pos[0] + 220, pos[1]]
        )

        replace_node(wf, old_name, code_node)
        add_node_after(wf, code_node["name"], exec_node)
        changed = True
        print(f"  DONE: '{old_name}' → sys:router:notify ({sev})")

    return changed


# ============================================================================
# MAIN
# ============================================================================

WORKFLOW_MAP = {
    "mail-health-alert-router": ("home:social:mail-health", wire_mail_health),
    "jbIqSwVByVnEAk7e": ("hwc:ops:jt:estimate-push", wire_estimate_push),
    "mNJKL8puSZpWhsR2": ("home:security:frigate-detect", wire_frigate),
    "YgoqxXkDtRkDrbpK": ("home:admin:alert-manager", wire_alertmanager),
    "KaGqsviVtFGp5d7l": ("home:admin:health-check", wire_health_check),
    "n14heZ9wzJ8Uyemo": ("home:media:jellyfin-alert", wire_media_pipeline),
    "lead-response-automation": ("hwc:ops:leads:response", wire_lead_response),
}

def main():
    dry_run = "--dry-run" in sys.argv
    target = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else None

    for wf_id, (wf_name, handler) in WORKFLOW_MAP.items():
        if target and target != wf_id and target != wf_name:
            continue

        print(f"\n{'='*60}")
        print(f"Processing: {wf_name} ({wf_id})")
        print(f"{'='*60}")

        try:
            data = api_get(f"/workflows/{wf_id}")
        except urllib.error.HTTPError as e:
            print(f"  ERROR: Failed to fetch workflow: {e}")
            continue

        wf = data
        original_nodes = len(wf["nodes"])

        changed = handler(wf)

        if not changed:
            print("  No changes needed")
            continue

        new_nodes = len(wf["nodes"])
        print(f"  Nodes: {original_nodes} → {new_nodes}")

        if dry_run:
            print("  DRY RUN: skipping API update")
            # Still save to file for inspection
            out_path = f"/tmp/n8n-notify-{wf_id}.json"
            with open(out_path, "w") as f:
                json.dump(wf, f, indent=2)
            print(f"  Saved preview: {out_path}")
            continue

        # Update via API
        try:
            # Only send the fields the API expects
            update_payload = {
                "name": wf.get("name", wf_name),
                "nodes": wf["nodes"],
                "connections": wf["connections"],
                "settings": wf.get("settings", {}),
                "staticData": wf.get("staticData"),
            }
            result = api_put(f"/workflows/{wf_id}", update_payload)
            print(f"  UPDATED via API ✓")
        except urllib.error.HTTPError as e:
            body = e.read().decode() if hasattr(e, 'read') else str(e)
            print(f"  ERROR updating via API: {e.code} — {body[:200]}")
            # Save failed version for debugging
            out_path = f"/tmp/n8n-notify-FAILED-{wf_id}.json"
            with open(out_path, "w") as f:
                json.dump(wf, f, indent=2)
            print(f"  Saved failed payload: {out_path}")

    print("\n✓ All workflows processed.")
    if dry_run:
        print("  (Dry run — no API changes were made)")

if __name__ == "__main__":
    main()
