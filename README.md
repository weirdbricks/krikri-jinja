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

## Status (v0.4.11)

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
- Globals: `range`, `dict`, `namespace`, `cycler`, `joiner`, `lipsum`,
  `random`
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
- Filters: `dictsort`, `filesizeformat`, `forceescape`, `center`, `random`
  (sequence choice plus Ansible-compatible `random(n)`, `random(start, stop)`,
  `random(start, stop, step)` ranges and deterministic `seed=`), `pprint`,
  `urlize`, `int(base=)`, `unique(attribute=)`, `format` with full
  %-conversion support, `Markup`-aware `safe`/`escape` under autoescape
- Tests: `escaped`, `filter`, `test`, `sameas`
- `Engine#render(name)` for loader-based rendering, engine-level
  `autoescape`, `StrictUndefined`, structured expression evaluation, and
  engine-local filter/test/global/function registration

Known gaps: `{% trans %}` / i18n (out of scope), `spaceless`,
`debug` tag, `truncate` `nowrap`, `groupby` secondary sort guarantees,
`wordwrap` `break_long_words` tuning, and complex results from negative
fractional powers such as `-5 ** 2.5`. Lazy filter generators are iterated by
templates but do not reproduce Python's process-specific `<generator ... at
0x...>` repr. Integers beyond `Int64` use a dedicated runtime value type, so
digit-shaped strings remain ordinary strings.

## Usage

```crystal
require "krikri-jinja"

KrikriJinja.render("Hello {{ name | upper }}!", {"name" => "world"})
# => "Hello WORLD!"

engine = KrikriJinja::Engine.new(KrikriJinja::FileSystemLoader.new("templates"))
engine.render_string("{% extends 'base.html' %}")
```

## Structured expressions and extensions

Expression evaluation returns a typed `JSON::Any` value instead of rendered
text. JSON `null` remains distinct from an undefined expression result:
lenient undefined is returned as `nil`, while strict undefined raises a
`TemplateError`.

```crystal
vars = {"items" => JSON.parse(%([{"name": "a"}, {"name": "b"}]))}
result = KrikriJinja.evaluate_expression("items | map(attribute='name')", vars)
result.to_json
# => ["a","b"]
```

Use an engine to configure strict undefined and register extensions locally.
The `register_json_*` APIs accept only JSON-compatible values, so callers do
not need to construct internal `AnyValue` instances.

```crystal
engine = KrikriJinja::Engine.new(
  KrikriJinja::DictLoader.new({"partial.html" => "hello"}),
  undefined: KrikriJinja::StrictUndefined.new
)
engine.register_json_filter("exclaim") do |value, _args, _kwargs|
  JSON::Any.new("#{value.as_s}!")
end
engine.register_json_test("text") do |value, _args, _kwargs|
  value.raw.is_a?(String)
end
engine.register_json_function("identity") do |args, _kwargs|
  args[0]
end
engine.register_global("answer", JSON::Any.new(42))
engine.register_loader_function("partial", "partial.html")
engine.render_string("{{ 'hello' | exclaim }} {{ 'hello' is text }} {{ identity([1, true]) | tojson }} {{ partial() }}")
# => "hello! True [1,true] hello"
```

`register_filter`, `register_test`, and `register_function` expose the native
value API for extensions that need `AnyValue`; `register_global` accepts plain
values and deep-converts nested arrays and hashes. `known_filter?` and
`known_test?` support compile-time feature checks. `TemplateError#to_json`
returns a structured error object containing its kind, message, line, and
optional operation or template metadata.

### Shared default engine

Callers that do not want to build and pass an engine at every call site can
register extensions once on the engine shared by the module-level `render`,
`evaluate_expression`, and `evaluate_expression_result` helpers:

```crystal
KrikriJinja.register_default_json_filter("exclaim") do |value, _args, _kwargs|
  JSON::Any.new("#{value.as_s}!")
end
KrikriJinja.render("{{ 'hello' | exclaim }}") # => "hello!"
```

`register_default_test`, `register_default_filter`, `register_default_json_test`,
`register_default_json_function`, `register_default_function`, `register_default_global`,
and `register_default_loader_function` mirror their `Engine` counterparts;
`default_known_filter?` / `default_known_test?` and `reset_default_engine` round
out the surface. Each call to `evaluate_expression` still gets its own engine,
derived from the default one, so per-call `strict:` and `loader:` arguments keep
working and cannot leak state into the shared engine.

### Host context

Hosts that need controller-side state inside a registration (variable scope,
role paths, plugin runners) subclass `KrikriJinja::HostContext` and hand an
instance to the call:

```crystal
class AnsibleContext < KrikriJinja::HostContext
  getter vars : Hash(String, JSON::Any)
  def initialize(@vars)
  end
end

KrikriJinja.register_default_function("lookup") do |args, kwargs, ctx|
  host = ctx.host_context.as(AnsibleContext)
  # ... call out to the controller's lookup plugin with host.vars ...
end

KrikriJinja.render(template, vars, host_context: AnsibleContext.new(vars))
```

`render`, `evaluate_expression`, `evaluate_expression_result`, and
`evaluate_expression_value` all accept `host_context:`; the engine passes it to
every registered filter, test, and function it invokes, including inside
includes, imports, and macros.

### Undefined versus null

Explicit `{%+ ... +%}` KEEP markers are supported: a tag closed with `+%}`
does not eat the newline that follows it, even with `trim_blocks` enabled.

`x in list` never raises for an undefined left operand; it reports False,
matching Python and real Ansible.

`KrikriJinja.ansible_strict_undefined` is Ansible's own strict undefined:
it raises when an undefined value is used, and chains through attribute and
subscript access on the way there, so `x | default(other.thing.y)` stays lazy
when `x` is defined. Plain `StrictUndefined` keeps Jinja2's non-chaining
behavior.

Strict-undefined failures now name the variable that was missing
("'missing_thing' is undefined"), matching real Ansible's own message.

`evaluate_expression` returns `nil` both for a JSON `null` result and for an
undefined expression under lenient undefined. Callers that must tell those
apart (for strict-conditional semantics) use `evaluate_expression_result`:

```crystal
KrikriJinja.evaluate_expression_result("missing").undefined? # => true
KrikriJinja.evaluate_expression_result("none").undefined?    # => false
KrikriJinja.evaluate_expression_result("none").value.to_json # => "null"
```

## Differential testing against real Jinja2

`compare/` renders a shared case corpus with **both** real Jinja2 (via
`python3` with the `jinja2` package installed) and this engine, then diffs
the outputs byte for byte:

```bash
./compare/run.sh
# total: 2,000  identical: 1,756  both-error: 244  divergent: 0
```

- `compare/gen_cases.py` generates `cases.json` (2,000 cases: literals,
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
crystal spec        # run the unit/integration suite (199 specs)
./compare/run.sh    # differential test against real Jinja2 (2,000 cases)
./compare/fuzz_run.sh 8 3000 1000  # 8 fuzz rounds, starting at seed 1001
```
