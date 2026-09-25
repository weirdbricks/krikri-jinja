require "../spec_helper"
require "../../src/krikri_jinja"

  # Helper: render with engine-level options.
private def render_env(source : String, vars = {} of String => String,
                       autoescape = false, trim_blocks = false, lstrip_blocks = false,
                       keep_trailing_newline = false)
  opts = KrikriJinja::LexerOptions.new(trim_blocks: trim_blocks, lstrip_blocks: lstrip_blocks,
                                       keep_trailing_newline: keep_trailing_newline)
  engine = KrikriJinja::Engine.new(nil, {} of String => KrikriJinja::AnyV, opts, autoescape)
  engine.render_string(source, KrikriJinja.context(vars))
end


# Behaviors verified against real Jinja2 via the compare/ differential
# harness; expected outputs here are the observed Jinja2 results.
describe KrikriJinja do
  describe "parity: numbers" do
    it "renders bools as ints in arithmetic" do
      KrikriJinja.render("{{ true + true }} {{ true * 3 }}").should eq("2 3")
      KrikriJinja.render("{{ true ** true }} {{ true | abs }} {{ -true }}").should eq("1 1 -1")
    end

    it "matches python float repr" do
      KrikriJinja.render("{{ 1e20 }} {{ 1e-5 }} {{ -0.0 }} {{ 0.0 }}").should eq("1e+20 1e-05 -0.0 0.0")
    end

    it "supports big integers beyond Int64" do
      KrikriJinja.render("{{ 10 ** 30 }}").should eq("1000000000000000000000000000000")
      KrikriJinja.render("{{ 9223372036854775807 + 1 }}").should eq("9223372036854775808")
    end

    it "keeps ** left-associative like jinja" do
      KrikriJinja.render("{{ 2 ** 3 ** 2 }}").should eq("64")
    end

    it "treats bools as ints in equality and ordering" do
      KrikriJinja.render("{{ 1 == 1.0 }} {{ true == 1 }} {{ 0 == false }} {{ '1' == 1 }}").should eq("True True True False")
      KrikriJinja.render("{{ true == 1.0 }} {{ false == 0.0 }}").should eq("True True")
    end

    it "repeats lists and strings like python" do
      KrikriJinja.render("{{ [1] * 3 }} {{ [0] * 0 }}|").should eq("[1, 1, 1] []|")
      KrikriJinja.render("{{ 'ab' * -1 }}|").should eq("|")
    end

    it "raises on unary plus of non-numbers" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ +'5' }}")
      end
    end
  end

  describe "parity: tuples and reprs" do
    it "renders tuple literals with parentheses" do
      KrikriJinja.render("{% set t = (1, 'a') %}{{ t }} {{ t[0] }}").should eq("(1, 'a') 1")
      KrikriJinja.render("{% set t = (1,) %}{{ t }}").should eq("(1,)")
      KrikriJinja.render("{% set t = () %}{{ t }}").should eq("()")
      KrikriJinja.render("{{ (1, [2, (3,)]) }}").should eq("(1, [2, (3,)])")
    end

    it "keeps bool/int/float/none dict keys distinct in repr and lookup" do
      KrikriJinja.render("{{ {true: 1} }}").should eq("{True: 1}")
      KrikriJinja.render("{{ {1: 'a'}[1.0] }} {{ {1.0: 'a'}[1] }}").should eq("a a")
      KrikriJinja.render("{{ {1: 'a'}[1] }} {{ {true: 'a'}[true] }}").should eq("a a")
    end

    it "renders Undefined as 'Undefined' inside containers" do
      KrikriJinja.render("{{ missing }}|{{ [missing] }}|{{ {'k': missing} }}").should eq("|[Undefined]|{'k': Undefined}")
    end
  end

  describe "parity: undefined" do
    it "iterates empty and has length zero" do
      KrikriJinja.render("{% for x in missing %}x{% endfor %}|").should eq("|")
      KrikriJinja.render("{{ missing | length }}").should eq("0")
      KrikriJinja.render("{{ missing | sort }}").should eq("[]")
    end

    it "raises on attribute access and subscript" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ missing.foo.bar | default('d') }}")
      end
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ missing[0] }}")
      end
    end

    it "passes sequence/iterable tests but not string/mapping" do
      KrikriJinja.render("{{ missing is string }} {{ missing is sequence }} {{ missing is iterable }} {{ missing is mapping }}").should eq("False True True False")
    end

    it "renders empty when a conditional has no else" do
      KrikriJinja.render("{{ 'a' if missing }}|").should eq("|")
    end

    it "is not json serializable" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ missing | tojson }}")
      end
    end
  end

  describe "parity: filters" do
    it "defaults case-insensitive sorting/unique/min/max/dictsort" do
      KrikriJinja.render("{{ ['b', 'A', 'C'] | sort | join(',') }}").should eq("A,b,C")
      KrikriJinja.render("{{ ['a','A','b'] | unique | join(',') }}").should eq("a,b")
      KrikriJinja.render("{{ {'B': 1, 'a': 2} | dictsort | map('first') | join(',') }}").should eq("a,B")
    end

    it "returns undefined for first/last/min/max/random on empty" do
      KrikriJinja.render("{{ [] | first | default('e1') }} {{ [] | last | default('e2') }}").should eq("e1 e2")
      KrikriJinja.render("{{ [] | min }} {{ [] | max }} {{ [] | random }}").should eq("  ")
    end

    it "truncates with leeway and killwords like jinja" do
      KrikriJinja.render("{{ 'abcdefghijkl' | truncate(8, true, '...', 3) }}").should eq("abcde...")
      KrikriJinja.render("{{ 'ab cd ef' | truncate(6, false, '...', 0) }}").should eq("ab...")
    end

    it "wraps long words by default but not with break_long_words=false" do
      KrikriJinja.render("{{ 'aaaaaaaaaaaaaaaaaa bb' | wordwrap(10) }}").should eq("aaaaaaaaaa\naaaaaaaa\nbb")
      KrikriJinja.render("{{ 'aaaaaaaaaa bb' | wordwrap(5, false) }}").should eq("aaaaaaaaaa\nbb")
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ 'ab' | wordwrap(0) }}")
      end
    end

    it "keeps slashes in urlencode and errors on bad pairs" do
      KrikriJinja.render("{{ 'a/b' | urlencode }}").should eq("a/b")
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ ('a b',) | urlencode }}")
      end
    end

    it "does not double-escape Markup" do
      render_env("{{ '<x>' | safe | escape }}", autoescape: true).should eq("<x>")
    end

    it "uses jinja quote entities" do
      render_env("{{ \"'\\\"\" | escape }}").should eq("&#39;&#34;")
    end

    it "groups with sorted keys and default" do
      KrikriJinja.render("{% for g in items | groupby('k') %}{{ g.grouper }};{% endfor %}",
        {"items" => [{"k" => "b"}, {"k" => "a"}]}).should eq("a;b;")
      KrikriJinja.render("{% for g in items | groupby('k', default='none') %}{{ g.grouper }};{% endfor %}",
        {"items" => [{"v" => 1}, {"k" => "a", "v" => 2}]}).should eq("a;none;")
    end

    it "indents without touching blank lines" do
      KrikriJinja.render("{{ 'a\\n\\nb' | indent(2) }}|").should eq("a\n\n  b|")
    end

    it "json-encodes with sorted keys and ascii escaping" do
      KrikriJinja.render("{{ {'true': 1, 'none': 2} | tojson }}").should eq("{\"none\": 2, \"true\": 1}")
      KrikriJinja.render("{{ '<&>' | tojson }}").should eq("\"\\u003c\\u0026\\u003e\"")
      KrikriJinja.render("{{ 'hé' | tojson }}").should eq("\"h\\u00e9\"")
    end

    it "urlizes links, www names and emails" do
      KrikriJinja.render("{{ 'visit http://x.com now' | urlize }}")
        .should eq("visit <a href=\"http://x.com\" rel=\"noopener\">http://x.com</a> now")
      KrikriJinja.render("{{ 'see www.example.com here' | urlize }}")
        .should eq("see <a href=\"https://www.example.com\" rel=\"noopener\">www.example.com</a> here")
      KrikriJinja.render("{{ 'mail a@b.com ok' | urlize }}")
        .should eq("mail <a href=\"mailto:a@b.com\">a@b.com</a> ok")
    end

    it "maps generator results without length" do
      KrikriJinja.render("{{ users | map(attribute='n') | list | first }}", {"users" => [{"n" => "x"}]}).should eq("x")
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ users | selectattr('zz') | length }}", {"users" => [{"n" => "a"}]})
      end
    end
  end

  describe "parity: string methods" do
    it "supports python-style methods" do
      KrikriJinja.render("{{ 'a'.ljust(3, '-') }} {{ 'a'.rjust(3, '-') }}").should eq("a-- --a")
      KrikriJinja.render("{{ 'a=b=c'.partition('=') | join('|') }}").should eq("a|=|b=c")
      KrikriJinja.render("{{ 'a,b,c'.rsplit(',', 1) | join('|') }}").should eq("a,b|c")
      KrikriJinja.render("{{ 'a\\nb\\rc'.splitlines() | join('|') }}").should eq("a|b|c")
      KrikriJinja.render("{{ 'test_ab'.removeprefix('test_') }} {{ 'test_ab'.removesuffix('_ab') }}").should eq("ab test")
      KrikriJinja.render("{{ 'a\\tb'.expandtabs(4) }}").should eq("a   b")
      KrikriJinja.render("{{ 'AbC'.swapcase() }}").should eq("aBc")
      KrikriJinja.render("{{ '12'.isdigit() }} {{ 'ab'.isdigit() }} {{ 'ab'.isalpha() }}").should eq("True False True")
      KrikriJinja.render("{{ 'banana'.count('an') }}").should eq("2")
      KrikriJinja.render("{{ '{} and {}'.format(1, 'x') }} {{ '{0}{1}'.format('a', 'b') }}").should eq("1 and x ab")
      KrikriJinja.render("{{ 'abc 2nd'.title() }}").should eq("Abc 2Nd")
    end
  end

  describe "parity: scope" do
    it "hides loop variables from blocks and includes" do
      KrikriJinja.render("{% for i in [1,2] %}{% block b %}x{{ i }}{% endblock %}{% endfor %}").should eq("xx")
      # jinja raises UndefinedError since loop locals are invisible to includes
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"p.html" => "{{ loop.index }}"}))
          .render_string("{% for i in [1,2] %}{% include 'p.html' %}{% endfor %}", KrikriJinja.context({} of String => String))
      end
    end

    it "keeps imported macros free of caller context" do
      KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"m.html" => "{% macro g() %}{{ greeting | default('none') }}{% endmacro %}"}
      )).render_string("{% from 'm.html' import g %}{{ g() }}", KrikriJinja.context({"greeting" => "hi"}))
        .should eq("none")
    end

    it "executes child top-level sets when extending" do
      KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"base.html" => "{% block b %}{% endblock %}"}
      )).render_string("{% extends 'base.html' %}{% set x = 7 %}{% block b %}{{ x }}{% endblock %}",
        KrikriJinja.context({} of String => String)).should eq("7")
    end

    it "supports super() in block chains" do
      KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"base.html" => "{% block body %}base{% endblock %}"}
      )).render_string("{% extends 'base.html' %}{% block body %}[{{ super() }}]{% endblock %}",
        KrikriJinja.context({} of String => String)).should eq("[base]")
    end

    it "chains block overrides through super" do
      KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"base.html" => "{% block body %}base{% endblock %}",
         "mid.html" => "{% extends 'base.html' %}{% block body %}mid({{ super() }}){% endblock %}"}
      )).render_string("{% extends 'mid.html' %}{% block body %}[{{ super() }}]{% endblock %}",
        KrikriJinja.context({} of String => String)).should eq("[mid(base)]")
    end
  end

  describe "parity: globals" do
    it "exposes cycler, joiner and dict methods as callables" do
      KrikriJinja.render("{% set c = cycler('a', 'b', 'c') %}{{ c.next() }}{{ c.next() }}{{ c.next() }}{{ c.next() }}|{{ c.current }}").should eq("abca|b")
      KrikriJinja.render("{% set j = joiner(', ') %}{% for i in [1,2,3] %}{{ j() }}{{ i }}{% endfor %}").should eq("1, 2, 3")
      KrikriJinja.render("{% for v in d.values() %}{{ v }}{% endfor %}", {"d" => {"a" => 1, "b" => 2}}).should eq("12")
    end

    it "rejects float arguments to range" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for i in range(2.5) %}{{ i }}{% endfor %}")
      end
    end

    it "builds dicts from tuples" do
      KrikriJinja.render("{{ dict([('a', 1), ('b', 2)]) | dictsort | join(',') }}").should eq("('a', 1),('b', 2)")
    end
  end

  describe "parity: whitespace and lexer" do
    it "does not lstrip before {%+ tags but keeps trim_blocks" do
      render_env("  {%+ if true %}X{% endif %}", lstrip_blocks: true, trim_blocks: true).should eq("  X")
      render_env("a\n{%+ if true %}\nb\n{% endif %}\nc", trim_blocks: true).should eq("a\nb\nc")
    end

    it "trims newlines after comments with trim_blocks" do
      render_env("a\n{# c #}\nb", trim_blocks: true).should eq("a\nb")
    end

    it "normalizes CRLF in source" do
      render_env("x\r\n", keep_trailing_newline: true).should eq("x\n")
    end

    it "does not end expressions at }} inside strings or dict literals" do
      KrikriJinja.render("{{ 'a[1]}' }} {{ d['k}}'] }}", {"d" => {"k}}" => "brace"}}).should eq("a[1]} brace")
      KrikriJinja.render("{{ {'a': {'b': [1, [2]]}} | tojson }}").should eq("{\"a\": {\"b\": [1, [2]]}}")
    end

    it "parses chained unary not" do
      KrikriJinja.render("{{ not not true }}").should eq("True")
    end

    it "supports set blocks with filters and chained filter blocks" do
      KrikriJinja.render("{% set x | upper %}ab{% endset %}{{ x }}").should eq("AB")
      KrikriJinja.render("{% filter upper | trim %} ab {% endfilter %}|").should eq("AB|")
    end

    it "decodes unicode escapes in string literals" do
      KrikriJinja.render("{{ 'a\\u00e9b' }}").should eq("aéb")
    end
  end


  describe "parity: round 5" do
    it "urlize trims punctuation and escapes html without linkifying" do
      render_env("{{ 'go to http://x.com, now' | urlize }}")
        .should eq("go to <a href=\"http://x.com\" rel=\"noopener\">http://x.com</a>, now")
      render_env("{{ '(see http://x.com)' | urlize }}")
        .should eq("(see <a href=\"http://x.com\" rel=\"noopener\">http://x.com</a>)")
      render_env("{{ '<a href=\"http://x.com\">x</a>' | urlize }}")
        .should eq("&lt;a href=&#34;http://x.com&#34;&gt;x&lt;/a&gt;")
      render_env("{{ 'http://x.com?a=<b>' | urlize }}", autoescape: true)
        .should eq("<a href=\"http://x.com?a=&lt;b&gt;\" rel=\"noopener\">http://x.com?a=&lt;b&gt;</a>")
    end

    it "rejects duplicate block names in one template" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% block b %}1{% endblock %}{% block b %}2{% endblock %}")
      end
    end

    it "keeps for-loop variables visible inside blocks that contain the loop" do
      KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"base.html" => "{% block b %}{% endblock %}"}
      )).render_string(
        "{% extends 'base.html' %}{% block b %}{% for i in [1,2] %}{{ i }}{% endfor %}{% endblock %}",
        KrikriJinja.context({} of String => String)).should eq("12")
    end

    it "captures set blocks as Markup under autoescape" do
      render_env("{% set x %}<y>{% endset %}{{ x }}", autoescape: true).should eq("<y>")
    end

    it "errors on tuple arguments spread into tests" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ 1 is in (1, 2) }}")
      end
    end

    it "supports membership and equality on tuples" do
      KrikriJinja.render("{{ 2 in (1, 2) }} {{ (1, 2) == (1, 2) }} {{ (1,) == (1, 2) }}").should eq("True True False")
    end

    it "sorts groupby keys first and raises on uncomparable ones" do
      KrikriJinja.render("{% for g in items | groupby('k') %}{{ g.grouper }};{% endfor %}",
        {"items" => [{"k" => 2}, {"k" => 10}]}).should eq("2;10;")
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for g in items | groupby('k') %}{{ g.grouper }};{% endfor %}",
          {"items" => [{"k" => nil}, {"k" => nil}]})
      end
    end

    it "accepts underscore int literals and bool range args" do
      KrikriJinja.render("{{ 1_000 }}").should eq("1000")
      KrikriJinja.render("{% for i in range(true) %}{{ i }}{% endfor %}").should eq("0")
    end

    it "sums beyond Int64 via big-int fallback" do
      KrikriJinja.render("{{ [9223372036854775807, 1] | sum }}").should eq("9223372036854775808")
    end

    it "rejects super with arguments and indent on non-strings" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"base.html" => "{% block b %}B{% endblock %}"}))
          .render_string("{% extends 'base.html' %}{% block b %}{{ super(1) }}{% endblock %}",
            KrikriJinja.context({} of String => String))
      end
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ 5 | indent(2) }}")
      end
    end

    it "defaults joiner separator to ', '" do
      KrikriJinja.render("{% set j = joiner() %}{{ j() }}x{{ j() }}").should eq("x, ")
    end

    it "rejects over-called filters through map" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ ['ab', 'c'] | map('center', 3, '-') | join('|') }}")
      end
    end
  end

  describe "parity: round 6" do
    it "renders infinity and nan like python" do
      KrikriJinja.render("{{ 1e308 * 10 }}").should eq("inf")
    end

    it "raises when iterating none but not undefined" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for x in none %}x{% endfor %}")
      end
      KrikriJinja.render("{% for x in missing %}x{% else %}e{% endfor %}").should eq("e")
    end

    it "exposes str.upper/lower as callable methods" do
      KrikriJinja.render("{{ 'abc'.upper().lower() }}").should eq("abc")
    end

    it "keeps int inputs int through round" do
      KrikriJinja.render("{{ 5 | round }}").should eq("5")
      KrikriJinja.render("{{ 1234 | round(-2) }}").should eq("1200")
      KrikriJinja.render("{{ 1234.0 | round(-2) }}").should eq("1200.0")
    end

    it "counts empty substring like python" do
      KrikriJinja.render("{{ 'abc'.count('') }}").should eq("4")
    end

    it "handles negative and out-of-range find starts" do
      KrikriJinja.render("{{ 'abcabc'.find('b', -3) }} {{ 'abc'.find('b', 5) }}").should eq("4 -1")
    end

    it "json-encodes tuple, markup and typed keys" do
      KrikriJinja.render("{{ (1, 2) | tojson }}").should eq("[1, 2]")
      KrikriJinja.render("{{ ('<x>' | safe) | tojson }}").should eq("\"\\u003cx\\u003e\"")
      KrikriJinja.render("{{ {1: 'a'} | tojson }}").should eq("{\"1\": \"a\"}")
    end

    it "shows loop targets but not loop in includes" do
      KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"p.html" => "{{ i }}"}))
        .render_string("{% for i in [1,2] %}{% include 'p.html' %}{% endfor %}",
          KrikriJinja.context({} of String => String)).should eq("12")
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"p.html" => "{{ loop.index }}"}))
          .render_string("{% for i in [1,2] %}{% include 'p.html' %}{% endfor %}",
            KrikriJinja.context({} of String => String))
      end
    end

    it "rejects unknown macro kwargs unless the body uses kwargs" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% macro m(a=1) %}{{ a }}{% endmacro %}{{ m(b=2) }}")
      end
      KrikriJinja.render("{% macro m(a) %}{{ kwargs['b'] | default('nb') }}{% endmacro %}{{ m(1, b=2) }}")
        .should eq("2")
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% macro m() %}x{% endmacro %}{{ m(1, 2) }}")
      end
      KrikriJinja.render("{% macro m() %}{{ varargs | length }}{% endmacro %}{{ m(1, 2, 3) }}").should eq("3")
    end
  end

  describe "parity: round 7" do
    it "centers with python padding rule" do
      KrikriJinja.render("{{ 'ab' | center(5) }}|").should eq("  ab |")
    end
    it "supports tuple dict keys" do
      KrikriJinja.render("{{ {(1, 2): 'v'} }}").should eq("{(1, 2): 'v'}")
    end
    it "rejects bare caller parameter" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% macro m(caller) %}{{ caller }}{% endmacro %}")
      end
    end
  end

  describe "parity: round 8" do
    it "treats 1 and True as the same dict key, first form wins" do
      KrikriJinja.render("{{ {1: 'a', true: 'b'}[1] }} {{ {1: 'a', true: 'b'}[true] }}").should eq("b b")
      KrikriJinja.render("{{ {true: 'a', 1: 'b'} }}").should eq("{True: 'b'}")
    end
    it "orders tuples lexicographically" do
      KrikriJinja.render("{{ [(2,), (1,)] | sort | join(',') }}").should eq("(1,),(2,)")
    end
    it "wraps with custom wrapstring positionally" do
      KrikriJinja.render("{{ 'a b c' | wordwrap(4, true, '--') }}").should eq("a b--c")
    end
  end

  describe "parity: round 9" do
    it "exposes dict.get with default" do
      KrikriJinja.render("{{ d.get('zz', 'none') }} {{ d.get('a') }}", {"d" => {"a" => 1}}).should eq("none 1")
    end

    it "urlizes case-variant schemes with an https prefix" do
      KrikriJinja.render("{{ 'HTTP://X.COM' | urlize }}")
        .should eq("<a href=\"https://HTTP://X.COM\" rel=\"noopener\">HTTP://X.COM</a>")
      KrikriJinja.render("{{ 'ftp://files.com' | urlize }}").should eq("ftp://files.com")
    end

    it "hides super inside includes" do
      KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"base.html" => "{% block b %}B{% endblock %}", "p.html" => "{{ super is defined }}"}
      )).render_string("{% extends 'base.html' %}{% block b %}{% include 'p.html' %}{% endblock %}",
        KrikriJinja.context({} of String => String)).should eq("False")
    end
  end

  describe "parity: round 10" do
    it "renders inf and huge floats like python" do
      KrikriJinja.render("{{ 1e308 * 10 }} {{ 1e15 }}").should eq("inf 1000000000000000.0")
    end

    it "repeats Markup like strings in arithmetic" do
      # macros return Markup (a str subclass), so int * macro-result repeats
      KrikriJinja.render("{% macro m(n) %}{{ n if n < 2 else n * m(n - 1) }}{% endmacro %}{{ m(4) }}")
        .should eq("1" * 24)
    end

    it "renders Markup repr inside containers" do
      render_env("{{ ('<x>' | safe, 'y') }}", autoescape: true).should eq("(Markup(&#39;&lt;x&gt;&#39;), &#39;y&#39;)")
    end

    it "returns empty for non-integer slice steps" do
      KrikriJinja.render("{{ 'abc'[::1.5] }}|").should eq("|")
    end

    it "sums chains of big integers" do
      KrikriJinja.render("{{ [9223372036854775807, 9223372036854775807, 1] | sum }}").should eq("18446744073709551615")
    end

    it "leaves strings unchanged for non-positive indent" do
      KrikriJinja.render("{{ 'a\nb' | indent(-1) }}|").should eq("a
b|")
    end
  end


  describe "parity: round 11" do
    it "routes int64 subtraction overflow through big ints" do
      KrikriJinja.render("{{ -9223372036854775807 - 2 }}").should eq("-9223372036854775809")
    end

    it "compares Markup with strings" do
      render_env("{{ ('x' | safe) == 'x' }}").should eq("True")
    end

    it "indents blank lines only with blank=true" do
      KrikriJinja.render("{{ 'a\n\nb' | indent(2) }}|").should eq("a

  b|")
      KrikriJinja.render("{{ 'a\n\nb' | indent(2, blank=true) }}|").should eq("a
  
  b|")
    end

    it "keeps whitespace-only lines under lstrip_blocks" do
      render_env("x\n   \n{% if true %}y{% endif %}", lstrip_blocks: true).should eq("x
   
y")
      render_env("x\n  {% if true %}y{% endif %}", lstrip_blocks: true).should eq("x
y")
    end

    it "requires single-character fill for ljust/rjust/center" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ 'a'.ljust(4, 'xy') }}")
      end
    end

    it "accepts trim chars as keyword" do
      KrikriJinja.render("{{ 'xxaxx' | trim(chars='x') }}").should eq("a")
    end

    it "treats unique results as generators" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ [1,1] | unique | length }}")
      end
    end
  end

  describe "parity: round 12" do
    it "renders top-level text before extends, drops content after" do
      KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"base.html" => "{% block b %}B{% endblock %}"}))
        .render_string("x{% extends 'base.html' %}", KrikriJinja.context({} of String => String)).should eq("xB")
      KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"base.html" => "S{% block b %}D{% endblock %}E"}))
        .render_string("{% extends 'base.html' %}{% block b %}{% endblock %}tail",
          KrikriJinja.context({} of String => String)).should eq("SE")
    end

    it "scopes macros defined inside if/for bodies to that frame" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for i in [1,2] %}{% if i == 1 %}{% macro m() %}M1{% endmacro %}{% endif %}{{ m() }}{% endfor %}")
      end
      KrikriJinja.render("{% if true %}{% macro m() %}M{% endmacro %}{{ m() }}{% endif %}").should eq("M")
    end

    it "supports *args and **kwargs call spreading" do
      KrikriJinja.render("{% macro m(a, b) %}{{ a }}{{ b }}{% endmacro %}{{ m(*[1, 2]) }}").should eq("12")
    end

    it "rejects positional arguments after keyword arguments" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ [1] | map(attribute='a', 'x') | join(',') }}", {"users" => [{"a" => 1}]})
      end
    end

    it "batch yields generators without fill, lists with fill" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ [1] | batch(0) | length }}")
      end
      KrikriJinja.render("{{ [1,2,3] | batch(2, 0) | length }}").should eq("2")
    end

    it "rejects urlencode keyword arguments" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ {'a': 'b/c'} | urlencode(for_qs=true) }}")
      end
    end
  end
  describe "parity: loop details" do
    it "resets depth for nested non-recursive loops" do
      KrikriJinja.render("{% for a in [1] %}{% for b in [2] %}{{ loop.depth }}{{ loop.depth0 }}{% endfor %}{% endfor %}").should eq("10")
    end

    it "raises on wrong arity unpacking" do
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for a, b in [[1, 2, 3]] %}{{ a }}{% endfor %}")
      end
      expect_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for a, b in [[1]] %}{{ a }}{% endfor %}")
      end
    end

    it "supports nested unpack targets" do
      KrikriJinja.render("{% for (a, b), c in [[(1, 2), 3]] %}{{ a }}{{ b }}{{ c }}{% endfor %}").should eq("123")
    end

    it "slices tuples" do
      KrikriJinja.render("{{ (1, 2, 3)[1:] | join(',') }}").should eq("2,3")
    end
  end
end
