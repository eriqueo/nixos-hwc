"""Bounded local-peer role setup. Passwords enter via systemd credentials.

Role, password and database-local owner changes commit together per database.
Never log SQL, password verifiers or exception text.
"""
import argparse
import base64
from dataclasses import dataclass
from enum import Enum
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

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


@dataclass(frozen=True)
class RawPassword:
    pass


class CredentialEncoding(Enum):
    PASSWORD = "password"
    POSTGRESQL_URL = "postgresql-url"


@dataclass(frozen=True)
class EnvironmentPassword:
    field: str
    encoding: CredentialEncoding


@dataclass(frozen=True)
class OwnedDatabase:
    database: str
    schemas: tuple
    previous: str | None


@dataclass(frozen=True)
class SharedTables:
    database: str
    tables: tuple


@dataclass(frozen=True)
class Role:
    name: str
    credential: RawPassword | EnvironmentPassword
    authority: OwnedDatabase | SharedTables
    prepare_sql: str


def parse_roles(value, admin, contract):
    require(contract["schemaVersion"] == 2, "CONTRACT_VERSION_INVALID")
    require(set(contract["encodings"]) == {encoding.value for encoding in CredentialEncoding}, "ENCODING_HANDLER_SET_MISMATCH")
    # Temporary expand/read compatibility. Remove when active home/work role
    # configs both prove schemaVersion2 in domain-exposure-review/plan.md
    # (https://refinery.hwc.iheartwoodcraft.com/project/brain-o7xth7).
    if isinstance(value, dict) and "schemaVersion" not in value:
        value = {"schemaVersion": 2, "roles": {
            name: {"credential": {"password": name}, "authority": {"owned": spec}, "prepareSql": ""}
            for name, spec in value.items()
        }}
    require(isinstance(value, dict) and set(value) == {"schemaVersion", "roles"}
            and value["schemaVersion"] == contract["schemaVersion"], "CONFIG_VERSION_INVALID")
    value = value["roles"]
    limits = contract["limits"]
    require(isinstance(value, dict) and 0 < len(value) <= limits["roles"], "ROLE_COUNT_BOUND")
    safe = re.compile(r"[a-z_][a-z0-9_]{0,62}\Z")
    roles = []
    for name, spec in value.items():
        require(bool(safe.fullmatch(name)), "ROLE_NAME_INVALID")
        require(name not in {admin, "postgres"} and not name.startswith("pg_"), "ADMIN_ROLE_FORBIDDEN")
        require(isinstance(spec, dict) and set(spec) == {"credential", "authority", "prepareSql"}, "ROLE_SPEC_INVALID")
        credential = spec["credential"]
        require(isinstance(credential, dict) and len(credential) == 1, "CREDENTIAL_TAG_INVALID")
        if set(credential) == {"password"}:
            require(isinstance(credential["password"], str), "CREDENTIAL_SECRET_INVALID")
            source = RawPassword()
        else:
            require(set(credential) == {"environment"}, "CREDENTIAL_TAG_INVALID")
            env = credential["environment"]
            require(isinstance(env, dict) and set(env) == {"secret", "field", "encoding"}, "ENV_SPEC_INVALID")
            require(isinstance(env["secret"], str) and isinstance(env["field"], str)
                    and re.fullmatch(r"[A-Z_][A-Z0-9_]*", env["field"]), "ENV_FIELD_INVALID")
            require(env["encoding"] in contract["encodings"], "ENV_ENCODING_INVALID")
            source = EnvironmentPassword(env["field"], CredentialEncoding(env["encoding"]))
        tag = spec["authority"]
        require(isinstance(tag, dict) and len(tag) == 1, "AUTHORITY_TAG_INVALID")
        if set(tag) == {"owned"}:
            owned = tag["owned"]
            require(isinstance(owned, dict) and set(owned) == {"schemas", "takeOwnershipFrom"}, "OWNED_SPEC_INVALID")
            schemas = owned["schemas"]
            require(isinstance(schemas, list) and 0 < len(schemas) <= limits["schemas"], "SCHEMA_COUNT_BOUND")
            require(all(isinstance(s, str) and safe.fullmatch(s) for s in schemas), "SCHEMA_NAME_INVALID")
            require(len(set(schemas)) == len(schemas), "DUPLICATE_SCHEMA")
            previous = owned["takeOwnershipFrom"]
            require(previous is None or isinstance(previous, str) and safe.fullmatch(previous), "PREVIOUS_OWNER_INVALID")
            require(previous != name, "PREVIOUS_OWNER_IS_TARGET")
            authority = OwnedDatabase(name, tuple(schemas), previous)
        else:
            require(set(tag) == {"shared"}, "AUTHORITY_TAG_INVALID")
            shared = tag["shared"]
            require(isinstance(shared, dict) and set(shared) == {"database", "tables"}, "SHARED_SPEC_INVALID")
            require(isinstance(shared["database"], str) and bool(safe.fullmatch(shared["database"])), "DATABASE_NAME_INVALID")
            tables = shared["tables"]
            require(isinstance(tables, dict) and 0 < len(tables) <= limits["tables"], "TABLE_COUNT_BOUND")
            grants = []
            for identity, privileges in sorted(tables.items()):
                parts = identity.split(".")
                require(len(parts) == 2 and all(safe.fullmatch(p) for p in parts), "TABLE_NAME_INVALID")
                require(isinstance(privileges, dict) and set(privileges) == set(contract["privileges"]), "PRIVILEGE_SPEC_INVALID")
                operations = []
                for verb, columns in privileges.items():
                    require(isinstance(columns, list) and len(columns) <= limits["columns"], "COLUMN_COUNT_BOUND")
                    require(all(isinstance(c, str) and safe.fullmatch(c) for c in columns), "COLUMN_NAME_INVALID")
                    require(len(columns) == len(set(columns)), "DUPLICATE_COLUMN")
                    if columns:
                        operations.append((verb, tuple(columns)))
                require(bool(operations), "EMPTY_TABLE_GRANT")
                grants.append((*parts, tuple(operations)))
            authority = SharedTables(shared["database"], tuple(grants))
        prepare = spec["prepareSql"]
        require(isinstance(prepare, str) and len(prepare.encode()) <= limits["sqlBytes"], "PREPARE_SQL_BOUND")
        roles.append(Role(name, source, authority, prepare))
    return tuple(roles)


