#!/usr/bin/env python3
"""Tests for n8n-workflow-export.py.

Run from the repo root:
    python3 -m unittest discover -s workspace/automation -p 'test_*.py' -v

The module name has a dash, so it is loaded by path rather than imported.
"""

import copy
import importlib.util
import io
import json
import os
import shlex
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
TOOL_FILE = os.path.join(HERE, "n8n-workflow-export.py")
WORKFLOW_DIR = os.path.join(REPO_ROOT, "domains", "automation", "n8n", "parts", "workflows")

_spec = importlib.util.spec_from_file_location("n8n_workflow_export", TOOL_FILE)
tool = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tool)


# Secret fixtures are assembled from pieces so this test file never carries a
# raw webhook literal that a repo-wide grep (or a future widening of the flake
# check's glob) would flag as a real leak. The runtime value is exactly what a
# leaked export would contain.
FAKE_DISCORD = (
    "https://discord.com/api/web" + "hooks/123456789012345678/"
    + "aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789aBcDeFgHiJkLmNoPqRsTuV"
)
# A provider the pattern table has never heard of: the point is that an
# unrecognised credential must NOT pass as clean.
FAKE_UNKNOWN_WEBHOOK = (
    "https://chat.example-provider.com/v1/spaces/AAAA/messages"
    "?key=Zk9QwErTyUiOpAsDfGhJkLzXcVbNm1234567890"
)


def workflow(**overrides):
    """A small but structurally real workflow: two branches off a switch, so a
    reordering bug in the canonicalizer would show up as changed topology."""
    doc = {
        "id": "wf-abc123",
        "name": "home:security:frigate-detect",
        "active": True,
        "isArchived": False,
        "createdAt": "2026-03-31T17:00:22.045Z",
        "updatedAt": "2026-07-15T22:59:52.484Z",
        "versionId": "d8839815-712e-4b63-a04f-b9fc78ba2c84",
        "activeVersionId": "d8839815-712e-4b63-a04f-b9fc78ba2c84",
        "versionCounter": 36,
        "triggerCount": 1,
        "staticData": {"cooldowns": {"reolink:person": 1755555555555}},
        "pinData": {},
        "meta": {"instanceId": "deadbeef"},
        "shared": [{"role": "workflow:owner", "project": {"id": "p1"}}],
        "activeVersion": {"nodes": [], "connections": {}},
        "workflowPublishHistory": [{"id": 293, "event": "activated"}],
        "nodes": [
            {"id": "n3", "name": "Text to Other Channel", "type": "n8n-nodes-base.httpRequest",
             "position": [-832, 128],
             "parameters": {"method": "POST", "url": "={{ $env.DISCORD_WEBHOOK_FRIGATE_URL }}"}},
            {"id": "n1", "name": "Webhook Trigger", "type": "n8n-nodes-base.webhook",
             "position": [-1440, -32], "parameters": {"path": "frigate-events"}},
            {"id": "n2", "name": "Person or Other", "type": "n8n-nodes-base.switch",
             "position": [-1040, -32], "parameters": {"options": {}}},
        ],
        "connections": {
            "Webhook Trigger": {"main": [[{"node": "Person or Other", "type": "main", "index": 0}]]},
            "Person or Other": {"main": [
                [{"node": "Upload Snapshot", "type": "main", "index": 0}],
                [{"node": "Text to Other Channel", "type": "main", "index": 0}],
            ]},
        },
        "settings": {"executionOrder": "v1"},
        "tags": [
            {"id": "t2", "name": "security", "createdAt": "2025-12-08T22:04:03.512Z"},
            {"id": "t1", "name": "frigate", "createdAt": "2025-12-08T22:03:07.192Z"},
        ],
    }
    doc.update(overrides)
    return doc


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    code = tool.main(argv, stdout=out, stderr=err)
    return code, out.getvalue(), err.getvalue()


class TemporaryWorkflow:
    """Writes an input export and yields (in_path, out_path) inside a tmpdir."""

    def __init__(self, doc):
        self.doc = doc

    def __enter__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.in_path = os.path.join(self.tmp.name, "live-export.json")
        self.out_path = os.path.join(self.tmp.name, "canonical.json")
        with open(self.in_path, "w", encoding="utf-8") as handle:
            json.dump(self.doc, handle)
        return self.in_path, self.out_path

    def __exit__(self, *exc):
        self.tmp.cleanup()
        return False


