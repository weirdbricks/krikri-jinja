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
      KrikriJinja.render("{{ items | unique(attribute='k') | length }}", ctx).should eq("2")
    end

    it "select by test" do
      ctx = KrikriJinja.context({"items" => [1, "a", 2, "b"]})
      KrikriJinja.render("{{ items | select('string') | join(',') }}", ctx).should eq("a,b")
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

    it "allows registering custom filters and tests" do
      KrikriJinja::BUILTIN_FILTERS["shout"] = ->(v : KrikriJinja::AnyValue, _a : Array(KrikriJinja::AnyValue), _k : Hash(String, KrikriJinja::AnyValue), _c : KrikriJinja::Context) do
        KrikriJinja::AnyValue.new(KrikriJinja.stringify(v).upcase + "!")
      end
      KrikriJinja::BUILTIN_TESTS["loud"] = ->(v : KrikriJinja::AnyValue, _a : Array(KrikriJinja::AnyValue), _k : Hash(String, KrikriJinja::AnyValue), _c : KrikriJinja::Context) do
        KrikriJinja.stringify(v).upcase == KrikriJinja.stringify(v)
      end
      KrikriJinja.render("{{ 'hey' | shout }} {{ 'HEY' is loud }}").should eq("HEY! True")
    end
  end
end
