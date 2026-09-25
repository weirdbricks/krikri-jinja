# krikri-jinja

A from-scratch Jinja2 template engine in Crystal, written as a clean-room
reimplementation for the krikri-playbook project.

## Clean-room basis

This implementation is written **from the Jinja2 Template Designer
Documentation and the Jinja2 Template Developer Documentation** - the public
specifications of what Jinja2 templates must mean - not from the source code
of any existing Jinja2 implementation. No implementation source was read or
referenced while writing the lexer, parser, or evaluator. Behavior is verified
against the documented semantics and against expected-output examples written
from the docs.

## Status (v0.3.1)

Implemented:

- Lexer for `{{ ... }}`, `{% ... %}`, `{# ... #}` with configurable delimiters
- Full expression grammar: arithmetic (`+ - * / // % **`), comparisons
  (including chained), `in` / `not in`, `is` / `is not` tests, `~` concat,
  filters with args/kwargs, attribute/item access, slicing (incl. step),
  calls with positional/keyword arguments and `*args` / `**kwargs` expansion,
  conditional expressions (`a if b else c`), list / dict / tuple literals,
  adjacent string concatenation
- Statements: `if/elif/else`, `for` (with `if` filter, `else`, unpacking),
  `set` (incl. `namespace` attribute assignment), `block` (incl. `super()`,
  `required`, and `scoped` modifiers), `macro` (with defaults), `call` (with
  `caller()`), `filter`, `with`, `include` (`ignore missing`, `with/without
  context`), `extends`, `import`/`from ... import`, `do`, `autoescape`
- `loop` variable: `index`, `index0`, `revindex`, `revindex0`, `first`,
  `last`, `length`, `previtem`, `nextitem`, `depth`, `depth0`
- 54 built-in filters (upper, lower, sort, map, select, groupby, batch,
  slice, join, default, tojson, ...) and 39 built-in tests
- Globals: `range`, `dict`, `namespace`, `cycler`, `joiner`, `lipsum`
- Template inheritance (multi-level `extends` + block override), includes,
  imports; `DictLoader` / `FileSystemLoader`
- Python-style semantics: truthiness, `True == 1`, floor division/modulo
  sign behavior, `None` stringification, CPython string repr, and
  arbitrary-precision integer arithmetic beyond `Int64`

Additional compatibility features:

- `{% raw %}` blocks (including `{%- raw -%}` marker forms)
- Whitespace control: `{{- -}}`, `{%- -%}` markers, `trim_blocks`,
  `lstrip_blocks`, `keep_trailing_newline` (default false, matching the
  documented environment default)
- Custom delimiters per engine (`block_start/end`, `var_start/end`,
  `comment_start/end`)
- Recursive `{% for %}` with `{{ loop(children) }}` recursion and
  `loop.depth`; `loop.cycle(...)` and `loop.changed(...)`
- Macro introspection: `varargs`, `kwargs`, `name`, `caller`
- `{% call(x, y) macro() %}` caller-body parameters
- `{% set x %}...{% endset %}` block form
- `{% include ['a.html', 'b.html'] %}` fallback lists
- `not` binds looser than comparisons (`not x in y` == `not (x in y)`)
- Hex/octal/binary integer literals
- Filters: `dictsort`, `filesizeformat`, `forceescape`, `center`, `random`,
  `pprint`, `urlize`, `int(base=)`, `unique(attribute=)`, `format` with full
  %-conversion support, `Markup`-aware `safe`/`escape` under autoescape
- Tests: `escaped`, `filter`, `test`, `sameas`
- `Engine#render(name)` for loader-based rendering, engine-level
  `autoescape`, and filter/test registration by mutating
  `BUILTIN_FILTERS` / `BUILTIN_TESTS`

Known gaps: `{% trans %}` / i18n (out of scope), `spaceless`,
`debug` tag, custom filter/test classes beyond hash registration,
`StrictUndefined` semantics (undefined is nil-based), `truncate`
`nowrap`, `groupby` secondary sort guarantees, `wordwrap`
`break_long_words` tuning, and complex results from negative fractional
powers such as `-5 ** 2.5`. Lazy filter generators are iterated by templates
but do not reproduce Python's process-specific `<generator ... at 0x...>`
repr. Integers beyond `Int64` use a dedicated runtime value type, so
digit-shaped strings remain ordinary strings.

## Usage

```crystal
require "krikri-jinja"

KrikriJinja.render("Hello {{ name | upper }}!", {"name" => "world"})
# => "Hello WORLD!"

engine = KrikriJinja::Engine.new(KrikriJinja::FileSystemLoader.new("templates"))
engine.render_string("{% extends 'base.html' %}")
```

## Differential testing against real Jinja2

`compare/` renders a shared case corpus with **both** real Jinja2 (via
`python3` with the `jinja2` package installed) and this engine, then diffs
the outputs byte for byte:

```bash
./compare/run.sh
# total: 1,990  identical: 1,749  both-error: 241  divergent: 0
```

- `compare/gen_cases.py` generates `cases.json` (1,990 cases: literals,
  arbitrary-precision arithmetic, filters, tests, statements, string and
  integer methods, whitespace control, raw blocks, inheritance/includes/
  imports, autoescape, recursive loops, and fuzz-class regressions)
- `compare/render.py` renders with real Jinja2 (same environment defaults:
  `trim_blocks=false`, `keep_trailing_newline=false`, default `Undefined`)
- `compare/render.cr` renders with krikri-jinja
- `compare/compare.py` diffs; both-error counts as compatible (the two
  engines use different exception vocabularies), one-ok-one-error or any
  output difference is a divergence
- `compare/fuzz_run.sh` runs generated multi-round sweeps and reports each
  completed seed. Render timeouts are reported as failed rounds while the
  sweep continues; Python outputs containing generator memory addresses are
  skipped, and any remaining addresses are normalized before comparison.

This harness found and fixed: undefined rendering as "" (not "None"),
filters binding tighter than unary minus, `map('filtername')` dispatch,
`min`/`max(attribute=)` returning the item, Python `round` semantics via
`sprintf`, string methods (`replace`, `split`, ...), tuple repr for
`dictsort`/`items`, Python-style `urlencode`, `slice` padding to the
longest column, `sum(start=)`, `indent(2, true)`, scientific-notation
literals, `{% raw %}` scanning past embedded `{%`, CPython string-repr
escaping, CPython `%`-format argument rules, lazy `slice` iteration,
arbitrary-precision integer semantics, empty `Markup` falsiness, safe
out-of-range negative indexing, bare test-argument and chained-`is`
parsing, and the constant-folding precedence trap for negative-literal-base
`**` expressions.

## Development

```bash
crystal spec        # run the unit/integration suite (193 specs)
./compare/run.sh    # differential test against real Jinja2 (1,990 cases)
./compare/fuzz_run.sh 8 3000 1000  # 8 fuzz rounds, starting at seed 1001
```
