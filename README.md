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

## Status (v0.1.0)

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

Not yet implemented: custom delimiters per-render, `trim_blocks` /
`lstrip_blocks` / `keep_trailing_newline` controls, `{% raw %}` blocks,
`{% trans %}`, i18n, `cycle`/`spaceless` tags, custom filter/test
registration API (filters/tests are plain hashes today), macro `varargs`/
`kwargs` introspection, `dictsort`, `filesizeformat`, `wordwrap` edge cases,
autoescape `Markup` round-tripping through filters, and `{% for %}`
`recursive` body rendering.

## Usage

```crystal
require "krikri-jinja"

KrikriJinja.render("Hello {{ name | upper }}!", {"name" => "world"})
# => "Hello WORLD!"

engine = KrikriJinja::Engine.new(KrikriJinja::FileSystemLoader.new("templates"))
engine.render_string("{% extends 'base.html' %}")
```

## Development

```bash
crystal spec   # run the suite
```