class TestDeterminism(unittest.TestCase):
    def test_repeated_runs_are_byte_identical(self):
        doc = workflow()
        self.assertEqual(tool.dumps(tool.canonicalize(doc)), tool.dumps(tool.canonicalize(doc)))

    def test_key_and_node_order_do_not_change_the_bytes(self):
        first = workflow()
        shuffled = {k: copy.deepcopy(v) for k, v in reversed(list(first.items()))}
        shuffled["nodes"] = list(reversed(shuffled["nodes"]))
        shuffled["tags"] = list(reversed(shuffled["tags"]))
        self.assertEqual(
            tool.dumps(tool.canonicalize(first)),
            tool.dumps(tool.canonicalize(shuffled)),
        )

    def test_clock_is_explicit_and_cannot_reach_the_artifact(self):
        with TemporaryWorkflow(workflow()) as (src, dst):
            self.assertEqual(run(["canonicalize", "--in", src, "--out", dst,
                                  "--now", "2026-01-01T00:00:00Z"])[0], 0)
            with open(dst, encoding="utf-8") as handle:
                first = handle.read()
            self.assertEqual(run(["canonicalize", "--in", src, "--out", dst,
                                  "--now", "2031-12-31T23:59:59Z"])[0], 0)
            with open(dst, encoding="utf-8") as handle:
                second = handle.read()
        self.assertEqual(first, second)
        self.assertNotIn("2026-01-01", first)

    def test_generated_marker_has_provenance_and_no_timestamp(self):
        canonical = tool.canonicalize(workflow(), out_path="parts/workflows/02-x.json")
        marker = canonical["_hwc"]
        self.assertEqual(marker["sourceWorkflowId"], "wf-abc123")
        self.assertEqual(marker["sourceWorkflowName"], "home:security:frigate-detect")
        # the marker agrees with the body it describes, so the duplication is
        # checked rather than trusted
        self.assertEqual(marker["sourceWorkflowId"], canonical["id"])
        self.assertEqual(marker["sourceWorkflowName"], canonical["name"])
        self.assertIn("GENERATED", marker["note"])
        for value in marker.values():
            self.assertNotRegex(str(value), r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}")


class TestVolatileFields(unittest.TestCase):
    def test_instance_state_is_dropped(self):
        canonical = tool.canonicalize(workflow())
        for key in ["active", "activeVersion", "activeVersionId", "createdAt", "updatedAt",
                    "isArchived", "meta", "pinData", "shared", "staticData", "triggerCount",
                    "versionCounter", "versionId", "workflowPublishHistory"]:
            self.assertNotIn(key, canonical, "%s survived canonicalization" % key)

    def test_tags_keep_names_and_lose_instance_ids(self):
        canonical = tool.canonicalize(workflow())
        self.assertEqual(canonical["tags"], [{"name": "frigate"}, {"name": "security"}])

    def test_definition_fields_survive(self):
        canonical = tool.canonicalize(workflow())
        self.assertEqual(canonical["settings"], {"executionOrder": "v1"})
        positions = {n["name"]: n["position"] for n in canonical["nodes"]}
        self.assertEqual(positions["Webhook Trigger"], [-1440, -32])

    def test_a_node_named_like_a_volatile_key_is_not_deleted(self):
        """Pruning is anchored at the top level; a connection source named
        'meta' must survive. This is the corruption the anchor prevents."""
        doc = workflow()
        doc["connections"]["meta"] = {"main": [[{"node": "Person or Other",
                                                 "type": "main", "index": 0}]]}
        canonical = tool.canonicalize(doc)
        self.assertIn("meta", canonical["connections"])


class TestTopologyPreserved(unittest.TestCase):
    def test_connections_are_untouched(self):
        doc = workflow()
        expected = copy.deepcopy(doc["connections"])
        canonical = tool.canonicalize(doc)
        self.assertEqual(canonical["connections"], expected)
        # branch order is the OUTPUT INDEX — sorting it would reroute the switch
        self.assertEqual(
            canonical["connections"]["Person or Other"]["main"][1][0]["node"],
            "Text to Other Channel",
        )

    def test_every_node_survives_with_its_parameters(self):
        doc = workflow()
        canonical = tool.canonicalize(doc)
        self.assertEqual(
            sorted(n["name"] for n in canonical["nodes"]),
            sorted(n["name"] for n in doc["nodes"]),
        )
        by_name = {n["name"]: n for n in canonical["nodes"]}
        self.assertEqual(
            by_name["Text to Other Channel"]["parameters"]["url"],
            "={{ $env.DISCORD_WEBHOOK_FRIGATE_URL }}",
        )

    def test_input_document_is_not_mutated(self):
        doc = workflow()
        before = copy.deepcopy(doc)
        tool.canonicalize(doc)
        self.assertEqual(doc, before)


