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

## Status (v0.2.0)

Implemented:

- Lexer for `{{ ... }}`, `{% ... %}`, `{# ... #}` with configurable delimiters
- Full expression grammar: arithmetic (`+ - * / // % **`), comparisons
  (including chained), `in` / `not in`, `is` / `is not` tests, `~` concat,
  filters with args/kwargs, attribute/item access, slicing (incl. step),
  calls with args/kwargs, conditional expressions (`a if b else c`), list /
  dict / tuple literals, adjacent string concatenation
- Statements: `if/elif/else`, `for` (with `if` filter, `else`, unpacking),
  `set` (incl. `namespace` attribute assignment), `block`, `macro` (with
  defaults), `call` (with `caller()`), `filter`, `with`, `include`
  (`ignore missing`, `with/without context`), `extends`, `import`/`from
  ... import`, `do`, `autoescape`
- `loop` variable: `index`, `index0`, `revindex`, `revindex0`, `first`,
  `last`, `length`, `previtem`, `nextitem`, `depth`, `depth0`
- ~45 built-in filters (upper, lower, sort, map, select, groupby, batch,
  slice, join, default, tojson, ...) and ~35 built-in tests
- Globals: `range`, `dict`, `namespace`, `cycler`, `lipsum`
- Template inheritance (multi-level `extends` + block override), includes,
  imports; `DictLoader` / `FileSystemLoader`
- Python-style semantics: truthiness, `True == 1`, floor division/modulo
  sign behavior, `None` stringification

Implemented on top of v0.1.0:

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
  `pprint`, `int(base=)`, `unique(attribute=)`, `format` with full
  %-conversion support, `Markup`-aware `safe`/`escape` under autoescape
- Tests: `escaped`, `filter`, `test`, `sameas`
- `Engine#render(name)` for loader-based rendering, engine-level
  `autoescape`, and filter/test registration by mutating
  `BUILTIN_FILTERS` / `BUILTIN_TESTS`

Not yet implemented: `{% trans %}` / i18n (out of scope), `spaceless`,
`debug` tag, custom filter/test classes beyond hash registration,
`StrictUndefined` semantics (undefined is nil-based), `truncate`
`nowrap`, `groupby` secondary sort guarantees, `wordwrap`
`break_long_words` tuning, and complex results from negative fractional
powers such as `-5 ** 2.5`. Integers beyond `Int64` use a dedicated runtime
value type, so digit-shaped strings remain ordinary strings.

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
python3 + jinja2) and this engine, then diffs the outputs byte for byte:

```bash
./compare/run.sh
# total: 1972  identical: 1736  both-error: 236  divergent: 0
```

- `compare/gen_cases.py` generates `cases.json` (1972 cases: literals,
  arithmetic, filters, tests, statements, whitespace control, raw,
  inheritance/includes/imports, autoescape, recursive loops)
- `compare/render.py` renders with real Jinja2 (same environment defaults:
  `trim_blocks=false`, `keep_trailing_newline=false`, default `Undefined`)
- `compare/render.cr` renders with krikri-jinja
- `compare/compare.py` diffs; both-error counts as compatible (the two
  engines use different exception vocabularies), one-ok-one-error or any
  output difference is a divergence

This harness found and fixed: undefined rendering as "" (not "None"),
filters binding tighter than unary minus, `map('filtername')` dispatch,
`min`/`max(attribute=)` returning the item, Python `round` semantics via
`sprintf`, string methods (`replace`, `split`, ...), tuple repr for
`dictsort`/`items`, Python-style `urlencode`, `slice` padding to the
longest column, `sum(start=)`, `indent(2, true)`, scientific-notation
literals, `{% raw %}` scanning past embedded `{%`, CPython string-repr
escaping, CPython `%`-format argument rules, lazy `slice` iteration,
and the constant-folding precedence trap for negative-literal-base `**`
expressions.

## Development

```bash
crystal spec        # run the unit/integration suite (184 specs)
./compare/run.sh    # differential test against real Jinja2 (1972 cases)
```
