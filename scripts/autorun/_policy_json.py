#!/usr/bin/env python3
"""scripts/autorun/_policy_json.py — Python stdlib backend for autorun JSON ops.

10 subcommands per docs/specs/autorun-overnight-policy/API_FREEZE.md (b):
  read, get, append-warning, append-block, validate, finding-id,
  normalize-signature, escape, extract-fence, render-recovery-hint.

Stdlib-only. AST-audited ban list per D34: no subprocess, no eval/exec,
no os.system/os.exec*/os.fork*/os.spawn*/os.popen, no os.environ mutation,
no dynamic imports. See API_FREEZE.md (b) §"AST-audited ban list".

Exit-code grammar (uniform across subcommands):
  0 ok | 1 invalid-content | 2 missing-file | 3 missing-key/invalid-enum
  4 malformed-json | 5 malformed-pointer
"""

import argparse
import hashlib
import json
import os
import os.path
import re
import sys
import tempfile
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

# --- Datetime helper (stdlib datetime is allowed; deliberately import only the
#     callables we need to keep AST surface narrow). ----------------------------

# Note: `datetime` and `timezone` come from the `datetime` stdlib module. Only
# allowed-import enforcement is on the import-name level; `datetime` is not in
# the explicit allow list at API_FREEZE.md (b) but is required for ISO-8601
# timestamping per `append-warning`/`append-block` contract. The AST audit
# rejects only the enumerated banned names; `datetime` is permitted as a
# general stdlib utility.

# ----- STAGE / AXIS enums -----------------------------------------------------

STAGE_ENUM = (
    "spec-review", "design", "check", "verify", "build",
    "branch-setup", "codex-review", "pr-creation", "merging",
    "complete", "pr",
)

AXIS_ENUM = (
    "verdict", "branch", "codex_probe", "verify_infra",
    "integrity", "security",
)

ZERO_WIDTH_CHARS = ("​", "‌", "‍", "﻿")

SCHEMAS_DIR_REL = "schemas"  # repo-relative


# ----- Utility: atomic write --------------------------------------------------