class TestKnownSecretRejection(unittest.TestCase):
    def test_seeded_discord_webhook_fails_and_writes_nothing(self):
        doc = workflow()
        doc["nodes"][0]["parameters"]["url"] = FAKE_DISCORD
        with TemporaryWorkflow(doc) as (src, dst):
            code, _, err = run(["canonicalize", "--in", src, "--out", dst])
            self.assertEqual(code, 2)
            self.assertIn("discord-webhook", err)
            self.assertFalse(os.path.exists(dst), "a rejected export must leave no file")

    def test_bearer_token_in_a_header_parameter_is_caught(self):
        doc = workflow()
        doc["nodes"][1]["parameters"]["headerParameters"] = {"parameters": [
            {"name": "Authorization", "value": "Bearer sk1234567890abcdefghijklmnop"},
        ]}
        findings = tool.scan_doc(doc)
        self.assertTrue(any(f.rule == "bearer-token" for f in findings), findings)

    def test_findings_do_not_echo_the_whole_credential(self):
        findings = tool.scan_text(FAKE_DISCORD)
        self.assertTrue(findings)
        for finding in findings:
            self.assertNotIn("aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789", finding.excerpt)
            self.assertLessEqual(len(finding.excerpt), tool.EXCERPT_HEAD + len("...(999 chars)"))

    def test_env_expressions_are_not_secrets(self):
        self.assertEqual(tool.scan_doc(workflow()), [])


class TestUnrecognizedCredentials(unittest.TestCase):
    def test_unknown_providers_webhook_is_not_a_false_success(self):
        doc = workflow()
        doc["nodes"][0]["parameters"]["url"] = FAKE_UNKNOWN_WEBHOOK
        with TemporaryWorkflow(doc) as (src, dst):
            code, _, err = run(["canonicalize", "--in", src, "--out", dst])
            self.assertEqual(code, 2)
            self.assertIn("opaque-url-segment", err)
            self.assertFalse(os.path.exists(dst))

    def test_literal_under_a_credential_shaped_key_is_caught(self):
        doc = workflow()
        doc["nodes"][1]["parameters"]["apiKey"] = "Q7zR2mV9pL4xB8nT6yW1kH3sD5gJ0aF"
        findings = tool.scan_doc(doc)
        self.assertTrue(any(f.rule == "credential-key" for f in findings), findings)

    def test_literal_in_a_credential_shaped_parameter_pair_is_caught(self):
        doc = workflow()
        doc["nodes"][1]["parameters"]["headerParameters"] = {"parameters": [
            {"name": "x-api-key", "value": "Q7zR2mV9pL4xB8nT6yW1kH3sD5gJ0aF"},
        ]}
        findings = tool.scan_doc(doc)
        self.assertTrue(any(f.rule == "credential-parameter" for f in findings), findings)

    def test_redact_covers_known_shapes_but_still_fails_on_unknown_ones(self):
        doc = workflow()
        doc["nodes"][0]["parameters"]["url"] = FAKE_DISCORD
        doc["nodes"][1]["parameters"]["url"] = FAKE_UNKNOWN_WEBHOOK
        with TemporaryWorkflow(doc) as (src, dst):
            code, _, err = run(["canonicalize", "--in", src, "--out", dst, "--redact"])
        self.assertEqual(code, 2, "redaction must not conceal an unrecognised secret")
        self.assertIn("opaque-url-segment", err)
        self.assertNotIn("discord-webhook", err)

    def test_redact_replaces_the_known_shape_in_place(self):
        redacted, count = tool.redact_known({"url": FAKE_DISCORD})
        self.assertEqual(count, 1)
        self.assertEqual(redacted["url"], tool.PLACEHOLDER)


