require "../spec_helper"
require "../../src/krikri_jinja"

describe KrikriJinja do
  describe "raw blocks" do
    it "emits raw content literally" do
      KrikriJinja.render("{% raw %}{{ not_rendered }}{% if x %}{% endraw %}")
        .should eq("{{ not_rendered }}{% if x %}")
    end

    it "handles whitespace markers on raw" do
      KrikriJinja.render("a\n{%- raw -%}  X  {%- endraw -%}\nb")
        .should eq("aXb")
    end
  end

  describe "whitespace control" do
    it "strips with - markers" do
      KrikriJinja.render("a  {{- 'X' -}}  b").should eq("aXb")
      KrikriJinja.render("a\n  {%- if true %}Y{% endif -%}\n  b").should eq("aYb")
    end

    it "supports trim_blocks and lstrip_blocks" do
      opts = KrikriJinja::LexerOptions.new(trim_blocks: true, lstrip_blocks: true)
      engine = KrikriJinja::Engine.new(nil, options: opts)
      engine.render_string("a\n{% if true %}\nb\n{% endif %}\nc").should eq("a\nb\nc")
      engine.render_string("  {% if true %}X{% endif %}\n").should eq("X")
    end

    it "strips the final newline by default" do
      KrikriJinja.render("x\n").should eq("x")
      engine = KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new(keep_trailing_newline: true))
      engine.render_string("x\n").should eq("x\n")
    end

    it "supports custom delimiters" do
      opts = KrikriJinja::LexerOptions.new(var_start: "((", var_end: "))", block_start: "(%", block_end: "%)")
      KrikriJinja::Engine.new(nil, options: opts).render_string("(% if true %)(( 1 + 1 ))(% endif %)").should eq("2")
    end

    it "supports custom comment delimiters" do
      opts = KrikriJinja::LexerOptions.new(comment_start: "<!--", comment_end: "-->")
      KrikriJinja::Engine.new(nil, options: opts).render_string("a<!-- hidden -->b").should eq("ab")
    end
  end

  describe "whitespace control across block boundaries" do
    for_vars = KrikriJinja.context({"plugins" => ["cpu", "interface", "load"]})
    if_for_vars = KrikriJinja.context({"autoload" => true, "plugins" => ["cpu", "interface", "load"]})

    it "keeps the for body's newline when {%- endif follows a trim_blocks-eaten newline" do
      # Ansible's template module defaults to trim_blocks: true, and roles
      # in the wild (robertdebock.collectd's collectd.conf.j2) pair a
      # `{% for ... -%}` with a `{%- endif %}` whose preceding newline
      # trim_blocks already ate. The `{%-` must not reach past that eaten
      # newline into the loop body's own trailing newline - doing so joined
      # every iteration onto one line (`LoadPlugin cpuLoadPlugin ...`),
      # which collectd rejects as a config syntax error.
      engine = KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new(trim_blocks: true))
      engine.render_string(
        "{% if autoload -%}\n{% for plugin in plugins -%}\nLoadPlugin {{ plugin }}\n{% endfor %}\n{%- endif %}",
        if_for_vars
      ).should eq("LoadPlugin cpu\nLoadPlugin interface\nLoadPlugin load\n")
    end

    it "keeps the for body's newline with text between {%- if and {% for" do
      engine = KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new(trim_blocks: true))
      engine.render_string(
        "{% if autoload -%}\n# LoadPlugin section\n{% for plugin in plugins -%}\nLoadPlugin {{ plugin }}\n{% endfor %}\n{%- endif %}",
        if_for_vars
      ).should eq("# LoadPlugin section\nLoadPlugin cpu\nLoadPlugin interface\nLoadPlugin load\n")
    end

    it "keeps the same shape correct without trim_blocks" do
      engine = KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new)
      engine.render_string(
        "{% if autoload -%}\n{% for plugin in plugins -%}\nLoadPlugin {{ plugin }}\n{% endfor %}\n{%- endif %}",
        if_for_vars
      ).should eq("LoadPlugin cpu\nLoadPlugin interface\nLoadPlugin load\n")
    end

    it "keeps the standalone for-loop's inter-iteration newline" do
      tpl = "{% for plugin in plugins -%}\nLoadPlugin {{ plugin }}\n{% endfor %}"
      KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new(trim_blocks: true))
        .render_string(tpl, for_vars)
        .should eq("LoadPlugin cpu\nLoadPlugin interface\nLoadPlugin load\n")
      KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new)
        .render_string(tpl, for_vars)
        .should eq("LoadPlugin cpu\nLoadPlugin interface\nLoadPlugin load\n")
    end

    it "does not let {%- reach past whitespace another tag already consumed" do
      engine = KrikriJinja::Engine.new(nil, options: KrikriJinja::LexerOptions.new(trim_blocks: true))
      # trim_blocks eats the newline after {% if %}; the following {%- has
      # nothing left to strip and must not reach back further.
      engine.render_string("{% if true %}\n{%- endif %}Z").should eq("Z")
      # right-strip consumed the newline; the following {%- must not touch
      # content before it.
      engine.render_string("{% if true -%}a\n  {%- endif %}").should eq("a")
    end
  end

  describe "loop extras" do
    it "supports cycle and changed" do
      KrikriJinja.render("{% for i in [1,2,3] %}{{ loop.cycle('a','b') }}{% endfor %}")
        .should eq("aba")
      KrikriJinja.render("{% for i in [1,1,2] %}{{ loop.changed(i) }}{% endfor %}")
        .should eq("TrueFalseTrue")
    end

    it "supports recursive loops" do
      ctx = KrikriJinja.context({"root" => {"v" => 1, "kids" => [{"v" => 2, "kids" => [] of KrikriJinja::AnyV}, {"v" => 3, "kids" => [] of KrikriJinja::AnyV}]}})
      t = "{% for n in [root] recursive %}{{ n.v }}{{ loop(n.kids) }}{% endfor %}"
      KrikriJinja.render(t, ctx).should eq("123")
    end

    it "tracks depth in recursive loops" do
      ctx = KrikriJinja.context({"root" => {"v" => 1, "kids" => [{"v" => 2, "kids" => [] of KrikriJinja::AnyV}]}})
      t = "{% for n in [root] recursive %}({{ n.v }}:{{ loop.depth }}{{ loop(n.kids) }}){% endfor %}"
      KrikriJinja.render(t, ctx).should eq("(1:1(2:2))")
    end

  end

  describe "macro extras" do
    it "exposes varargs and kwargs" do
      t = "{% macro m(a, b=0) %}{{ a }}|{{ b }}|{{ varargs | join(',') }}|{{ kwargs['extra'] }}{% endmacro %}"
      KrikriJinja.render("#{t}{{ m(1, 2, 3, 4, extra='x') }}").should eq("1|2|3,4|x")
    end

    it "leaves name undefined inside macro body (jinja parity)" do
      t = "{% macro m() %}[{{ name }}]{% endmacro %}{{ m() }}"
      KrikriJinja.render(t).should eq("[]")
    end

    it "expands keyword dictionaries into macro calls" do
      t = "{% macro m(a, b=0) %}{{ a }}|{{ b }}|{{ kwargs['x'] }}{% endmacro %}{{ m(**d) }}"
      KrikriJinja.render(t, {"d" => {"a" => 1, "b" => 2, "x" => 3}}).should eq("1|2|3")
    end

    it "passes call-tag parameters to the caller body" do
      t = "{% macro row() %}[{{ caller('x') }}]{% endmacro %}{% call(v) row() %}<{{ v }}>{% endcall %}"
      KrikriJinja.render(t).should eq("[<x>]")
    end
  end

  describe "set block form" do
    it "captures rendered body into a variable" do
      KrikriJinja.render("{% set x %}ab{% endset %}{{ x | upper }}").should eq("AB")
    end
  end

  describe "include with fallbacks" do
    loader = KrikriJinja::DictLoader.new({
      "a.html" => "A",
      "b.html" => "B",
    } of String => String)
    engine = KrikriJinja::Engine.new(loader)

    it "tries templates in order" do
      engine.render_string("{% include ['a.html', 'b.html'] %}").should eq("A")
      engine.render_string("{% include ['missing.html', 'b.html'] %}").should eq("B")
    end
  end

  describe "more filters" do
    it "dictsort" do
      ctx = KrikriJinja.context({"d" => {"b" => 2, "a" => 1}})
      KrikriJinja.render("{% for k, v in d | dictsort %}{{ k }}{% endfor %}", ctx).should eq("ab")
    end

    it "filesizeformat" do
      KrikriJinja.render("{{ 1000 | filesizeformat }} {{ 1000 | filesizeformat(true) }} {{ 1 | filesizeformat }}")
        .should eq("1.0 kB 1000 Bytes 1 Byte")
      KrikriJinja.render("{{ 9223372036854775808 | filesizeformat }}").should eq("9.2 EB")
    end

    it "format with conversions" do
      KrikriJinja.render("{{ '%s %d %x %05d %r' | format('a', 255, 255, 42, 's') }}")
        .should eq("a 255 ff 00042 's'")
    end

    it "center and int base" do
      KrikriJinja.render("{{ 'ab' | center(6) }}|").should eq("  ab  |")
      KrikriJinja.render("{{ '0x1f' | int }} {{ '0x1f' | int(0, base=16) }}").should eq("0 31")
    end

    it "unique with attribute" do
      ctx = KrikriJinja.context({"items" => [{"k" => 1}, {"k" => 1}, {"k" => 2}]})
      # unique returns a python generator, which has no length
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ items | unique(attribute='k') | length }}", ctx)
      end
      KrikriJinja.render("{{ items | unique(attribute='k') | list | length }}", ctx).should eq("2")
    end

    it "select by test" do
      ctx = KrikriJinja.context({"items" => [1, "a", 2, "b"]})
      KrikriJinja.render("{{ items | select('string') | join(',') }}", ctx).should eq("a,b")
    end

    it "matches keyword filter and test behavior" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ [1,2,3] | map(filter='string') | join(',') }}")
      end
      KrikriJinja.render("{{ [1,2,3,4] | select(test='odd') | join(',') }}").should eq("1,2,3,4")
    end

    it "returns deterministic values for singleton random inputs" do
      KrikriJinja.render("{{ [1] | random }} {{ 'a' | random }} {{ [7] | random }}")
        .should eq("1 a 7")
    end

    it "matches Python seed behavior for integer and string seeds" do
      KrikriJinja.render("{{ random(65534, seed=1) }}").should eq("8805")
      KrikriJinja.render("{{ random(65534, seed='host1') }}").should eq("31863")
      KrikriJinja.render("{{ random(65534, seed='host1') }}")
        .should eq(KrikriJinja.render("{{ random(65534, seed='host1') }}"))
    end

    it "supports Ansible integer range forms" do
      KrikriJinja.render("{{ random(10, seed=42) }} {{ random(10, 20, seed=42) }} {{ random(10, 20, 2, seed=42) }}")
        .should eq("1 11 10")
      KrikriJinja.render("{{ 20 | random(start=10, step=2, seed=42) }}").should eq("10")
    end

    it "makes seeded random selection repeatable and seed-sensitive" do
      KrikriJinja.render("{{ random(1000, seed=1) }}").should eq("137")
      KrikriJinja.render("{{ random(1000, seed=1) }}").should eq("137")
      KrikriJinja.render("{{ random(1000, seed=2) }}").should eq("978")
      KrikriJinja.render("{{ [-5, -4, -3, -4, -5] | random(seed=1) }}").should eq("-4")
    end

    it "handles empty sequences, negative values, and steps" do
      KrikriJinja.render("{{ [] | random }}|{{ random([]) }}|").should eq("||")
      KrikriJinja.render("{{ random(-5, 0, seed=42) }} {{ random(20, 10, -2, seed=42) }}")
        .should eq("-5 20")
      KrikriJinja.render("{{ random(10, 20, 0, seed=42) }}").should eq("11")
    end

    it "rejects invalid random ranges and arguments" do
      [
        "{{ random(0) }}",
        "{{ random(1, 2, 3, 4) }}",
        "{{ random(1.5) }}",
        "{{ random(1, 2, bad=3) }}",
        "{{ [1, 2] | random(3) }}",
      ].each do |template|
        expect_raises(KrikriJinja::TemplateError) { KrikriJinja.render(template) }
      end
    end

    it "safe/escape survive autoescape" do
      engine = KrikriJinja::Engine.new(nil, autoescape: true)
      engine.render_string("{{ v }}|{{ v | safe }}|{{ v | escape }}", {"v" => "<b>"} of String => KrikriJinja::AnyV)
        .should eq("&lt;b&gt;|<b>|&lt;b&gt;")
      KrikriJinja.render("{{ v is escaped }}", {"v" => KrikriJinja::AnyValue.new(KrikriJinja::Markup.new("<i>"))})
        .should eq("True")
    end
  end

  describe "expression extras" do
    it "parses hex/octal/binary literals" do
      KrikriJinja.render("{{ 0x1f }} {{ 0o17 }} {{ 0b101 }}").should eq("31 15 5")
    end

    it "binds not looser than comparisons" do
      KrikriJinja.render("{{ not 1 in [1] }} {{ not 'x' in 'abc' }}").should eq("False True")
    end

    it "supports sameas" do
      KrikriJinja.render("{{ x is sameas none }} {{ 1 is sameas 1 }} {{ 'a' is sameas 'b' }}")
        .should eq("False True False")
    end

    it "supports true and false tests" do
      KrikriJinja.render("{{ true is true }} {{ false is true }} {{ none is true }}")
        .should eq("True False False")
      KrikriJinja.render("{{ false is false }} {{ true is false }} {{ true is not false }}")
        .should eq("True False True")
    end

    it "supports the default filter alias" do
      KrikriJinja.render("{{ missing | d('fallback') }} {{ missing | d }}")
        .should eq("fallback ")
    end

    it "rejects required blocks with a body (jinja raises)" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% block a scoped required %}x{% endblock %}")
      end
    end
  end

  describe "engine api" do
    it "renders named templates" do
      engine = KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"t.html" => "hi {{ n }}"} of String => String))
      engine.render("t.html", {"n" => "you"} of String => KrikriJinja::AnyV).should eq("hi you")
    end

    it "provides user-defined globals" do
      engine = KrikriJinja::Engine.new(nil, {"site" => "example"} of String => KrikriJinja::AnyV)
      engine.render_string("{{ site }}").should eq("example")
    end

    it "evaluates structured expressions as JSON values" do
      variables = {"items" => JSON.parse(%([{"name":"a"},{"name":"b"}]))}
      KrikriJinja.evaluate_expression("items | map(attribute='name')", variables).to_json.should eq(%(["a","b"]))
      KrikriJinja.evaluate_expression("none", variables).not_nil!.raw.should be_nil
      KrikriJinja.parse_expression("1 + 2").should be_a(KrikriJinja::Nodes::BinOpNode)
    end
    it "keeps FileSystemLoader reads inside its root" do
      root = File.tempname
      sibling = "#{root}_sibling"
      Dir.mkdir(root)
      Dir.mkdir(sibling)
      secret = File.join(sibling, "secret.txt")
      File.write(secret, "secret")
      loader = KrikriJinja::FileSystemLoader.new(root)
      loader.get_source("../#{File.basename(sibling)}/secret.txt").should be_nil
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
      engine.render_string("{{ 'hey' | shout }} {{ 'HEY' is loud }} {{ site }} {{ answer() }}").should eq("HEY! True example 42")
      expect_raises(KrikriJinja::TemplateError) { KrikriJinja.render("{{ 'hey' | shout }}") }
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
      engine.render_string("{{ 'x' | json_exclaim }} {{ 'x' is json_text }} {{ json_identity([1, true]) }}").should eq("x! True [1, True]")
    end

    it "keeps structured errors inspectable" do
      begin
        KrikriJinja.evaluate_expression("missing + 1", {} of String => JSON::Any, strict: true)
        raise "expected expression failure"
      rescue error : KrikriJinja::TemplateError
        error.kind.should eq(KrikriJinja::ErrorKind::Runtime)
        error.to_json.includes?("\"kind\":\"runtime\"").should be_true
      end
    end

    it "registers loader-backed functions" do
      engine = KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"partial.html" => "partial"}))
      engine.register_loader_function("partial", "partial.html")
      engine.render_string("{{ partial() }}").should eq("partial")
    end
  end
end
