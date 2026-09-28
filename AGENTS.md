# AGENTS.md

## Project Overview

krikri-jinja is a **clean-room Jinja2 template engine in Crystal** (shard `krikri-jinja`). It is implemented from the Jinja2 Template Designer/Developer *documentation only* — never read or port from real Jinja2 source code. Behavior parity with real Jinja2 is instead verified empirically by the differential harness in `compare/`. Keep this clean-room discipline: the source-of-truth is the public spec, and correctness is measured by matching rendered output.

The primary consumer is the krikri-playbook project.

## Commands

```bash
just test             # unit/integration suite (257 tests, in spec/), parallel across 4 cores
just test-serial       # same suite, single-threaded (bisect: real bug vs. parallel-run race)
./compare/run.sh      # differential test vs real Jinja2 (140 cases); exits nonzero on divergence
```

- The suite runs on **minitest.cr**, not Crystal's built-in Spec (migrated 2026-09-27). `just test` builds with `-Dpreview_mt` and runs `CRYSTAL_WORKERS=4 ... --parallel 4`; see the `justfile` for the raw commands if you need to run outside `just`.
- Because specs run on real OS threads under `-Dpreview_mt`, any module-level mutable singleton (like `KrikriJinja.default_engine`) needs explicit synchronization — see the `RWLock`/`Mutex` usage in `src/krikri_jinja/evaluator.cr`, `src/krikri_jinja/context.cr`, and `src/krikri_jinja.cr`. A spec that mutates such a singleton (`reset_default_engine`, `register_default_*`) must be serialized against the others that touch it, the way `spec/krikri_jinja/default_engine_spec.cr` does with its own `Mutex` — minitest.cr has no built-in per-test serial tag.
- `./compare/run.sh` requires **python3 with the `jinja2` package installed** and regenerates `compare/cases.json` from `compare/gen_cases.py` on every run (so `cases.json` shows up as modified whenever `gen_cases.py` changes — that's expected, commit both together or as appropriate).
- The harness writes intermediate JSONL to `/tmp/krikri-jinja-{py,cr}.jsonl`.
- No CI config, no linter config. `crystal tool format` is not enforced by any config.

## Architecture / Data Flow

Straightforward pipeline in `src/`:

1. `lexer.cr` — tokenizes `{{ }}`, `{% %}`, `{# #}` (delimiters configurable per engine).
2. `parser.cr` — recursive-descent parser producing `nodes.cr` AST.
3. `evaluator.cr` — walks the AST and writes output to an `IO`. Also holds runtime classes: `LoopObject` / `LoopCallable` (the `loop` variable, incl. recursive `{{ loop(children) }}`), `MacroCallable`, `Markup` (autoescape-exempt strings).
4. `context.cr` — scoped variable lookup (stack of scopes + globals); missing names resolve to `Undefined`.
5. `filters.cr` / `tests.cr` — built-in filters (~45) and tests (~35) as `Hash(String, ...)`; custom ones are registered by mutating `BUILTIN_FILTERS` / `BUILTIN_TESTS`.
6. `globals.cr` — `range`, `dict`, `namespace`, `cycler`, `lipsum`.

Entry points: `KrikriJinja.render(source, vars)` for one-shot rendering, or `KrikriJinja::Engine.new(loader)` with `DictLoader` / `FileSystemLoader` for `extends`/`include`/`import`.

### Value model (the key thing to understand)

- **`AnyValue`** (in `nodes.cr`) is a JSON::Any-style wrapper around `AnyV` so arrays/hashes can be recursive — Crystal can't express that type alias. Nearly everything at render time is `AnyValue`; unwrap with `.raw`, re-wrap with `AnyValue.new(...)` or `AnyValue.wrap_deep` / `KrikriJinja.wrap_value` (deep-converts plain Crystal values) / `KrikriJinja.from_json_any`.
- **Python semantics are simulated**: `Undefined` stringifies to `""` but `nil` stringifies to `"None"`; `True`/`False`/`None` capitalization; Python floor-division/modulo sign behavior; `True == 1`; tuple values are a distinct `TupleValue` class (repr uses `(...)`) because `dictsort`/`items` must render with parentheses. Truthiness lives in `value_helpers.cr` (`truthy?`, `stringify`, `format_float` — matches Python float repr, e.g. integral floats get `.0`).
- `Undefined` is nil-based (no `StrictUndefined`); `value_helpers.undefined?` treats both `nil` and `Undefined` as undefined.

### Python-matching helpers in `src/krikri_jinja.cr`

`py_format` (Python %-formatting for the `format` filter), `percent_encode`/`quote_plus` (match `urllib.parse.quote`/`quote_plus`), `filesizeformat`. These exist because Crystal stdlib behavior differs from Python; extend these rather than inventing new formatting approaches.

## Testing

Two complementary layers:

1. **`spec/`** — minitest.cr specs asserting exact output strings. Style: `assert_equal(expected, KrikriJinja.render(template, context))`. Expected outputs are hand-written from the Jinja2 docs.
2. **`compare/` differential harness** — the real arbiter of parity:
   - `gen_cases.py` defines the corpus programmatically (`add(name, template, data=, templates=, **env)`); **add new cases here, not by editing cases.json** (it's generated).
   - `render.py` renders with real Jinja2 using the *same environment defaults* (`trim_blocks=false`, `keep_trailing_newline=false`, default `Undefined`).
   - `render.cr` renders the same cases with this engine (compared files passed as argv, JSONL in/out).
   - `compare.py` diffs: both-error counts as compatible (different exception vocabularies between engines); one-ok-one-error or any output byte difference is a divergence.
   - `cases.json` case shape: `{"name", "template", "data", optional "templates" (DictLoader map), optional "env" overrides}`.

Workflow for behavior changes: add a case to `gen_cases.py`, run `./compare/run.sh`, fix the engine until 140+/140+ pass, and keep the spec suite green too. Past divergences fixed this way are listed in the README — check it to avoid re-deriving known traps (e.g. filters bind tighter than unary minus, `map('name')` dispatch, `slice` pads to longest column).

## Known Gaps (don't file as bugs)

Not implemented, intentionally: `{% trans %}`/i18n, `spaceless`, `debug` tag, `StrictUndefined` semantics, `truncate` `nowrap`, `groupby` secondary-sort guarantees, `wordwrap` `break_long_words` tuning, custom filter/test classes beyond hash registration.

## Gotchas

- This is a clean-room project: **never consult Jinja2 implementation source**; use the Jinja2 docs and the differential harness for correctness.
- Integers are `Int64`, floats `Float64`; literal `Int32`s must be converted (see `wrap_value`). Numeric edge cases (division producing Float64 vs Int64, `//` and `%` sign behavior) must match Python exactly — the corpus covers `neg div mod` cases.
- Regex matching for float formatting/literals relies on scientific-notation support; the lexer handles hex/octal/binary int literals explicitly.
- Recursion in for-loops goes through `LoopCallable`, which pushes/pops context scopes and restores the outer `loop` binding in an `ensure` block — preserve that pattern when touching loop code.
- Macro bodies capture their defining `Context` (`closure`); `varargs`/`kwargs`/`caller` are supported. `{% call(x, y) macro() %}` passes caller-body parameters.
- Whitespace-control defaults mirror Jinja2 env defaults: `keep_trailing_newline` is false by default. The differential harness depends on these defaults staying aligned between `render.py` and the engine.