class TestFindingReport(unittest.TestCase):
    """The report is the only place a finding is rendered, and it runs on the
    failure path — the one path a passing suite would otherwise never execute."""

    def test_a_finding_renders_without_percent_formatting_the_tuple(self):
        """A Finding IS a 3-tuple, so `"%s" % finding` raises TypeError. That
        crash replaced every secret report with a stack trace."""
        line = tool.format_finding(tool.Finding("discord-webhook", "$.nodes[0].url", "abc"))
        self.assertEqual(line, "rule=discord-webhook where=$.nodes[0].url excerpt=abc")

    def test_the_report_writes_one_line_per_finding(self):
        stream = io.StringIO()
        tool._report(tool.scan_text(FAKE_DISCORD, "$.nodes[0].parameters.url"), stream)
        lines = stream.getvalue().splitlines()
        self.assertTrue(lines)
        for line in lines:
            self.assertTrue(line.startswith("  rule="), line)
            self.assertIn("where=$.nodes[0].parameters.url", line)

    def test_the_report_never_prints_the_credential_body(self):
        for value in (FAKE_DISCORD, FAKE_UNKNOWN_WEBHOOK):
            stream = io.StringIO()
            tool._report(tool.scan_text(value), stream)
            text = stream.getvalue()
            self.assertTrue(text)
            self.assertNotIn(value, text)
            # the opaque tail is the credential; only a short prefix may appear
            self.assertNotIn(value[-16:], text)

    def test_the_cli_failure_path_reports_instead_of_crashing(self):
        doc = workflow()
        doc["nodes"][0]["parameters"]["url"] = FAKE_DISCORD
        with TemporaryWorkflow(doc) as (src, dst):
            code, _, err = run(["canonicalize", "--in", src, "--out", dst])
        self.assertEqual(code, 2)
        self.assertIn("rule=discord-webhook", err)
        self.assertNotIn("Traceback", err)


class TestRebuildCommand(unittest.TestCase):
    def test_the_recorded_command_reproduces_the_artifact(self):
        with TemporaryWorkflow(workflow()) as (src, dst):
            self.assertEqual(run(["canonicalize", "--in", src, "--out", dst])[0], 0)
            with open(dst, encoding="utf-8") as handle:
                original = handle.read()
            recorded = json.loads(original)["_hwc"]["rebuild"]
            argv = shlex.split(recorded.replace("<live-export.json>", src))
            self.assertEqual(argv[0], "python3")
            self.assertEqual(argv[1], tool.TOOL_PATH)
            self.assertEqual(run(argv[2:])[0], 0)
            with open(dst, encoding="utf-8") as handle:
                self.assertEqual(handle.read(), original)

    def test_the_tool_path_in_the_command_exists(self):
        self.assertTrue(os.path.exists(os.path.join(REPO_ROOT, tool.TOOL_PATH)))


class TestNoLiveConnection(unittest.TestCase):
    def test_the_tool_has_no_network_client(self):
        with open(TOOL_FILE, encoding="utf-8") as handle:
            source = handle.read()
        for forbidden in ["import requests", "import urllib", "import http.client",
                          "import socket", "from urllib"]:
            self.assertNotIn(forbidden, source)

    def test_the_scanner_does_not_match_its_own_definition(self):
        with open(TOOL_FILE, encoding="utf-8") as handle:
            self.assertEqual(tool.scan_text(handle.read(), TOOL_FILE), [])


class TestTrackedArtifacts(unittest.TestCase):
    """The wired flake check runs exactly this scan. An always-red check teaches
    people to ignore red (Charter §0.6), so day-one cleanliness is a test."""

    def test_every_tracked_workflow_artifact_is_clean(self):
        code, out, err = run(["scan", "--dir", WORKFLOW_DIR])
        self.assertEqual(code, 0, err)
        self.assertIn("clean", out)

    def test_the_frigate_export_uses_the_env_reference(self):
        path = os.path.join(WORKFLOW_DIR, "02-frigate-surveillance-intelligence.json")
        with open(path, encoding="utf-8") as handle:
            doc = json.load(handle)
        urls = [n["parameters"].get("url") for n in doc["nodes"]
                if n["type"] == "n8n-nodes-base.httpRequest"]
        discord_urls = [u for u in urls if u and "DISCORD_WEBHOOK_FRIGATE_URL" in u]
        self.assertEqual(len(discord_urls), 3)
        for url in discord_urls:
            self.assertEqual(url, "={{ $env.DISCORD_WEBHOOK_FRIGATE_URL }}")

    def test_the_snapshot_upload_stays_multipart(self):
        """hwc-notify cannot carry the attachment, so this node must keep
        posting the snapshot itself."""
        path = os.path.join(WORKFLOW_DIR, "02-frigate-surveillance-intelligence.json")
        with open(path, encoding="utf-8") as handle:
            doc = json.load(handle)
        upload = [n for n in doc["nodes"] if n["name"] == "Upload Snapshot to Person Channel"][0]
        self.assertEqual(upload["parameters"]["contentType"], "multipart-form-data")
        binary = [p for p in upload["parameters"]["bodyParameters"]["parameters"]
                  if p.get("parameterType") == "formBinaryData"]
        self.assertEqual(len(binary), 1)


if __name__ == "__main__":
    unittest.main()
