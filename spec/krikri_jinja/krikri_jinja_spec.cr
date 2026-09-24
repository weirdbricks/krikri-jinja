require "../spec_helper"
require "../../src/krikri_jinja"

describe KrikriJinja do
  describe "variables and literals" do
    it "renders plain text" do
      KrikriJinja.render("hello").should eq("hello")
    end

    it "substitutes variables" do
      KrikriJinja.render("Hello {{ name }}!", {"name" => "world"}).should eq("Hello world!")
    end

    it "renders numbers and booleans Python-style" do
      KrikriJinja.render("{{ 1 }} {{ 2.5 }} {{ true }} {{ false }} {{ none }}").should eq("1 2.5 True False None")
    end

    it "stringifies lists and dicts repr-style" do
      KrikriJinja.render("{{ [1, 'a'] }}").should eq("[1, 'a']")
      KrikriJinja.render("{{ {'a': 1} }}").should eq("{'a': 1}")
    end

    it "supports attribute and item access" do
      ctx = KrikriJinja.context({"user" => {"name" => "bob"}, "items" => [10, 20, 30]})
      KrikriJinja.render("{{ user.name }} {{ user['name'] }} {{ items[1] }} {{ items[-1] }}", ctx)
        .should eq("bob bob 20 30")
    end

    it "supports slicing" do
      KrikriJinja.render("{{ 'abcdef'[1:3] }}{{ 'abcdef'[::-1] }}{{ [1,2,3,4][::2] }}")
        .should eq("bcfedcba[1, 3]")
    end
  end

  describe "expressions" do
    it "does arithmetic" do
      KrikriJinja.render("{{ 2 + 3 * 4 }} {{ 10 / 4 }} {{ 7 // 2 }} {{ 7 % 3 }} {{ 2 ** 10 }} {{ -5 + 2 }}")
        .should eq("14 2.5 3 1 1024 -3")
    end

    it "concatenates with ~" do
      KrikriJinja.render("{{ 'a' ~ 1 ~ true }}").should eq("a1True")
    end

    it "compares" do
      KrikriJinja.render("{{ 1 < 2 }} {{ 'a' == 'a' }} {{ 1 != 2 }} {{ 3 >= 3 }} {{ 1 if true else 2 }}")
        .should eq("True True True True 1")
    end

    it "supports in/not in" do
      KrikriJinja.render("{{ 1 in [1,2] }} {{ 'x' not in 'abc' }} {{ 'k' in {'k': 1} }}")
        .should eq("True True True")
    end

    it "supports and/or/not with short circuit" do
      KrikriJinja.render("{{ true and 5 }} {{ false or 'x' }} {{ not false }}")
        .should eq("5 x True")
    end

    it "supports conditional expressions" do
      KrikriJinja.render("{{ 'yes' if 1 > 0 else 'no' }}").should eq("yes")
    end

    it "supports list/dict literals and tuple expressions" do
      KrikriJinja.render("{{ [1, 2][1] }}{{ {'k': 'v'}['k'] }}").should eq("2v")
    end

    it "treats undefined as falsy nil" do
      KrikriJinja.render("{{ missing | default('fallback') }}").should eq("fallback")
      KrikriJinja.render("{{ 'x' if missing else 'y' }}").should eq("y")
    end
  end

  describe "statements" do
    it "runs if/elif/else" do
      t = "{% if x == 1 %}one{% elif x == 2 %}two{% else %}many{% endif %}"
      KrikriJinja.render(t, {"x" => 1}).should eq("one")
      KrikriJinja.render(t, {"x" => 2}).should eq("two")
      KrikriJinja.render(t, {"x" => 5}).should eq("many")
    end

    it "runs for loops with loop variables" do
      KrikriJinja.render("{% for i in [1,2,3] %}{{ loop.index }}:{{ i }} {% endfor %}")
        .should eq("1:1 2:2 3:3 ")
      KrikriJinja.render("{% for i in [1,2,3] %}{{ loop.last }}{% endfor %}")
        .should eq("FalseFalseTrue")
    end

    it "supports for-else" do
      KrikriJinja.render("{% for i in [] %}{{ i }}{% else %}empty{% endfor %}").should eq("empty")
    end

    it "supports unpacking in for loops" do
      KrikriJinja.render("{% for k, v in items %}{{ k }}={{ v }};{% endfor %}",
        KrikriJinja.context({"items" => [[1, "a"], [2, "b"]]}))
        .should eq("1=a;2=b;")
    end

    it "filters for-loop items" do
      KrikriJinja.render("{% for i in [1,2,3,4] if i > 2 %}{{ i }}{% endfor %}").should eq("34")
    end

    it "sets variables" do
      KrikriJinja.render("{% set x = 5 %}{{ x * 2 }}").should eq("10")
      KrikriJinja.render("{% set a, b = 1, 2 %}{{ a }}{{ b }}").should eq("12")
    end

    it "supports with blocks" do
      KrikriJinja.render("{% with a = 3 %}{{ a }}{% endwith %}{{ a is defined }}").should eq("3False")
    end

    it "defines and calls macros" do
      t = "{% macro greet(name, punct='!') %}hi {{ name }}{{ punct }}{% endmacro %}{{ greet('bob') }} {{ greet('ann', punct='?') }}"
      KrikriJinja.render(t).should eq("hi bob! hi ann?")
    end

    it "supports {% call %} with caller" do
      t = "{% macro wrap() %}<{{ caller() }}>{% endmacro %}{% call wrap() %}body{% endcall %}"
      KrikriJinja.render(t).should eq("<body>")
    end

    it "supports filter blocks" do
      KrikriJinja.render("{% filter upper %}abc{% endfilter %}").should eq("ABC")
    end

    it "supports do" do
      KrikriJinja.render("{% set x = 1 %}{% do none %}{{ x }}").should eq("1")
    end

    it "supports namespace for cross-scope mutation" do
      t = "{% set ns = namespace(count=0) %}{% for i in [1,2,3] %}{% set ns.count = ns.count + 1 %}{% endfor %}{{ ns.count }}"
      KrikriJinja.render(t).should eq("3")
    end
  end

  describe "filters" do
    it "applies builtin string filters" do
      KrikriJinja.render("{{ 'hi'.upper }} {{ 'HI'.lower }} {{ ' hi ' | trim }} {{ 'ab'.length }}")
        .should eq("HI hi hi 2")
    end

    it "applies list filters" do
      KrikriJinja.render("{{ [3,1,2] | sort | join('-') }} {{ [1,2,3] | sum }} {{ [1,2] | first }} {{ [1,2] | last }}")
        .should eq("1-2-3 6 1 2")
    end

    it "applies default" do
      KrikriJinja.render("{{ missing | default('d') }} {{ '' | default('d', true) }} {{ 0 | default('d', true) }}")
        .should eq("d d d")
    end

    it "maps and selects" do
      users = KrikriJinja.context({"users" => [{"name" => "a"}, {"name" => "b"}]})["users"].raw.as(Array(KrikriJinja::AnyValue))
      KrikriJinja.render("{{ users | map(attribute='name') | join(',') }}", {"users" => users})
        .should eq("a,b")
    end

    it "applies tests" do
      KrikriJinja.render("{{ 4 is even }} {{ 3 is odd }} {{ 9 is divisibleby 3 }} {{ x is defined }} {{ 'a' is string }}",
        {"x" => 1}).should eq("True True True True True")
    end

    it "applies comparison tests" do
      KrikriJinja.render("{{ 1 is eq 1 }} {{ 2 is gt 1 }} {{ [1,2,3] | select('gt', 1) | list | length }}")
        .should eq("True True 2")
    end

    it "sorts with attribute" do
      users = KrikriJinja.context({"users" => [{"n" => "b"}, {"n" => "a"}]})["users"].raw.as(Array(KrikriJinja::AnyValue))
      KrikriJinja.render("{{ users | sort(attribute='n') | map(attribute='n') | join('') }}", {"users" => users})
        .should eq("ab")
    end

    it "converts to json" do
      KrikriJinja.render("{{ data | tojson }}", KrikriJinja.context({"data" => {"a" => [1, 2]}}))
        .should eq("{\"a\": [1, 2]}")
    end

    it "rounds and formats" do
      KrikriJinja.render("{{ 42.55 | round(1) }} {{ '%s=%d' | format('x', 5) }}").should eq("42.6 x=5")
    end
  end

  describe "template inheritance and inclusion" do
    loader = KrikriJinja::DictLoader.new({
      "base.html"    => "<title>{% block title %}Default{% endblock %}</title>{% block body %}{% endblock %}",
      "child.html"   => "{% extends 'base.html' %}{% block title %}{{ page }}{% endblock %}{% block body %}B{% endblock %}",
      "partial.html" => "P={{ x }}",
      "module.html"  => "{% macro double(v) %}{{ v * 2 }}{% endmacro %}{% set answer = 42 %}",
    } of String => String)
    engine = KrikriJinja::Engine.new(loader)

    it "extends with block overrides" do
      engine.render_string("{% extends 'child.html' %}",KrikriJinja.context({"page" => "Home"}))
        .should eq("<title>Home</title>B")
    end

    it "child blocks override base defaults" do
      engine.render_string("{% extends 'base.html' %}{% block body %}X{% endblock %}")
        .should eq("<title>Default</title>X")
    end

    it "includes templates with context" do
      engine.render_string("A {% include 'partial.html' %}",KrikriJinja.context({"x" => 7}))
        .should eq("A P=7")
    end

    it "include ignore missing" do
      engine.render_string("{% include 'nope.html' ignore missing %}ok").should eq("ok")
    end

    it "imports macros from modules" do
      engine.render_string("{% import 'module.html' as m %}{{ m.double(21) }} {{ m.answer }}")
        .should eq("42 42")
    end

    it "imports specific names from modules" do
      engine.render_string("{% from 'module.html' import double %}{{ double(5) }}").should eq("10")
    end
  end

  describe "whitespace behavior" do
    it "keeps newlines after var tags but handles basic trimming" do
      KrikriJinja.render("a\n{% if true %}\nb\n{% endif %}\n").should eq("a\n\nb\n\n")
    end
  end
end
