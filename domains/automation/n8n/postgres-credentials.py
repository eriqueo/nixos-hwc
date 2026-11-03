"""Reconcile selected PostgreSQL credentials while the n8n container is stopped.

Use the vendor CLI and current encryption key. Never run a workflow, print CLI
output, decrypt unrelated credentials, or put a database password into SQLite.
"""
import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import selectors
import sqlite3
import subprocess
import sys
import time


class BoundaryError(Exception):
    pass


def require(condition, code):
    if not condition:
        raise BoundaryError(code)


def run_bounded(command, payload=None):
    """Fail and terminate the CLI at its time/output limit; never retry."""
    require(payload is None or len(payload) <= 4 * 1024 * 1024, "CLI_INPUT_BOUND")
    process = subprocess.Popen(command, stdin=subprocess.PIPE if payload else subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output = {"stdout": bytearray(), "stderr": bytearray()}
    limits = {"stdout": 4 * 1024 * 1024, "stderr": 1024 * 1024}
    position = 0
    deadline = time.monotonic() + 95
    try:
        with selectors.DefaultSelector() as selector:
            for label in output:
                handle = getattr(process, label)
                os.set_blocking(handle.fileno(), False)
                selector.register(handle, selectors.EVENT_READ, label)
            if payload:
                os.set_blocking(process.stdin.fileno(), False)
                selector.register(process.stdin, selectors.EVENT_WRITE, "stdin")
            while selector.get_map():
                require(time.monotonic() < deadline, "CLI_TIME_BOUND")
                for event, _ in selector.select(timeout=min(1, max(0, deadline - time.monotonic()))):
                    if event.data == "stdin":
                        position += os.write(event.fileobj.fileno(), payload[position:position + 65536])
                        if position == len(payload):
                            selector.unregister(event.fileobj)
                            event.fileobj.close()
                    else:
                        chunk = os.read(event.fileobj.fileno(), 65536)
                        if not chunk:
                            selector.unregister(event.fileobj)
                            event.fileobj.close()
                        else:
                            require(len(output[event.data]) + len(chunk) <= limits[event.data], "CLI_OUTPUT_BOUND")
                            output[event.data].extend(chunk)
        require(process.wait(timeout=max(0.1, deadline - time.monotonic())) == 0, "SCOPED_CLI_FAILED")
        return output["stdout"].decode()
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        for handle in (process.stdin, process.stdout, process.stderr):
            if handle is not None:
                handle.close()


def row_digest(row, key):
    encoded = json.dumps(row, sort_keys=True, separators=(",", ":"),
                         default=lambda value: {"bytes": bytes(value).hex()}).encode()
    require(len(encoded) <= 16 * 1024 * 1024, "SQLITE_ROW_BOUND")
    return hmac.digest(key, encoded, "sha256")


def snapshot(database, ids, key):
    tables = {}
    selected = {}
    with sqlite3.connect(f"file:{database}?mode=ro", uri=True, timeout=5) as db:
        db.execute("BEGIN")
        require(db.execute("PRAGMA quick_check").fetchone() == ("ok",), "SQLITE_QUICK_CHECK_FAILED")
        actual_ids = {row[0] for row in db.execute("SELECT id FROM credentials_entity WHERE type='postgres'")}
        require(actual_ids == set(ids), "POSTGRES_CREDENTIAL_SCOPE_CHANGED")
        names = [row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
        for name in names:
            cursor = db.execute('SELECT * FROM "' + name.replace('"', '""') + '"')
            columns = [column[0] for column in cursor.description]
            hashes = []
            for index, row in enumerate(cursor):
                require(index < 2000000, "SQLITE_TABLE_ROW_BOUND")
                record = dict(zip(columns, row))
                if name == "credentials_entity" and record["id"] in ids:
                    selected[record["id"]] = record
                else:
                    hashes.append(row_digest(record, key))
            tables[name] = (len(hashes), hashlib.sha256(b"".join(sorted(hashes))).hexdigest())
        require(len(selected) == len(ids), "SELECTED_CREDENTIAL_MISSING")
    return tables, selected


def reconcile(config, database, cli, key):
    require(config["schemaVersion"] == 1, "CONFIG_VERSION_INVALID")
    ids = config["credentialIds"]
    require(isinstance(ids, list) and 0 < len(ids) <= 16 and len(ids) == len(set(ids)), "CREDENTIAL_COUNT_BOUND")
    before, selected = snapshot(database, ids, key)

    def exported(credential_id):
        raw = cli(["export:credentials", "--id=" + credential_id, "--decrypted", "--output=/dev/stdout"])
        decoder = json.JSONDecoder()
        found = []
        # The CLI can log around its JSON and can catch an error with exit0.
        # Require exactly the selected record, then verify the stored readback.
        for offset in [0] + [i + 1 for i, char in enumerate(raw) if char == "\n"]:
            if raw[offset:offset + 1] != "[":
                continue
            try:
                value, _ = decoder.raw_decode(raw[offset:])
            except ValueError:
                continue
            if isinstance(value, list) and len(value) == 1 and value[0].get("id") == credential_id:
                found.append(value[0])
        require(len(found) == 1 and found[0]["type"] == "postgres", "SCOPED_EXPORT_INVALID")
        return found[0]

    records = [exported(credential_id) for credential_id in ids]
    desired = config["desired"]
    changes = []
    for record in records:
        data = record["data"]
        require(isinstance(data, dict) and data.get("database") == config["database"], "DATABASE_IDENTITY_MISMATCH")
        require(not data.get("sshTunnel", False), "UNEXPECTED_POSTGRES_SSH_TUNNEL")
        # Reject a remote client rather than silently redirecting its credential.
        require(data.get("host", config["vendorDefaults"]["host"]) == desired["host"]
                and data.get("port", config["vendorDefaults"]["port"]) == desired["port"], "DATABASE_TRANSPORT_MISMATCH")
        target = dict(data, **desired)
        if target != data:
            changes.append({field: record[field] for field in ("id", "name", "type")} | {"data": target})
    # Idempotent effect: reserve no new ID, update only existing IDs, and skip
    # import when the selected content is already correct. No retry loop.
    if changes:
        cli(["import:credentials", "--input=/dev/stdin"], json.dumps(changes).encode())
    verified = [exported(credential_id) for credential_id in ids] if changes else records
    for original, current in zip(records, verified):
        require(current["data"] == dict(original["data"], **desired), "CREDENTIAL_READBACK_MISMATCH")
    after, updated = snapshot(database, ids, key)
    require(after == before, "UNRELATED_SQLITE_STATE_CHANGED")
    for credential_id in ids:
        old, new = selected[credential_id], updated[credential_id]
        differences = {field for field in old if old[field] != new[field]}
        require(differences <= {"data", "updatedAt"}, "CREDENTIAL_METADATA_CHANGED")
        if not changes:
            require(not differences, "IDEMPOTENT_START_CHANGED_CREDENTIAL")
    return {"passed": True, "state": "applied" if changes else "unchanged",
            "selectedCredentials": len(ids), "changedCredentials": len(changes),
            "unrelatedTablesPreserved": len(after) - 1}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=Path)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--podman", required=True)
    parser.add_argument("--image", required=True)
    parser.add_argument("--encryption-env-file", type=Path)
    args = parser.parse_args()
    try:
        inspect = subprocess.run([args.podman, "inspect", "--format={{.State.Running}}", "n8n"],
                                 capture_output=True, timeout=10)
        if inspect.returncode == 0:
            require(inspect.stdout.strip() == b"false", "N8N_MUST_BE_STOPPED")
        else:
            # Distinguish absence from an inaccessible/broken container engine.
            exists = subprocess.run([args.podman, "container", "exists", "n8n"], capture_output=True, timeout=10)
            require(exists.returncode == 1, "CONTAINER_STATE_UNKNOWN")

        def cli(arguments, payload=None):
            command = [args.podman, "run", "--rm", "-i", "--network=none", "--user=1000:100",
                       "--name=n8n-postgres-credential-setup",
                       "--cap-drop=all", "--security-opt=no-new-privileges", "--read-only",
                       "--tmpfs=/tmp:rw,nosuid,nodev,size=128m", "--memory=1g", "--cpus=1",
                       "--timeout=90", "--stop-timeout=15", "--env=N8N_DIAGNOSTICS_ENABLED=false",
                       "--env=N8N_VERSION_NOTIFICATIONS_ENABLED=false",
                       "--env=N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true",
                       "-v", str(args.data_dir) + ":/home/node/.n8n:rw"]
            if args.encryption_env_file:
                command += ["--env-file", str(args.encryption_env_file)]
            command += ["--entrypoint=/usr/local/bin/node", args.image,
                        "/usr/local/lib/node_modules/n8n/bin/n8n", *arguments]
            # A real OS pipe supports the vendor's /dev/stdout export; a Node
            # child-process socket does not. Output remains private to memory.
            try:
                return run_bounded(command, payload)
            except BaseException:
                # Only this unit's private network-none helper; never stop n8n.
                subprocess.run([args.podman, "stop", "--time=10", "n8n-postgres-credential-setup"],
                               capture_output=True, timeout=15)
                raise

        print(json.dumps(reconcile(json.loads(args.config.read_text()), args.data_dir / "database.sqlite", cli, os.urandom(32))))
    except (BoundaryError, OSError, ValueError, KeyError, sqlite3.Error, subprocess.SubprocessError) as error:
        # Never emit CLI output, encrypted records, selected data or exception text.
        print(json.dumps({"passed": False, "code": str(error) if isinstance(error, BoundaryError) else "CREDENTIAL_RECONCILIATION_FAILED"}), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