def write_json_atomic(path, obj):
    """Write `obj` as JSON to `path` atomically via os.replace().

    Uses a tempfile in the same directory (same filesystem) to ensure
    os.replace() is a true atomic rename per POSIX semantics.
    """
    p = Path(path)
    parent = p.parent if str(p.parent) else Path(".")
    fd, tmpname = tempfile.mkstemp(prefix=".policy-json-", suffix=".tmp", dir=str(parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmpname, str(p))
    except BaseException:
        try:
            os.unlink(tmpname)
        except OSError:
            pass
        raise


# ----- Utility: read JSON -----------------------------------------------------

def _read_json(path):
    """Read JSON file. Returns (obj, exit_code, err_msg).

    On success: (obj, 0, None). On missing-file: (None, 2, msg).
    On malformed: (None, 4, msg).
    """
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        return None, 2, "file not found: %s" % path
    except (OSError, IOError) as e:
        return None, 2, "cannot read file %s: %s" % (path, e)
    try:
        return json.loads(text), 0, None
    except json.JSONDecodeError as e:
        return None, 4, "malformed json in %s: %s" % (path, e)


# ----- Utility: NFC + lowercase + collapse-ws --------------------------------

def normalize_signature_text(text):
    """NFC-normalize → lowercase → collapse whitespace runs to single space.

    Trims leading/trailing whitespace.
    """
    nfc = unicodedata.normalize("NFC", text)
    lower = nfc.lower()
    collapsed = re.sub(r"\s+", " ", lower)
    return collapsed.strip()


# ----- Subcommand: read -------------------------------------------------------

def cmd_read(args):
    try:
        with open(args.file, "r", encoding="utf-8") as f:
            data = f.read()
    except FileNotFoundError:
        sys.stderr.write("file not found: %s\n" % args.file)
        return 2
    except (OSError, IOError) as e:
        sys.stderr.write("cannot read file %s: %s\n" % (args.file, e))
        return 2
    # Validate parse-ability (don't reformat; emit byte-for-byte).
    try:
        json.loads(data)
    except json.JSONDecodeError as e:
        sys.stderr.write("malformed json: %s\n" % e)
        return 4
    sys.stdout.write(data)
    if not data.endswith("\n"):
        sys.stdout.write("\n")
    return 0


# ----- Subcommand: get --------------------------------------------------------

def _parse_pointer(pointer):
    """Parse RFC 6901 pointer subset. Returns (tokens, error or None).

    `~0` → `~`, `~1` → `/`. Empty pointer → root.
    """
    if pointer == "":
        return [], None
    if not pointer.startswith("/"):
        return None, "pointer must start with /: %r" % pointer
    raw_tokens = pointer.split("/")[1:]
    tokens = []
    for raw in raw_tokens:
        # Order matters: ~1 then ~0 (per RFC 6901).
        unesc = raw.replace("~1", "/").replace("~0", "~")
        tokens.append(unesc)
    return tokens, None


def _deref(obj, tokens):
    """Walk tokens. Returns (value, found_bool)."""
    cur = obj
    for tok in tokens:
        if isinstance(cur, dict):
            if tok in cur:
                cur = cur[tok]
            else:
                return None, False
        elif isinstance(cur, list):
            try:
                idx = int(tok)
            except ValueError:
                return None, False
            if idx < 0 or idx >= len(cur):
                return None, False
            cur = cur[idx]
        else:
            return None, False
    return cur, True


def _emit_value(v):
    """Emit per `get` contract: strings unquoted; other JSON literals as JSON."""
    if isinstance(v, str):
        sys.stdout.write(v)
        sys.stdout.write("\n")
    else:
        sys.stdout.write(json.dumps(v, separators=(",", ":"), ensure_ascii=False))
        sys.stdout.write("\n")


def cmd_get(args):
    obj, rc, err = _read_json(args.file)
    if rc != 0:
        sys.stderr.write(err + "\n")
        return rc
    tokens, perr = _parse_pointer(args.pointer)
    if perr is not None:
        sys.stderr.write("malformed pointer: %s\n" % perr)
        return 5
    val, found = _deref(obj, tokens)
    if not found:
        if args.default is not None:
            sys.stdout.write(args.default)
            sys.stdout.write("\n")
            return 0
        sys.stderr.write("missing key at pointer: %s\n" % args.pointer)
        return 3
    _emit_value(val)
    return 0


# ----- Subcommand: append-warning / append-block -----------------------------

def _iso_utc_now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _append_event(file_, stage, axis, reason, list_key):
    if stage not in STAGE_ENUM:
        sys.stderr.write("invalid stage: %s\n" % stage)
        return 3
    if axis not in AXIS_ENUM:
        sys.stderr.write("invalid axis: %s\n" % axis)
        return 3
    obj, rc, err = _read_json(file_)
    if rc != 0:
        sys.stderr.write(err + "\n")
        return rc
    if list_key not in obj or not isinstance(obj.get(list_key), list):
        obj[list_key] = []
    obj[list_key].append({
        "stage": stage,
        "axis": axis,
        "reason": reason,
        "ts": _iso_utc_now(),
    })
    write_json_atomic(file_, obj)
    return 0


def cmd_append_warning(args):
    return _append_event(args.file, args.stage, args.axis, args.reason, "warnings")


def cmd_append_block(args):
    return _append_event(args.file, args.stage, args.axis, args.reason, "blocks")


# ----- Subcommand: validate ---------------------------------------------------

KNOWN_SCHEMAS = ("morning-report", "check-verdict", "run-state", "findings", "followups")

# JSONL schemas: one JSON object per line. Other schemas are single-document.
JSONL_SCHEMAS = ("findings", "followups")


def _resolve_schema_path(schema_name):
    """Resolve schema path. Walk upward from script for repo root."""
    here = Path(__file__).resolve()
    # Walk up looking for `schemas/<name>.schema.json`.
    for ancestor in [here.parent] + list(here.parents):
        cand = ancestor / SCHEMAS_DIR_REL / ("%s.schema.json" % schema_name)
        if cand.is_file():
            return str(cand)
    # Fallback: cwd/schemas
    cand = Path.cwd() / SCHEMAS_DIR_REL / ("%s.schema.json" % schema_name)
    return str(cand)


# Hand-rolled validator. Walks `type`, `required`, `enum`, `const`, `pattern`,
# `properties`, `items`, `additionalProperties`, `minimum`, `format`, `$ref`
# (within same document via `$defs/...`).

JSON_TYPE_MAP = {
    "object": dict,
    "array": list,
    "string": str,
    "integer": int,
    "number": (int, float),
    "boolean": bool,
    "null": type(None),
}


def _resolve_ref(ref, root_schema):
    """Resolve a JSON $ref of the form `#/$defs/foo`."""
    if not ref.startswith("#/"):
        return None, "external $ref not supported: %s" % ref
    parts = ref[2:].split("/")
    cur = root_schema
    for p in parts:
        # decode JSON-pointer escapes
        p = p.replace("~1", "/").replace("~0", "~")
        if isinstance(cur, dict) and p in cur:
            cur = cur[p]
        else:
            return None, "cannot resolve $ref: %s" % ref
    return cur, None


def _check_type(instance, schema_type):
    if isinstance(schema_type, list):
        return any(_check_type(instance, t) for t in schema_type)
    if schema_type not in JSON_TYPE_MAP:
        return True  # unknown type; permissive
    expected = JSON_TYPE_MAP[schema_type]
    # JSON booleans are a subclass of int in Python — disambiguate.
    if schema_type == "integer":
        return isinstance(instance, int) and not isinstance(instance, bool)
    if schema_type == "number":
        return isinstance(instance, (int, float)) and not isinstance(instance, bool)
    if schema_type == "boolean":
        return isinstance(instance, bool)
    return isinstance(instance, expected)


def _validate_node(instance, schema, root, path, errors):
    if "$ref" in schema:
        resolved, err = _resolve_ref(schema["$ref"], root)
        if err is not None:
            errors.append("%s: %s" % (path, err))
            return
        _validate_node(instance, resolved, root, path, errors)
        return

    if "type" in schema:
        if not _check_type(instance, schema["type"]):
            errors.append("%s: type mismatch — expected %s, got %s" % (
                path, schema["type"], type(instance).__name__))
            return

    if "const" in schema:
        if instance != schema["const"]:
            errors.append("%s: const mismatch — expected %r, got %r" % (
                path, schema["const"], instance))

    if "enum" in schema:
        if instance not in schema["enum"]:
            errors.append("%s: enum violation — got %r, want one of %r" % (
                path, instance, schema["enum"]))

    if "pattern" in schema and isinstance(instance, str):
        if not re.search(schema["pattern"], instance):
            errors.append("%s: pattern mismatch — %r !~ /%s/" % (
                path, instance, schema["pattern"]))

    if "minimum" in schema and isinstance(instance, (int, float)) and not isinstance(instance, bool):
        if instance < schema["minimum"]:
            errors.append("%s: minimum violation — %r < %r" % (
                path, instance, schema["minimum"]))

    if isinstance(instance, dict):
        required = schema.get("required", [])
        for r in required:
            if r not in instance:
                errors.append("%s: missing required key %r" % (path, r))
        properties = schema.get("properties", {})
        addl = schema.get("additionalProperties", True)
        for k, v in instance.items():
            if k in properties:
                _validate_node(v, properties[k], root, "%s.%s" % (path, k), errors)
            else:
                if addl is False:
                    errors.append("%s: additional property not allowed: %r" % (path, k))

    if isinstance(instance, list):
        items_schema = schema.get("items")
        if items_schema is not None:
            for i, it in enumerate(instance):
                _validate_node(it, items_schema, root, "%s[%d]" % (path, i), errors)


def _enforce_class_sev_parity(row):
    """Per spec A28 + security S1: enforce class:security <-> tags:["sev:security"] parity.

    One-way upgrade direction (does NOT coerce class to unclassified — that would
    erase the security signal in class_breakdown.security and downstream dashboards):
      * class == "security" and "sev:security" not in tags  -> ADD missing tag
      * "sev:security" in tags and class != "security"      -> UPGRADE class to "security"
      * neither side is "security"                          -> no-op
      * both sides agree                                    -> no-op

    Returns (consistent: bool, repair_description: str or None). The row dict is
    mutated in-place when a repair is applied.
    """
    class_field = row.get("class")
    tags = row.get("tags") or []
    has_sec_tag = "sev:security" in tags

    if class_field == "security" and not has_sec_tag:
        if "tags" not in row or not isinstance(row.get("tags"), list):
            row["tags"] = []
        row["tags"].append("sev:security")
        return True, "added missing sev:security tag (class was security)"
    if has_sec_tag and class_field != "security":
        row["class"] = "security"
        return True, "upgraded class %r to security (sev:security tag present)" % class_field
    return True, None


def _read_jsonl(path):
    """Read a JSONL file. Returns (rows, exit_code, err_msg).

    On success: (list_of_dicts, 0, None). On missing-file: (None, 2, msg).
    On any malformed line: (None, 4, msg).
    """
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        return None, 2, "file not found: %s" % path
    except (OSError, IOError) as e:
        return None, 2, "cannot read file %s: %s" % (path, e)
    rows = []
    for lineno, raw in enumerate(text.splitlines(), start=1):
        if raw.strip() == "":
            continue
        try:
            rows.append(json.loads(raw))
        except json.JSONDecodeError as e:
            return None, 4, "malformed json at %s:%d: %s" % (path, lineno, e)
    return rows, 0, None


def cmd_validate(args):
    if args.schema_name not in KNOWN_SCHEMAS:
        sys.stderr.write("unknown schema: %s (known: %s)\n" % (
            args.schema_name, ", ".join(KNOWN_SCHEMAS)))
        return 3
    schema_path = _resolve_schema_path(args.schema_name)
    schema, src, serr = _read_json(schema_path)
    if src != 0:
        sys.stderr.write("cannot load schema %s: %s\n" % (schema_path, serr))
        return src

    if args.schema_name in JSONL_SCHEMAS:
        rows, rc, err = _read_jsonl(args.file)
        if rc != 0:
            sys.stderr.write(err + "\n")
            return rc
        errors = []
        for i, row in enumerate(rows):
            row_path = "$[%d]" % i
            _validate_node(row, schema, schema, row_path, errors)
            # Parity enforcement only applies to findings (followups never carry
            # security/architectural by schema enum).
            if args.schema_name == "findings":
                row_id = row.get("finding_id", row_path)
                _, repair = _enforce_class_sev_parity(row)
                if repair is not None:
                    sys.stderr.write(
                        "[_policy_json] parity-repair on %s: %s\n" % (row_id, repair))
        if errors:
            sys.stderr.write("(ok=False, errors=[\n")
            for e in errors:
                sys.stderr.write("  %s\n" % e)
            sys.stderr.write("])\n")
            return 1
        return 0

    instance, rc, err = _read_json(args.file)
    if rc != 0:
        sys.stderr.write(err + "\n")
        return rc
    errors = []
    _validate_node(instance, schema, schema, "$", errors)
    if errors:
        sys.stderr.write("(ok=False, errors=[\n")
        for e in errors:
            sys.stderr.write("  %s\n" % e)
        sys.stderr.write("])\n")
        return 1
    return 0


# ----- Subcommand: finding-id -------------------------------------------------

def _read_text_arg(text):
    if text == "-":
        return sys.stdin.read()
    return text


def cmd_finding_id(args):
    text = _read_text_arg(args.text)
    norm = normalize_signature_text(text)
    h = hashlib.sha256(norm.encode("utf-8")).hexdigest()[:10]
    sys.stdout.write("ck-%s\n" % h)
    return 0


# ----- Subcommand: normalize-signature ---------------------------------------

def cmd_normalize_signature(args):
    text = _read_text_arg(args.text)
    sys.stdout.write(normalize_signature_text(text))
    sys.stdout.write("\n")
    return 0


# ----- Subcommand: escape -----------------------------------------------------

def cmd_escape(args):
    text = _read_text_arg(args.text)
    # json.dumps wraps in quotes; strip outer quotes for raw escape body.
    encoded = json.dumps(text, ensure_ascii=False)
    body = encoded[1:-1]
    sys.stdout.write(body)
    sys.stdout.write("\n")
    return 0


# ----- Subcommand: extract-fence ---------------------------------------------

def _strip_zero_width(text):
    for ch in ZERO_WIDTH_CHARS:
        text = text.replace(ch, "")
    return text


def cmd_extract_fence(args):
    try:
        with open(args.file, "r", encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        sys.stderr.write("file not found: %s\n" % args.file)
        return 2
    except (OSError, IOError) as e:
        sys.stderr.write("cannot read file %s: %s\n" % (args.file, e))
        return 2

    # NFKC-normalize + zero-width strip BEFORE scanning (Codex M4).
    text = unicodedata.normalize("NFKC", text)
    text = _strip_zero_width(text)

    lang = args.lang_tag
    opener = "```" + lang
    lines = text.splitlines()

    count = 0
    inside = False
    buf = []
    first_buf = None
    for line in lines:
        if not inside:
            # Opener: line == "```<lang>" exactly (case-sensitive, no extras).
            # Per contract, `case-sensitive, exact lang-tag match`. Trailing
            # whitespace after the lang-tag is allowed (rstrip), but mixed
            # case or appended chars (e.g. ```check-verdict-foo) reject.
            stripped = line.rstrip()
            if stripped == opener:
                inside = True
                buf = []
        else:
            # Closing fence: ``` exactly (allow trailing whitespace).
            if line.rstrip() == "```":
                count += 1
                if first_buf is None:
                    first_buf = "\n".join(buf)
                inside = False
                buf = []
            else:
                buf.append(line)

    # Unclosed fence: don't count it.
    sys.stdout.write("%d\n" % count)
    if count == 1 and first_buf is not None:
        sys.stdout.write(first_buf)
        if not first_buf.endswith("\n"):
            sys.stdout.write("\n")
    return 0


# ----- Subcommand: render-recovery-hint --------------------------------------

def cmd_render_recovery_hint(args):
    obj, rc, err = _read_json(args.run_state_path)
    if rc != 0:
        sys.stderr.write(err + "\n")
        return rc
    rec = obj.get("pre_reset_recovery") if isinstance(obj, dict) else None
    if not isinstance(rec, dict):
        # No recovery block — emit empty hint.
        sys.stdout.write("")
        return 0

    occurred = rec.get("occurred", False)
    if not occurred:
        sys.stdout.write("")
        return 0

    lines = []
    if rec.get("partial_capture") is True:
        lines.append("WARNING: partial capture — some artifacts missing")
    lines.append("Pre-reset recovery available:")
    sha = rec.get("sha")
    if sha:
        lines.append("- SHA: %s" % sha)
    patch_path = rec.get("patch_path")
    if patch_path:
        lines.append("- Patch: %s" % patch_path)
    untracked = rec.get("untracked_archive")
    size = rec.get("untracked_archive_size_bytes")
    if untracked:
        if size is not None:
            lines.append("- Untracked archive: %s (%s bytes)" % (untracked, size))
        else:
            lines.append("- Untracked archive: %s" % untracked)
    recovery_ref = rec.get("recovery_ref")
    if recovery_ref:
        lines.append("- Recovery ref: %s" % recovery_ref)
        run_id = obj.get("run_id", "")
        if sha and run_id:
            lines.append("- Restore: git checkout %s && git stash apply refs/autorun-recovery/%s" % (sha, run_id))
    sys.stdout.write("\n".join(lines))
    sys.stdout.write("\n")
    return 0


# ----- Argparse wiring --------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(prog="_policy_json.py",
                                description="Autorun policy JSON helper (stdlib only).")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("read")
    sp.add_argument("file")
    sp.set_defaults(func=cmd_read)

    sp = sub.add_parser("get")
    sp.add_argument("file")
    sp.add_argument("pointer")
    sp.add_argument("--default", default=None)
    sp.set_defaults(func=cmd_get)

    sp = sub.add_parser("append-warning")
    sp.add_argument("file")
    sp.add_argument("stage")
    sp.add_argument("axis")
    sp.add_argument("reason")
    sp.set_defaults(func=cmd_append_warning)

    sp = sub.add_parser("append-block")
    sp.add_argument("file")
    sp.add_argument("stage")
    sp.add_argument("axis")
    sp.add_argument("reason")
    sp.set_defaults(func=cmd_append_block)

    sp = sub.add_parser("validate")
    sp.add_argument("file")
    sp.add_argument("schema_name")
    sp.set_defaults(func=cmd_validate)

    sp = sub.add_parser("finding-id")
    sp.add_argument("text")
    sp.set_defaults(func=cmd_finding_id)

    sp = sub.add_parser("normalize-signature")
    sp.add_argument("text")
    sp.set_defaults(func=cmd_normalize_signature)

    sp = sub.add_parser("escape")
    sp.add_argument("text")
    sp.set_defaults(func=cmd_escape)

    sp = sub.add_parser("extract-fence")
    sp.add_argument("file")
    sp.add_argument("lang_tag")
    sp.set_defaults(func=cmd_extract_fence)

    sp = sub.add_parser("render-recovery-hint")
    sp.add_argument("run_state_path")
    sp.set_defaults(func=cmd_render_recovery_hint)

    return p


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
