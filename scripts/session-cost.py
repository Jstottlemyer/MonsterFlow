#!/usr/bin/env python3
"""Session cost tracker for Claude Code.

Reads ~/.claude/projects/<sanitized-cwd>/*.jsonl and reports token usage cost
for the current session (most recently modified JSONL) and today.

Called from /wrap to show end-of-session cost summary.
No external deps. Python 3.9+.
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path


PRICING = {
    'claude-opus-4-6':   {'in': 5e-6,    'out': 25e-6, 'cw': 6.25e-6,  'cr': 0.5e-6,   'fast': 6},
    'claude-opus-4-5':   {'in': 5e-6,    'out': 25e-6, 'cw': 6.25e-6,  'cr': 0.5e-6,   'fast': 1},
    'claude-opus-4-1':   {'in': 15e-6,   'out': 75e-6, 'cw': 18.75e-6, 'cr': 1.5e-6,   'fast': 1},
    'claude-opus-4':     {'in': 15e-6,   'out': 75e-6, 'cw': 18.75e-6, 'cr': 1.5e-6,   'fast': 1},
    'claude-sonnet-4-6': {'in': 3e-6,    'out': 15e-6, 'cw': 3.75e-6,  'cr': 0.3e-6,   'fast': 1},
    'claude-sonnet-4-5': {'in': 3e-6,    'out': 15e-6, 'cw': 3.75e-6,  'cr': 0.3e-6,   'fast': 1},
    'claude-sonnet-4':   {'in': 3e-6,    'out': 15e-6, 'cw': 3.75e-6,  'cr': 0.3e-6,   'fast': 1},
    'claude-3-7-sonnet': {'in': 3e-6,    'out': 15e-6, 'cw': 3.75e-6,  'cr': 0.3e-6,   'fast': 1},
    'claude-3-5-sonnet': {'in': 3e-6,    'out': 15e-6, 'cw': 3.75e-6,  'cr': 0.3e-6,   'fast': 1},
    'claude-haiku-4-5':  {'in': 1e-6,    'out': 5e-6,  'cw': 1.25e-6,  'cr': 0.1e-6,   'fast': 1},
    'claude-3-5-haiku':  {'in': 0.8e-6,  'out': 4e-6,  'cw': 1e-6,     'cr': 0.08e-6,  'fast': 1},
}
WEB_SEARCH_COST = 0.01


def canonical_model(name):
    name = re.sub(r'-\d{8}$', '', name or '')
    name = re.sub(r'^.*/', '', name)
    name = re.sub(r'\[.*?\]$', '', name)
    return name


def get_pricing(model):
    canon = canonical_model(model)
    if canon in PRICING:
        return PRICING[canon]
    for k, v in PRICING.items():
        if canon.startswith(k):
            return v
    return None


def project_dir():
    cwd = os.getcwd()
    config_dir = os.environ.get('CLAUDE_CONFIG_DIR', os.path.expanduser('~/.claude'))
    sanitized = cwd.replace('/', '-')
    return Path(config_dir) / 'projects' / sanitized


def find_session_files(pdir):
    return sorted(pdir.glob('*.jsonl'), key=lambda p: p.stat().st_mtime)


def parse_entries(path):
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def entry_cost(entry):
    msg = entry.get('message') or {}
    usage = msg.get('usage') or {}
    p = get_pricing(msg.get('model'))
    if not p:
        return 0.0
    mult = p['fast'] if usage.get('speed') == 'fast' else 1
    base = (
        usage.get('input_tokens', 0) * p['in']
        + usage.get('output_tokens', 0) * p['out']
        + usage.get('cache_creation_input_tokens', 0) * p['cw']
        + usage.get('cache_read_input_tokens', 0) * p['cr']
    )
    srv = usage.get('server_tool_use') or {}
    base += srv.get('web_search_requests', 0) * WEB_SEARCH_COST
    return base * mult


def is_assistant_with_usage(entry):
    msg = entry.get('message') or {}
    return msg.get('role') == 'assistant' and bool(msg.get('usage'))


def is_today_local(entry):
    ts = entry.get('timestamp')
    if not ts:
        return False
    try:
        dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
    except ValueError:
        return False
    return dt.astimezone().date() == datetime.now().astimezone().date()


def fmt_cost(x):
    return f"${x:,.2f}"


def fmt_tokens(n):
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.0f}k"
    return str(n)


def summarize(entries):
    cost = 0.0
    calls = 0
    inp = out = cw = cr = 0
    models = {}
    for e in entries:
        if not is_assistant_with_usage(e):
            continue
        c = entry_cost(e)
        cost += c
        calls += 1
        u = (e.get('message') or {}).get('usage') or {}
        inp += u.get('input_tokens', 0)
        out += u.get('output_tokens', 0)
        cw  += u.get('cache_creation_input_tokens', 0)
        cr  += u.get('cache_read_input_tokens', 0)
        m = canonical_model((e.get('message') or {}).get('model'))
        models[m] = models.get(m, 0) + c
    denom = inp + cr
    cache_hit = (cr / denom * 100) if denom else 0.0
    return {
        'cost': cost, 'calls': calls,
        'in': inp, 'out': out, 'cw': cw, 'cr': cr,
        'cache_hit_pct': cache_hit,
        'models': models,
    }


def dedup_iter(paths):
    seen = set()
    for p in paths:
        for e in parse_entries(p):
            mid = (e.get('message') or {}).get('id')
            if mid:
                if mid in seen:
                    continue
                seen.add(mid)
            yield e


def main():
    ap = argparse.ArgumentParser(description='Claude Code session cost summary')
    ap.add_argument('--session-only', action='store_true', help='show only current session')
    ap.add_argument('--json', action='store_true', help='emit JSON instead of text')
    ap.add_argument('--cumulative-only', action='store_true',
                    help='output exactly one integer (cents, today cumulative) on stdout; exit 1 if no session data')
    args = ap.parse_args()

    pdir = project_dir()
    if not pdir.exists():
        print(f"No Claude Code project data at {pdir}", file=sys.stderr)
        return 1

    files = find_session_files(pdir)
    if not files:
        print(f"No session files in {pdir}", file=sys.stderr)
        return 1

    # --cumulative-only: emit a single integer (cents) representing today's
    # cumulative cost across all session files, then exit.
    if args.cumulative_only:
        today_entries = (e for e in dedup_iter(files) if is_today_local(e))
        today_summary = summarize(today_entries)
        cents = int(round(today_summary['cost'] * 100))
        print(cents)
        return 0

    session_path = files[-1]  # most recently modified
    session_summary = summarize(dedup_iter([session_path]))

    today_summary = None
    if not args.session_only:
        today_entries = (e for e in dedup_iter(files) if is_today_local(e))
        today_summary = summarize(today_entries)

    if args.json:
        out = {'session': session_summary, 'session_file': str(session_path)}
        if today_summary is not None:
            out['today'] = today_summary
        print(json.dumps(out, indent=2))
        return 0

    s = session_summary
    total_in = s['in'] + s['cw'] + s['cr']
    print("=== Session Cost ===")
    print(
        f"Session: {fmt_cost(s['cost']):>8}  "
        f"({s['calls']} calls · {fmt_tokens(total_in)} in / {fmt_tokens(s['out'])} out · "
        f"{s['cache_hit_pct']:.0f}% cache hit)"
    )
    if today_summary is not None:
        t = today_summary
        print(f"Today:   {fmt_cost(t['cost']):>8}  ({t['calls']} calls)")
    return 0


if __name__ == '__main__':
    sys.exit(main())
