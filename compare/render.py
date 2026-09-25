#!/usr/bin/env python3
"""Renders compare/cases.json with real Jinja2; prints JSON lines:
{"name": ..., "output": ..., "error": ...}
"""
import json
import sys
from jinja2 import Environment, DictLoader, StrictUndefined, Undefined

cases_path = sys.argv[1] if len(sys.argv) > 1 else "compare/cases.json"
with open(cases_path) as f:
    cases = json.load(f)

for case in cases:
    name = case["name"]
    env_opts = case.get("env", {})
    env = Environment(
        loader=DictLoader(case.get("templates", {})),
        extensions=["jinja2.ext.do"],
        trim_blocks=env_opts.get("trim_blocks", False),
        lstrip_blocks=env_opts.get("lstrip_blocks", False),
        keep_trailing_newline=env_opts.get("keep_trailing_newline", False),
        autoescape=env_opts.get("autoescape", False),
        undefined=StrictUndefined if env_opts.get("undefined") == "strict" else Undefined,
    )
    try:
        template = env.from_string(case["template"])
        output = template.render(case["data"])
        print(json.dumps({"name": name, "output": output, "error": None}))
    except Exception as e:  # noqa: BLE001 - we record errors as results
        error_kind = "undefined" if type(e).__name__ == "UndefinedError" else "runtime"
        print(json.dumps({"name": name, "output": None, "error": f"{type(e).__name__}: {e}",
                          "error_kind": error_kind}))
