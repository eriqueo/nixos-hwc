"""Bounded local-peer role setup. Passwords enter via systemd credentials.

Role, password and database-local owner changes commit together per database.
Never log SQL, password verifiers or exception text.
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import sys

import psycopg
from psycopg import sql


class ContractError(Exception):
    def __init__(self, code):
        self.code = code


def require(condition, code):
    if not condition:
        raise ContractError(code)


def scram_matches(password, verifier):
    """Keep the verifier and salt unchanged on ordinary starts."""
    if not verifier or not verifier.startswith("SCRAM-SHA-256$"):
        return False
    try:
        _, parameters, keys = verifier.split("$")
        iterations, salt = parameters.split(":")
        stored, server = keys.split(":")
        iterations = int(iterations)
        require(4096 <= iterations <= 1000000, "SCRAM_ITERATION_BOUND")
        salted = hashlib.pbkdf2_hmac(
            "sha256", password, base64.b64decode(salt, validate=True), iterations
        )
        client = hmac.digest(salted, b"Client Key", "sha256")
        return hmac.compare_digest(
            hashlib.sha256(client).digest(), base64.b64decode(stored, validate=True)
        ) and hmac.compare_digest(
            hmac.digest(salted, b"Server Key", "sha256"),
            base64.b64decode(server, validate=True),
        )
    except (ValueError, ContractError):
        return False


def parse_roles(value, admin):
    require(isinstance(value, dict) and 0 < len(value) <= 16, "ROLE_COUNT_BOUND")
    safe = re.compile(r"[a-z_][a-z0-9_]{0,62}\Z")
    for name, spec in value.items():
        require(bool(safe.fullmatch(name)), "ROLE_NAME_INVALID")
        require(name not in {admin, "postgres"} and not name.startswith("pg_"), "ADMIN_ROLE_FORBIDDEN")
        require(isinstance(spec, dict) and set(spec) == {"schemas", "takeOwnershipFrom"}, "ROLE_SPEC_INVALID")
        schemas = spec["schemas"]
        require(isinstance(schemas, list) and 0 < len(schemas) <= 8, "SCHEMA_COUNT_BOUND")
        require(all(isinstance(s, str) and safe.fullmatch(s) for s in schemas), "SCHEMA_NAME_INVALID")
        require(len(set(schemas)) == len(schemas), "DUPLICATE_SCHEMA")
        previous = spec["takeOwnershipFrom"]
        require(previous is None or isinstance(previous, str) and safe.fullmatch(previous), "PREVIOUS_OWNER_INVALID")
        require(previous != name, "PREVIOUS_OWNER_IS_TARGET")
    return value


# Both catalog classes matter: extension-owned composite types also have a
# pg_class relation. Never transfer extension members or shared database owners.
# %% escapes PostgreSQL format() placeholders for psycopg's parameter protocol.
OWNER_OPERATIONS = """
SELECT kind, identity FROM (
 SELECT CASE c.relkind WHEN 'r' THEN 'TABLE' WHEN 'p' THEN 'TABLE'
   WHEN 'S' THEN 'SEQUENCE' WHEN 'v' THEN 'VIEW'
   WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'c' THEN 'TYPE' END AS kind,
   format('%%I.%%I',n.nspname,c.relname) AS identity
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname=%s)
   AND n.nspname=ANY(%s) AND c.relkind IN ('r','p','S','v','m','c')
   AND NOT EXISTS(SELECT 1 FROM pg_depend d
     WHERE d.classid='pg_class'::regclass AND d.objid=c.oid AND d.deptype='e')
   AND NOT(c.relkind='c' AND EXISTS(SELECT 1 FROM pg_type t
     JOIN pg_depend d ON d.classid='pg_type'::regclass AND d.objid=t.oid AND d.deptype='e'
     WHERE t.typrelid=c.oid))
 UNION ALL
 SELECT 'TYPE',format('%%I.%%I',n.nspname,t.typname)
 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
 WHERE t.typowner=(SELECT oid FROM pg_roles WHERE rolname=%s)
   AND n.nspname=ANY(%s) AND t.typtype IN ('e','d')
   AND NOT EXISTS(SELECT 1 FROM pg_depend d
     WHERE d.classid='pg_type'::regclass AND d.objid=t.oid AND d.deptype='e')
 UNION ALL
 SELECT CASE p.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,
   format('%%I.%%I(%%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.proowner=(SELECT oid FROM pg_roles WHERE rolname=%s)
   AND n.nspname=ANY(%s)
   AND NOT EXISTS(SELECT 1 FROM pg_depend d
     WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e')
) objects ORDER BY CASE kind WHEN 'TABLE' THEN 0 ELSE 1 END, identity LIMIT 4097
"""


def provision(connect, roles, read_password):
    results = []
    for name, spec in sorted(roles.items()):
        password = read_password(name)
        require(bool(re.fullmatch(rb"[A-Za-z0-9_-]{64}", password)), "PASSWORD_FORMAT_INVALID")
        with connect(name) as connection:
            with connection.cursor() as cursor:
                cursor.execute("SET LOCAL lock_timeout='2s'; SET LOCAL statement_timeout='30s'")
                cursor.execute("SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname=current_database()")
                require(cursor.fetchone() == (name,), "DATABASE_OWNER_MISMATCH")
                cursor.execute("SELECT EXISTS(SELECT 1 FROM pg_auth_members WHERE member=(SELECT oid FROM pg_roles WHERE rolname=%s))", (name,))
                require(cursor.fetchone() == (False,), "ROLE_MEMBERSHIPS_REQUIRE_REVIEW")
                cursor.execute("SELECT rolpassword FROM pg_authid WHERE rolname=%s", (name,))
                row = cursor.fetchone()
                require(row is not None, "DECLARED_ROLE_MISSING")
                changed = not scram_matches(password, row[0])
                cursor.execute(sql.SQL("ALTER ROLE {} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS").format(sql.Identifier(name)))
                if changed:
                    cursor.execute("SET LOCAL password_encryption='scram-sha-256'")
                    cursor.execute(sql.SQL("ALTER ROLE {} PASSWORD {}").format(sql.Identifier(name), sql.Literal(password.decode("ascii"))))
                operations = []
                previous = spec["takeOwnershipFrom"]
                if previous is not None:
                    cursor.execute(OWNER_OPERATIONS, (previous, spec["schemas"]) * 3)
                    operations = cursor.fetchmany(4097)
                    require(len(operations) <= 4096, "OWNER_OPERATION_BOUND")
                    for kind, identity in operations:
                        require(kind in {"TABLE", "SEQUENCE", "VIEW", "MATERIALIZED VIEW", "TYPE", "FUNCTION", "PROCEDURE"}, "OWNER_KIND_INVALID")
                        cursor.execute(sql.SQL("ALTER {} {} OWNER TO {}").format(sql.SQL(kind), sql.SQL(identity), sql.Identifier(name)))
        results.append({"role": name, "passwordChanged": changed, "ownershipOperations": len(operations)})
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=Path)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--admin-role", required=True)
    args = parser.parse_args()
    try:
        roles = parse_roles(json.loads(args.config.read_text()), args.admin_role)
        credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])

        def connect(database):
            return psycopg.connect(
                dbname=database, user=args.admin_role, host=args.socket,
                port=args.port, connect_timeout=5,
                options="-c log_statement=none -c log_min_duration_statement=-1 "
                        "-c log_min_error_statement=panic -c log_parameter_max_length_on_error=0",
            )

        def read_password(name):
            with (credentials / name).open("rb") as handle:
                return handle.read(65)

        print(json.dumps({"passed": True, "roles": provision(connect, roles, read_password)}))
    except (psycopg.Error, ContractError, OSError, ValueError, KeyError) as error:
        print(json.dumps({"passed": False, "code": getattr(error, "sqlstate", None) or getattr(error, "code", None) or "ROLE_OPERATION_FAILED"}), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