def password_from_credential(raw, role, byte_bound):
    require(len(raw) <= byte_bound, "CREDENTIAL_BYTE_BOUND")
    password = raw
    if isinstance(role.credential, EnvironmentPassword):
        values = []
        for line in raw.decode("ascii").splitlines():
            key, separator, value = line.partition("=")
            if separator and key == role.credential.field:
                values.append(value)
        require(len(values) == 1, "ENV_FIELD_MISSING_OR_DUPLICATE")
        password = values[0].encode("ascii")
        if role.credential.encoding == CredentialEncoding.POSTGRESQL_URL:
            parsed = urlsplit(values[0])
            require(parsed.scheme in {"postgresql", "postgres"}
                    and unquote(parsed.username or "") == role.name
                    and unquote(parsed.path) == "/" + role.authority.database, "DATABASE_URL_IDENTITY_MISMATCH")
            password = unquote(parsed.password or "").encode("ascii")
        else:
            require(role.credential.encoding == CredentialEncoding.PASSWORD, "ENCODING_HANDLER_MISSING")
    else:
        require(isinstance(role.credential, RawPassword), "CREDENTIAL_HANDLER_MISSING")
    require(bool(re.fullmatch(rb"[A-Za-z0-9_-]{64}", password)), "PASSWORD_FORMAT_INVALID")
    return password


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
) objects ORDER BY CASE kind WHEN 'TABLE' THEN 0 ELSE 1 END, identity LIMIT %s
"""


class BoundedCursor:
    def __init__(self, cursor, limit):
        self.cursor = cursor
        self.remaining = limit

    def execute(self, query, parameters=None):
        require(self.remaining > 0, "SQL_OPERATION_BOUND")
        self.remaining -= 1
        return self.cursor.execute(query, parameters)

    def __getattr__(self, name):
        return getattr(self.cursor, name)


def shared_authority(cursor, role, limit):
    """Reconcile this role's direct authority, preserving every shared owner."""
    name, authority = role.name, role.authority
    cursor.execute("SELECT EXISTS(SELECT 1 FROM pg_database WHERE datdba=%s::regrole) OR EXISTS(SELECT 1 FROM pg_namespace WHERE nspowner=%s::regrole) OR EXISTS(SELECT 1 FROM pg_class WHERE relowner=%s::regrole) OR EXISTS(SELECT 1 FROM pg_proc WHERE proowner=%s::regrole) OR EXISTS(SELECT 1 FROM pg_type WHERE typowner=%s::regrole)", (name,) * 5)
    require(cursor.fetchone() == (False,), "SHARED_ROLE_OWNS_OBJECTS")
    cursor.execute("SELECT EXISTS(SELECT 1 FROM pg_shdepend WHERE refclassid='pg_authid'::regclass AND refobjid=%s::regrole AND dbid<>0 AND dbid<>(SELECT oid FROM pg_database WHERE datname=current_database()))", (name,))
    require(cursor.fetchone() == (False,), "SHARED_ROLE_HAS_OTHER_DATABASE_AUTHORITY")
    cursor.execute("SELECT nspname FROM pg_namespace WHERE nspname !~ '^pg_' AND nspname<>'information_schema' ORDER BY nspname LIMIT %s", (limit + 1,))
    schemas = [row[0] for row in cursor.fetchmany(limit + 1)]
    require(len(schemas) <= limit, "SHARED_SCHEMA_BOUND")
    cursor.execute("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=ANY(%s)", (schemas,))
    require(cursor.fetchone()[0] <= limit, "SHARED_OBJECT_BOUND")
    for schema in schemas:
        for objects in ("TABLES", "SEQUENCES", "ROUTINES"):
            cursor.execute(sql.SQL("REVOKE ALL PRIVILEGES ON ALL {} IN SCHEMA {} FROM {}").format(sql.SQL(objects), sql.Identifier(schema), sql.Identifier(name)))
        cursor.execute(sql.SQL("REVOKE ALL PRIVILEGES ON SCHEMA {} FROM {}").format(sql.Identifier(schema), sql.Identifier(name)))
    # Table-level REVOKE does not clear separately granted column privileges.
    cursor.execute("SELECT n.nspname,c.relname,a.attname FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=ANY(%s) AND a.attacl IS NOT NULL AND EXISTS(SELECT 1 FROM aclexplode(a.attacl) x WHERE x.grantee=%s::regrole) LIMIT %s", (schemas, name, limit + 1))
    columns = cursor.fetchmany(limit + 1)
    require(len(columns) <= limit, "COLUMN_ACL_BOUND")
    for schema, table, column in columns:
        cursor.execute(sql.SQL("REVOKE ALL PRIVILEGES ({}) ON TABLE {}.{} FROM {}").format(sql.Identifier(column), sql.Identifier(schema), sql.Identifier(table), sql.Identifier(name)))
    # Remove direct default grants too; otherwise newly created tables regain
    # the old broad access after this service has finished.
    cursor.execute("SELECT pg_get_userbyid(d.defaclrole),n.nspname,d.defaclobjtype FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace WHERE EXISTS(SELECT 1 FROM aclexplode(d.defaclacl) x WHERE x.grantee=%s::regrole) LIMIT %s", (name, limit + 1))
    defaults = cursor.fetchmany(limit + 1)
    require(len(defaults) <= limit, "DEFAULT_ACL_BOUND")
    object_kinds = {"r": "TABLES", "S": "SEQUENCES", "f": "FUNCTIONS", "T": "TYPES", "n": "SCHEMAS"}
    for owner, schema, kind in defaults:
        require(kind in object_kinds, "DEFAULT_ACL_KIND_INVALID")
        scope = sql.SQL("") if schema is None else sql.SQL(" IN SCHEMA {}").format(sql.Identifier(schema))
        cursor.execute(sql.SQL("ALTER DEFAULT PRIVILEGES FOR ROLE {}{} REVOKE ALL PRIVILEGES ON {} FROM {}").format(sql.Identifier(owner), scope, sql.SQL(object_kinds[kind]), sql.Identifier(name)))
    cursor.execute(sql.SQL("REVOKE ALL PRIVILEGES ON DATABASE {} FROM {}").format(sql.Identifier(authority.database), sql.Identifier(name)))
    cursor.execute(sql.SQL("GRANT CONNECT ON DATABASE {} TO {}").format(sql.Identifier(authority.database), sql.Identifier(name)))
    for schema in sorted({schema for schema, _, _ in authority.tables}):
        cursor.execute(sql.SQL("GRANT USAGE ON SCHEMA {} TO {}").format(sql.Identifier(schema), sql.Identifier(name)))
    for schema, table, privileges in authority.tables:
        identity = sql.Identifier(schema, table)
        for verb, columns in privileges:
            cursor.execute(sql.SQL("GRANT {} ({}) ON TABLE {} TO {}").format(sql.SQL(verb.upper()), sql.SQL(",").join(map(sql.Identifier, columns)), identity, sql.Identifier(name)))
        if any(verb == "insert" for verb, _ in privileges):
            relation = identity.as_string(cursor.cursor)
            cursor.execute("SELECT pg_get_serial_sequence(%s,a.attname) FROM pg_attribute a WHERE a.attrelid=%s::regclass AND a.attnum>0 AND NOT a.attisdropped", (relation, relation))
            for (sequence,) in cursor.fetchall():
                if sequence:
                    cursor.execute(sql.SQL("GRANT USAGE ON SEQUENCE {} TO {}").format(sql.SQL(sequence), sql.Identifier(name)))
    # PUBLIC and memberships cannot be negated per role. Refuse an unexpected
    # schema-creation or security-definer path rather than claiming confinement.
    cursor.execute("SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname=ANY(%s) AND has_schema_privilege(%s,oid,'CREATE')) OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname=ANY(%s) AND p.prosecdef AND has_function_privilege(%s,p.oid,'EXECUTE'))", (schemas, name, schemas, name))
    require(cursor.fetchone() == (False,), "SHARED_ROLE_PUBLIC_AUTHORITY_REQUIRES_REVIEW")


