require "../spec_helper"
require "../../src/krikri_jinja"

describe KrikriJinja do
  describe "raw blocks" do
    it "emits raw content literally" do
      assert_equal("{{ not_rendered }}{% if x %}", KrikriJinja.render("{% raw %}{{ not_rendered }}{% if x %}{% endraw %}"))
    end

    it "handles whitespace markers on raw" do
      assert_equal("aXb", KrikriJinja.render("a\n{%- raw -%}  X  {%- endraw -%}\nb"))
    end
  end

  describe "whitespace control" do
    it "strips with - markers" do
      assert_equal("aXb", KrikriJinja.render("a  {{- 'X' -}}  b"))
      assert_equal("aYb", KrikriJinja.render("a\n  {%- if true %}Y{% endif -%}\n  b"))
    end

    it "supports trim_blocks and lstrip_blocks" do
      opts = KrikriJinja::LexerOptions.new(trim_blocks: true, lstrip_blocks: true)
      engine = KrikriJinja::Engine.new(nil, options: opts)
      assert_equal("a\nb\nc", engine.render_string("a\n{% if true %}\nb\n{% endif %}\nc"))
      assert_equal("X", engine.render_string("  {% if true %}X{% endif %}\n"))
    end

    it "strips the final newline by default" do
      assert_equal("x", KrikriJinja.render("x\n"))
      engine = KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new(keep_trailing_newline: true))
      assert_equal("x\n", engine.render_string("x\n"))
    end

    it "supports custom delimiters" do
      opts = KrikriJinja::LexerOptions.new(var_start: "((", var_end: "))", block_start: "(%", block_end: "%)")
      assert_equal("2", KrikriJinja::Engine.new(nil, options: opts).render_string("(% if true %)(( 1 + 1 ))(% endif %)"))
    end

    it "supports custom comment delimiters" do
      opts = KrikriJinja::LexerOptions.new(comment_start: "<!--", comment_end: "-->")
      assert_equal("ab", KrikriJinja::Engine.new(nil, options: opts).render_string("a<!-- hidden -->b"))
    end
  end

  describe "whitespace control across block boundaries" do
    let(for_vars) { KrikriJinja.context({"plugins" => ["cpu", "interface", "load"]}) }
    let(if_for_vars) { KrikriJinja.context({"autoload" => true, "plugins" => ["cpu", "interface", "load"]}) }

    it "keeps the for body's newline when {%- endif follows a trim_blocks-eaten newline" do
      # Ansible's template module defaults to trim_blocks: true, and roles
      # in the wild (robertdebock.collectd's collectd.conf.j2) pair a
      # `{% for ... -%}` with a `{%- endif %}` whose preceding newline
      # trim_blocks already ate. The `{%-` must not reach past that eaten
      # newline into the loop body's own trailing newline - doing so joined
      # every iteration onto one line (`LoadPlugin cpuLoadPlugin ...`),
      # which collectd rejects as a config syntax error.
      engine = KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new(trim_blocks: true))
      assert_equal("LoadPlugin cpu\nLoadPlugin interface\nLoadPlugin load\n", engine.render_string(
        "{% if autoload -%}\n{% for plugin in plugins -%}\nLoadPlugin {{ plugin }}\n{% endfor %}\n{%- endif %}",
        if_for_vars
      ))
    end

    it "keeps the for body's newline with text between {%- if and {% for" do
      engine = KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new(trim_blocks: true))
      assert_equal("# LoadPlugin section\nLoadPlugin cpu\nLoadPlugin interface\nLoadPlugin load\n", engine.render_string(
        "{% if autoload -%}\n# LoadPlugin section\n{% for plugin in plugins -%}\nLoadPlugin {{ plugin }}\n{% endfor %}\n{%- endif %}",
        if_for_vars
      ))
    end

    it "keeps the same shape correct without trim_blocks" do
      engine = KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new)
      assert_equal("LoadPlugin cpu\nLoadPlugin interface\nLoadPlugin load\n", engine.render_string(
        "{% if autoload -%}\n{% for plugin in plugins -%}\nLoadPlugin {{ plugin }}\n{% endfor %}\n{%- endif %}",
        if_for_vars
      ))
    end

    it "keeps the standalone for-loop's inter-iteration newline" do
      tpl = "{% for plugin in plugins -%}\nLoadPlugin {{ plugin }}\n{% endfor %}"
      assert_equal("LoadPlugin cpu\nLoadPlugin interface\nLoadPlugin load\n", KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new(trim_blocks: true))
        .render_string(tpl, for_vars))
      assert_equal("LoadPlugin cpu\nLoadPlugin interface\nLoadPlugin load\n", KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new)
        .render_string(tpl, for_vars))
    end

    it "does not let {%- reach past whitespace another tag already consumed" do
      engine = KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new(trim_blocks: true))
      # trim_blocks eats the newline after {% if %}; the following {%- has
      # nothing left to strip and must not reach back further.
      assert_equal("Z", engine.render_string("{% if true %}\n{%- endif %}Z"))
      # right-strip consumed the newline; the following {%- must not touch
      # content before it.
      assert_equal("a", engine.render_string("{% if true -%}a\n  {%- endif %}"))
    end
  end

  describe "loop extras" do
    it "supports cycle and changed" do
      assert_equal("aba", KrikriJinja.render("{% for i in [1,2,3] %}{{ loop.cycle('a','b') }}{% endfor %}"))
      assert_equal("TrueFalseTrue", KrikriJinja.render("{% for i in [1,1,2] %}{{ loop.changed(i) }}{% endfor %}"))
    end

    it "supports recursive loops" do
      ctx = KrikriJinja.context({"root" => {"v" => 1, "kids" => [{"v" => 2, "kids" => [] of KrikriJinja::AnyV}, {"v" => 3, "kids" => [] of KrikriJinja::AnyV}]}})
      t = "{% for n in [root] recursive %}{{ n.v }}{{ loop(n.kids) }}{% endfor %}"
      assert_equal("123", KrikriJinja.render(t, ctx))
    end

    it "tracks depth in recursive loops" do
      ctx = KrikriJinja.context({"root" => {"v" => 1, "kids" => [{"v" => 2, "kids" => [] of KrikriJinja::AnyV}]}})
      t = "{% for n in [root] recursive %}({{ n.v }}:{{ loop.depth }}{{ loop(n.kids) }}){% endfor %}"
      assert_equal("(1:1(2:2))", KrikriJinja.render(t, ctx))
    end
  end

  describe "macro extras" do
    it "exposes varargs and kwargs" do
      t = "{% macro m(a, b=0) %}{{ a }}|{{ b }}|{{ varargs | join(',') }}|{{ kwargs['extra'] }}{% endmacro %}"
      assert_equal("1|2|3,4|x", KrikriJinja.render("#{t}{{ m(1, 2, 3, 4, extra='x') }}"))
    end

    it "leaves name undefined inside macro body (jinja parity)" do
      t = "{% macro m() %}[{{ name }}]{% endmacro %}{{ m() }}"
      assert_equal("[]", KrikriJinja.render(t))
    end

    it "expands keyword dictionaries into macro calls" do
      t = "{% macro m(a, b=0) %}{{ a }}|{{ b }}|{{ kwargs['x'] }}{% endmacro %}{{ m(**d) }}"
      assert_equal("1|2|3", KrikriJinja.render(t, {"d" => {"a" => 1, "b" => 2, "x" => 3}}))
    end

    it "passes call-tag parameters to the caller body" do
      t = "{% macro row() %}[{{ caller('x') }}]{% endmacro %}{% call(v) row() %}<{{ v }}>{% endcall %}"
      assert_equal("[<x>]", KrikriJinja.render(t))
    end
  end

  describe "set block form" do
    it "captures rendered body into a variable" do
      assert_equal("AB", KrikriJinja.render("{% set x %}ab{% endset %}{{ x | upper }}"))
    end
  end

  describe "include with fallbacks" do
    let(loader) { KrikriJinja::DictLoader.new({"a.html" => "A", "b.html" => "B"} of String => String) }
    let(engine) { KrikriJinja::Engine.new(loader) }

    it "tries templates in order" do
      assert_equal("A", engine.render_string("{% include ['a.html', 'b.html'] %}"))
      assert_equal("B", engine.render_string("{% include ['missing.html', 'b.html'] %}"))
    end
  end

  describe "more filters" do
    it "dictsort" do
      ctx = KrikriJinja.context({"d" => {"b" => 2, "a" => 1}})
      assert_equal("ab", KrikriJinja.render("{% for k, v in d | dictsort %}{{ k }}{% endfor %}", ctx))
    end

    it "filesizeformat" do
      assert_equal("1.0 kB 1000 Bytes 1 Byte", KrikriJinja.render("{{ 1000 | filesizeformat }} {{ 1000 | filesizeformat(true) }} {{ 1 | filesizeformat }}"))
      assert_equal("9.2 EB", KrikriJinja.render("{{ 9223372036854775808 | filesizeformat }}"))
    end

    it "format with conversions" do
      assert_equal("a 255 ff 00042 's'", KrikriJinja.render("{{ '%s %d %x %05d %r' | format('a', 255, 255, 42, 's') }}"))
    end

    it "center and int base" do
      assert_equal("  ab  |", KrikriJinja.render("{{ 'ab' | center(6) }}|"))
      assert_equal("0 31", KrikriJinja.render("{{ '0x1f' | int }} {{ '0x1f' | int(0, base=16) }}"))
    end

    # ansible-core 2.19 materializes filter outputs at the call boundary
    # (live-verified: `{{ items | unique(attribute='k') | length }}` renders
    # 2 in real), so unique results no longer behave as bare generators here.
    it "unique with attribute" do
      ctx = KrikriJinja.context({"items" => [{"k" => 1}, {"k" => 1}, {"k" => 2}]})
      assert_equal("2", KrikriJinja.render("{{ items | unique(attribute='k') | length }}", ctx))
      assert_equal("2", KrikriJinja.render("{{ items | unique(attribute='k') | list | length }}", ctx))
    end

    it "select by test" do
      ctx = KrikriJinja.context({"items" => [1, "a", 2, "b"]})
      assert_equal("a,b", KrikriJinja.render("{{ items | select('string') | join(',') }}", ctx))
    end

    it "matches keyword filter and test behavior" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ [1,2,3] | map(filter='string') | join(',') }}")
      end
      assert_equal("1,2,3,4", KrikriJinja.render("{{ [1,2,3,4] | select(test='odd') | join(',') }}"))
    end

    it "returns deterministic values for singleton random inputs" do
      assert_equal("1 a 7", KrikriJinja.render("{{ [1] | random }} {{ 'a' | random }} {{ [7] | random }}"))
    end

    it "matches Python seed behavior for integer and string seeds" do
      assert_equal("8805", KrikriJinja.render("{{ random(65534, seed=1) }}"))
      assert_equal("31863", KrikriJinja.render("{{ random(65534, seed='host1') }}"))
      assert_equal(KrikriJinja.render("{{ random(65534, seed='host1') }}"), KrikriJinja.render("{{ random(65534, seed='host1') }}"))
    end

    it "supports Ansible integer range forms" do
      assert_equal("1 11 10", KrikriJinja.render("{{ random(10, seed=42) }} {{ random(10, 20, seed=42) }} {{ random(10, 20, 2, seed=42) }}"))
      assert_equal("10", KrikriJinja.render("{{ 20 | random(start=10, step=2, seed=42) }}"))
    end

    it "makes seeded random selection repeatable and seed-sensitive" do
      assert_equal("137", KrikriJinja.render("{{ random(1000, seed=1) }}"))
      assert_equal("137", KrikriJinja.render("{{ random(1000, seed=1) }}"))
      assert_equal("978", KrikriJinja.render("{{ random(1000, seed=2) }}"))
      assert_equal("-4", KrikriJinja.render("{{ [-5, -4, -3, -4, -5] | random(seed=1) }}"))
    end

    it "handles empty sequences, negative values, and steps" do
      assert_equal("||", KrikriJinja.render("{{ [] | random }}|{{ random([]) }}|"))
      assert_equal("-5 20", KrikriJinja.render("{{ random(-5, 0, seed=42) }} {{ random(20, 10, -2, seed=42) }}"))
      assert_equal("11", KrikriJinja.render("{{ random(10, 20, 0, seed=42) }}"))
    end

    it "rejects invalid random ranges and arguments" do
      [
        "{{ random(0) }}",
        "{{ random(1, 2, 3, 4) }}",
        "{{ random(1.5) }}",
        "{{ random(1, 2, bad=3) }}",
        "{{ [1, 2] | random(3) }}",
      ].each do |template|
        assert_raises(KrikriJinja::TemplateError) { KrikriJinja.render(template) }
      end
    end

    it "safe/escape survive autoescape" do
      engine = KrikriJinja::Engine.new(nil, autoescape: true)
      assert_equal("&lt;b&gt;|<b>|&lt;b&gt;", engine.render_string("{{ v }}|{{ v | safe }}|{{ v | escape }}", {"v" => "<b>"} of String => KrikriJinja::AnyV))
      assert_equal("True", KrikriJinja.render("{{ v is escaped }}", {"v" => KrikriJinja::AnyValue.new(KrikriJinja::Markup.new("<i>"))}))
    end
  end

  describe "expression extras" do
    it "parses hex/octal/binary literals" do
      assert_equal("31 15 5", KrikriJinja.render("{{ 0x1f }} {{ 0o17 }} {{ 0b101 }}"))
    end

    it "binds not looser than comparisons" do
      assert_equal("False True", KrikriJinja.render("{{ not 1 in [1] }} {{ not 'x' in 'abc' }}"))
    end

    it "supports sameas" do
      assert_equal("False True False", KrikriJinja.render("{{ x is sameas none }} {{ 1 is sameas 1 }} {{ 'a' is sameas 'b' }}"))
    end

    it "supports true and false tests" do
      assert_equal("True False False", KrikriJinja.render("{{ true is true }} {{ false is true }} {{ none is true }}"))
      assert_equal("True False True", KrikriJinja.render("{{ false is false }} {{ true is false }} {{ true is not false }}"))
    end

    it "supports the default filter alias" do
      assert_equal("fallback ", KrikriJinja.render("{{ missing | d('fallback') }} {{ missing | d }}"))
    end

    it "rejects required blocks with a body (jinja raises)" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% block a scoped required %}x{% endblock %}")
      end
    end
  end

  describe "engine api" do
    it "renders named templates" do
      engine = KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"t.html" => "hi {{ n }}"} of String => String))
      assert_equal("hi you", engine.render("t.html", {"n" => "you"} of String => KrikriJinja::AnyV))
    end

    it "provides user-defined globals" do
      engine = KrikriJinja::Engine.new(nil, {"site" => "example"} of String => KrikriJinja::AnyV)
      assert_equal("example", engine.render_string("{{ site }}"))
    end

    it "evaluates structured expressions as JSON values" do
      variables = {"items" => JSON.parse(%([{"name":"a"},{"name":"b"}]))}
      assert_equal(%(["a","b"]), KrikriJinja.evaluate_expression("items | map(attribute='name')", variables).to_json)
      assert_nil(KrikriJinja.evaluate_expression("none", variables).not_nil!.raw)
      assert(KrikriJinja.parse_expression("1 + 2").is_a?(KrikriJinja::Nodes::BinOpNode))
    end
    it "keeps FileSystemLoader reads inside its root" do
      root = File.tempname
      sibling = "#{root}_sibling"
      Dir.mkdir(root)
      Dir.mkdir(sibling)
      secret = File.join(sibling, "secret.txt")
      File.write(secret, "secret")
      loader = KrikriJinja::FileSystemLoader.new(root)
      assert_nil(loader.get_source("../#{File.basename(sibling)}/secret.txt"))
    ensure
      File.delete(secret) if secret && File.exists?(secret)
      Dir.delete(sibling) if sibling && Dir.exists?(sibling)
      Dir.delete(root) if root && Dir.exists?(root)
    end

    it "allows registering engine-local filters, tests, globals, and functions" do
      engine = KrikriJinja::Engine.new
      engine.register_filter("shout") do |v, _args, _kwargs, _ctx|
        KrikriJinja::AnyValue.new(KrikriJinja.stringify(v).upcase + "!")
      end
      engine.register_test("loud") do |v, _args, _kwargs, _ctx|
        KrikriJinja.stringify(v).upcase == KrikriJinja.stringify(v)
      end
      engine.register_global("site", "example")
      engine.register_function("answer") do |_args, _kwargs, _ctx|
        KrikriJinja::AnyValue.new(42i64)
      end
      assert_equal("HEY! True example 42", engine.render_string("{{ 'hey' | shout }} {{ 'HEY' is loud }} {{ site }} {{ answer() }}"))
      assert_raises(KrikriJinja::TemplateError) { KrikriJinja.render("{{ 'hey' | shout }}") }
    end

    it "registers JSON-compatible extension callbacks" do
      engine = KrikriJinja::Engine.new
      engine.register_json_filter("json_exclaim") do |target, _args, _kwargs|
        JSON::Any.new(target.as_s + "!")
      end
      engine.register_json_test("json_text") do |target, _args, _kwargs|
        target.raw.is_a?(String)
      end
      engine.register_json_function("json_identity") do |args, _kwargs|
        args[0]
      end
      assert_equal("x! True [1, True]", engine.render_string("{{ 'x' | json_exclaim }} {{ 'x' is json_text }} {{ json_identity([1, true]) }}"))
    end

    it "keeps structured errors inspectable" do
      begin
        KrikriJinja.evaluate_expression("missing + 1", {} of String => JSON::Any, strict: true)
        raise "expected expression failure"
      rescue error : KrikriJinja::TemplateError
        assert_equal(KrikriJinja::ErrorKind::Runtime, error.kind)
        assert_equal(true, error.to_json.includes?("\"kind\":\"runtime\""))
      end
    end

    it "registers loader-backed functions" do
      engine = KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"partial.html" => "partial"}))
      engine.register_loader_function("partial", "partial.html")
      assert_equal("partial", engine.render_string("{{ partial() }}"))
    end
  end
end
