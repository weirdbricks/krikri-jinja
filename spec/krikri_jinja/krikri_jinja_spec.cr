require "../spec_helper"
require "../../src/krikri_jinja"

describe KrikriJinja do
  describe "variables and literals" do
    it "renders plain text" do
      assert_equal("hello", KrikriJinja.render("hello"))
    end

    it "substitutes variables" do
      assert_equal("Hello world!", KrikriJinja.render("Hello {{ name }}!", {"name" => "world"}))
    end

    it "renders numbers and booleans Python-style" do
      assert_equal("1 2.5 True False None", KrikriJinja.render("{{ 1 }} {{ 2.5 }} {{ true }} {{ false }} {{ none }}"))
    end

    it "stringifies lists and dicts repr-style" do
      assert_equal("[1, 'a']", KrikriJinja.render("{{ [1, 'a'] }}"))
      assert_equal("{'a': 1}", KrikriJinja.render("{{ {'a': 1} }}"))
    end

    it "supports attribute and item access" do
      ctx = KrikriJinja.context({"user" => {"name" => "bob"}, "items" => [10, 20, 30]})
      assert_equal("bob bob 20 30", KrikriJinja.render("{{ user.name }} {{ user['name'] }} {{ items[1] }} {{ items[-1] }}", ctx))
    end

    it "supports slicing" do
      assert_equal("bcfedcba[1, 3]", KrikriJinja.render("{{ 'abcdef'[1:3] }}{{ 'abcdef'[::-1] }}{{ [1,2,3,4][::2] }}"))
    end
  end

  describe "expressions" do
    it "does arithmetic" do
      assert_equal("14 2.5 3 1 1024 -3", KrikriJinja.render("{{ 2 + 3 * 4 }} {{ 10 / 4 }} {{ 7 // 2 }} {{ 7 % 3 }} {{ 2 ** 10 }} {{ -5 + 2 }}"))
    end

    it "concatenates with ~" do
      assert_equal("a1True", KrikriJinja.render("{{ 'a' ~ 1 ~ true }}"))
    end

    it "compares" do
      assert_equal("True True True True 1", KrikriJinja.render("{{ 1 < 2 }} {{ 'a' == 'a' }} {{ 1 != 2 }} {{ 3 >= 3 }} {{ 1 if true else 2 }}"))
    end

    it "supports in/not in" do
      assert_equal("True True True", KrikriJinja.render("{{ 1 in [1,2] }} {{ 'x' not in 'abc' }} {{ 'k' in {'k': 1} }}"))
    end

    it "supports and/or/not with short circuit" do
      assert_equal("5 x True", KrikriJinja.render("{{ true and 5 }} {{ false or 'x' }} {{ not false }}"))
    end

    it "supports conditional expressions" do
      assert_equal("yes", KrikriJinja.render("{{ 'yes' if 1 > 0 else 'no' }}"))
    end

    it "supports list/dict literals and tuple expressions" do
      assert_equal("2v", KrikriJinja.render("{{ [1, 2][1] }}{{ {'k': 'v'}['k'] }}"))
    end

    it "treats undefined as falsy nil" do
      assert_equal("fallback", KrikriJinja.render("{{ missing | default('fallback') }}"))
      assert_equal("y", KrikriJinja.render("{{ 'x' if missing else 'y' }}"))
    end
  end

  describe "statements" do
    it "runs if/elif/else" do
      t = "{% if x == 1 %}one{% elif x == 2 %}two{% else %}many{% endif %}"
      assert_equal("one", KrikriJinja.render(t, {"x" => 1}))
      assert_equal("two", KrikriJinja.render(t, {"x" => 2}))
      assert_equal("many", KrikriJinja.render(t, {"x" => 5}))
    end

    it "runs for loops with loop variables" do
      assert_equal("1:1 2:2 3:3 ", KrikriJinja.render("{% for i in [1,2,3] %}{{ loop.index }}:{{ i }} {% endfor %}"))
      assert_equal("FalseFalseTrue", KrikriJinja.render("{% for i in [1,2,3] %}{{ loop.last }}{% endfor %}"))
    end

    it "supports for-else" do
      assert_equal("empty", KrikriJinja.render("{% for i in [] %}{{ i }}{% else %}empty{% endfor %}"))
    end

    it "accepts a trailing colon before compound statement bodies (jinja2 parity)" do
      # Real Jinja2's parse_statements skips an optional colon for
      # Python-syntax compatibility; ajsalminen.hosts' hosts.j2 relies on it.
      assert_equal("12", KrikriJinja.render("{% for i in [1,2]: %}{{ i }}{% endfor %}"))
      assert_equal("y", KrikriJinja.render("{% if true: %}y{% endif %}"))
      assert_equal("n", KrikriJinja.render("{% if false %}y{% elif true: %}n{% endif %}"))
      assert_equal("n", KrikriJinja.render("{% if false %}y{% else: %}n{% endif %}"))
      assert_equal("empty", KrikriJinja.render("{% for i in []: %}{{ i }}{% else: %}empty{% endfor %}"))
      assert_equal("2", KrikriJinja.render("{% for i in [1,2] if i > 1: %}{{ i }}{% endfor %}"))
      assert_equal("A", KrikriJinja.render("{% filter upper: %}a{% endfilter %}"))
      assert_equal("1", KrikriJinja.render("{% macro m(x): %}{{ x }}{% endmacro %}{{ m(1) }}"))
      assert_equal("<b>", KrikriJinja.render("{% macro wrap() %}<{{ caller() }}>{% endmacro %}{% call wrap(): %}b{% endcall %}"))
      assert_equal("x", KrikriJinja.render("{% autoescape false: %}x{% endautoescape %}"))
    end

    it "still rejects the colon where real Jinja2 rejects it" do
      assert_raises(KrikriJinja::TemplateError) { KrikriJinja.render("{% with a = 3: %}{{ a }}{% endwith %}") }
      assert_raises(KrikriJinja::TemplateError) { KrikriJinja.render("{% set x = 1: %}") }
      assert_raises(KrikriJinja::TemplateError) { KrikriJinja.render("{% if true %}y{% endif: %}") }
      assert_raises(KrikriJinja::TemplateError) { KrikriJinja.render("{% for i in [1] %}{{ i }}{% endfor: %}") }
    end

    it "supports unpacking in for loops" do
      assert_equal("1=a;2=b;", KrikriJinja.render("{% for k, v in items %}{{ k }}={{ v }};{% endfor %}",
        KrikriJinja.context({"items" => [[1, "a"], [2, "b"]]})))
    end

    it "filters for-loop items" do
      assert_equal("34", KrikriJinja.render("{% for i in [1,2,3,4] if i > 2 %}{{ i }}{% endfor %}"))
    end

    it "sets variables" do
      assert_equal("10", KrikriJinja.render("{% set x = 5 %}{{ x * 2 }}"))
      assert_equal("12", KrikriJinja.render("{% set a, b = 1, 2 %}{{ a }}{{ b }}"))
    end

    it "supports with blocks" do
      assert_equal("3False", KrikriJinja.render("{% with a = 3 %}{{ a }}{% endwith %}{{ a is defined }}"))
    end

    it "defines and calls macros" do
      t = "{% macro greet(name, punct='!') %}hi {{ name }}{{ punct }}{% endmacro %}{{ greet('bob') }} {{ greet('ann', punct='?') }}"
      assert_equal("hi bob! hi ann?", KrikriJinja.render(t))
    end

    it "supports {% call %} with caller" do
      t = "{% macro wrap() %}<{{ caller() }}>{% endmacro %}{% call wrap() %}body{% endcall %}"
      assert_equal("<body>", KrikriJinja.render(t))
    end

    it "supports filter blocks" do
      assert_equal("ABC", KrikriJinja.render("{% filter upper %}abc{% endfilter %}"))
    end

    it "supports do" do
      assert_equal("1", KrikriJinja.render("{% set x = 1 %}{% do none %}{{ x }}"))
    end

    it "supports namespace for cross-scope mutation" do
      t = "{% set ns = namespace(count=0) %}{% for i in [1,2,3] %}{% set ns.count = ns.count + 1 %}{% endfor %}{{ ns.count }}"
      assert_equal("3", KrikriJinja.render(t))
    end
  end

  describe "filters" do
    it "applies builtin string filters" do
      assert_equal("HI hi hi 2", KrikriJinja.render("{{ 'hi'.upper() }} {{ 'HI'.lower() }} {{ ' hi ' | trim }} {{ 'ab' | length }}"))
    end

    it "applies list filters" do
      assert_equal("1-2-3 6 1 2", KrikriJinja.render("{{ [3,1,2] | sort | join('-') }} {{ [1,2,3] | sum }} {{ [1,2] | first }} {{ [1,2] | last }}"))
    end

    it "applies default" do
      assert_equal("d d d", KrikriJinja.render("{{ missing | default('d') }} {{ '' | default('d', true) }} {{ 0 | default('d', true) }}"))
    end

    it "maps and selects" do
      users = KrikriJinja.context({"users" => [{"name" => "a"}, {"name" => "b"}]})["users"].raw.as(Array(KrikriJinja::AnyValue))
      assert_equal("a,b", KrikriJinja.render("{{ users | map(attribute='name') | join(',') }}", {"users" => users}))
    end

    it "applies tests" do
      assert_equal("True True True True True", KrikriJinja.render("{{ 4 is even }} {{ 3 is odd }} {{ 9 is divisibleby 3 }} {{ x is defined }} {{ 'a' is string }}",
        {"x" => 1}))
    end

    it "applies comparison tests" do
      assert_equal("True True 2", KrikriJinja.render("{{ 1 is eq 1 }} {{ 2 is gt 1 }} {{ [1,2,3] | select('gt', 1) | list | length }}"))
    end

    it "sorts with attribute" do
      users = KrikriJinja.context({"users" => [{"n" => "b"}, {"n" => "a"}]})["users"].raw.as(Array(KrikriJinja::AnyValue))
      assert_equal("ab", KrikriJinja.render("{{ users | sort(attribute='n') | map(attribute='n') | join('') }}", {"users" => users}))
    end

    it "converts to json" do
      assert_equal("{\"a\": [1, 2]}", KrikriJinja.render("{{ data | tojson }}", KrikriJinja.context({"data" => {"a" => [1, 2]}})))
    end

    it "rounds and formats" do
      assert_equal("42.5 x=5", KrikriJinja.render("{{ 42.55 | round(1) }} {{ '%s=%d' | format('x', 5) }}"))
    end
  end

  describe "template inheritance and inclusion" do
    let(loader) do
      KrikriJinja::DictLoader.new({
        "base.html"    => "<title>{% block title %}Default{% endblock %}</title>{% block body %}{% endblock %}",
        "child.html"   => "{% extends 'base.html' %}{% block title %}{{ page }}{% endblock %}{% block body %}B{% endblock %}",
        "partial.html" => "P={{ x }}",
        "module.html"  => "{% macro double(v) %}{{ v * 2 }}{% endmacro %}{% set answer = 42 %}",
      } of String => String)
    end
    let(engine) { KrikriJinja::Engine.new(loader) }

    it "extends with block overrides" do
      assert_equal("<title>Home</title>B", engine.render_string("{% extends 'child.html' %}", KrikriJinja.context({"page" => "Home"})))
    end

    it "child blocks override base defaults" do
      assert_equal("<title>Default</title>X", engine.render_string("{% extends 'base.html' %}{% block body %}X{% endblock %}"))
    end

    it "includes templates with context" do
      assert_equal("A P=7", engine.render_string("A {% include 'partial.html' %}", KrikriJinja.context({"x" => 7})))
    end

    it "include ignore missing" do
      assert_equal("ok", engine.render_string("{% include 'nope.html' ignore missing %}ok"))
    end

    it "imports macros from modules" do
      assert_equal("42 42", engine.render_string("{% import 'module.html' as m %}{{ m.double(21) }} {{ m.answer }}"))
    end

    it "imports specific names from modules" do
      assert_equal("10", engine.render_string("{% from 'module.html' import double %}{{ double(5) }}"))
    end
  end

  describe "whitespace behavior" do
    it "strips the final newline by default, keeps it on request" do
      assert_equal("a\n\nb\n", KrikriJinja.render("a\n{% if true %}\nb\n{% endif %}\n"))
      opts = KrikriJinja::LexerOptions.new(keep_trailing_newline: true)
      assert_equal("x\n", KrikriJinja::Engine.new(nil, options: opts).render_string("x\n"))
    end

    it "supports trim_blocks and lstrip_blocks" do
      opts = KrikriJinja::LexerOptions.new(trim_blocks: true, lstrip_blocks: true)
      engine = KrikriJinja::Engine.new(nil, options: opts)
      assert_equal("a\nb\nc", engine.render_string("a\n{% if true %}\nb\n{% endif %}\nc"))
    end
  end
end