def provision(connect, roles, read_password, operation_limit):
    results = []
    for role in sorted(roles, key=lambda role: role.name):
        name, authority = role.name, role.authority
        password = read_password(role)
        with connect(authority.database) as connection:
            with connection.cursor() as native_cursor:
                cursor = BoundedCursor(native_cursor, operation_limit)
                cursor.execute("SET LOCAL lock_timeout='2s'; SET LOCAL statement_timeout='30s'")
                if isinstance(authority, OwnedDatabase):
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
                if role.prepare_sql:
                    # Trusted application-owned source, bounded before entry;
                    # DDL and authority changes share this database transaction.
                    cursor.execute(role.prepare_sql)
                operations = []
                if isinstance(authority, SharedTables):
                    shared_authority(cursor, role, operation_limit)
                elif authority.previous is not None:
                    cursor.execute(OWNER_OPERATIONS, (authority.previous, list(authority.schemas)) * 3 + (operation_limit + 1,))
                    operations = cursor.fetchmany(operation_limit + 1)
                    require(len(operations) <= operation_limit, "OWNER_OPERATION_BOUND")
                    for kind, identity in operations:
                        require(kind in {"TABLE", "SEQUENCE", "VIEW", "MATERIALIZED VIEW", "TYPE", "FUNCTION", "PROCEDURE"}, "OWNER_KIND_INVALID")
                        cursor.execute(sql.SQL("ALTER {} {} OWNER TO {}").format(sql.SQL(kind), sql.SQL(identity), sql.Identifier(name)))
        results.append({"role": name, "passwordChanged": changed, "ownershipOperations": len(operations), "authority": "shared" if isinstance(authority, SharedTables) else "owned"})
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=Path)
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--socket", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--admin-role", required=True)
    args = parser.parse_args()
    try:
        contract = json.loads(args.contract.read_text())
        roles = parse_roles(json.loads(args.config.read_text()), args.admin_role, contract)
        credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])

        def connect(database):
            return psycopg.connect(
                dbname=database, user=args.admin_role, host=args.socket,
                port=args.port, connect_timeout=5,
                options="-c log_statement=none -c log_min_duration_statement=-1 "
                        "-c log_min_error_statement=panic -c log_parameter_max_length_on_error=0",
            )

        def read_password(role):
            with (credentials / role.name).open("rb") as handle:
                raw = handle.read(contract["limits"]["credentialBytes"] + 1)
            return password_from_credential(raw, role, contract["limits"]["credentialBytes"])

        print(json.dumps({"passed": True, "roles": provision(connect, roles, read_password, contract["limits"]["operations"])}))
    except (psycopg.Error, ContractError, OSError, ValueError, KeyError) as error:
        print(json.dumps({"passed": False, "code": getattr(error, "sqlstate", None) or getattr(error, "code", None) or "ROLE_OPERATION_FAILED"}), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
