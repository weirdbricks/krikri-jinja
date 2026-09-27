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

# Keyed like a dict that arrived through a JSON round trip: the YAML
# integer keys `7:`/`10:` reached the engine as plain strings.
private def json_style_d
  KrikriJinja::AnyValue.new({"7" => KrikriJinja::AnyValue.new("seven"), "10" => KrikriJinja::AnyValue.new("ten")} of String => KrikriJinja::AnyValue)
end

# Behaviors verified against real Jinja2 via the compare/ differential
# harness; expected outputs here are the observed Jinja2 results.
describe KrikriJinja do
  describe "parity: numbers" do
    it "renders bools as ints in arithmetic" do
      assert_equal("2 3", KrikriJinja.render("{{ true + true }} {{ true * 3 }}"))
      assert_equal("1 1 -1", KrikriJinja.render("{{ true ** true }} {{ true | abs }} {{ -true }}"))
    end

    it "matches python float repr" do
      assert_equal("1e+20 1e-05 -0.0 0.0", KrikriJinja.render("{{ 1e20 }} {{ 1e-5 }} {{ -0.0 }} {{ 0.0 }}"))
    end

    it "supports big integers beyond Int64" do
      assert_equal("1000000000000000000000000000000", KrikriJinja.render("{{ 10 ** 30 }}"))
      assert_equal("9223372036854775808", KrikriJinja.render("{{ 9223372036854775807 + 1 }}"))
    end

    it "keeps ** left-associative like jinja" do
      assert_equal("64", KrikriJinja.render("{{ 2 ** 3 ** 2 }}"))
    end

    it "treats bools as ints in equality and ordering" do
      assert_equal("True True True False", KrikriJinja.render("{{ 1 == 1.0 }} {{ true == 1 }} {{ 0 == false }} {{ '1' == 1 }}"))
      assert_equal("True True", KrikriJinja.render("{{ true == 1.0 }} {{ false == 0.0 }}"))
    end

    it "repeats lists and strings like python" do
      assert_equal("[1, 1, 1] []|", KrikriJinja.render("{{ [1] * 3 }} {{ [0] * 0 }}|"))
      assert_equal("|", KrikriJinja.render("{{ 'ab' * -1 }}|"))
    end

    it "raises on unary plus of non-numbers" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ +'5' }}")
      end
    end
  end

  describe "parity: tuples and reprs" do
    it "renders tuple literals with parentheses" do
      assert_equal("(1, 'a') 1", KrikriJinja.render("{% set t = (1, 'a') %}{{ t }} {{ t[0] }}"))
      assert_equal("(1,)", KrikriJinja.render("{% set t = (1,) %}{{ t }}"))
      assert_equal("()", KrikriJinja.render("{% set t = () %}{{ t }}"))
      assert_equal("(1, [2, (3,)])", KrikriJinja.render("{{ (1, [2, (3,)]) }}"))
    end

    it "keeps bool/int/float/none dict keys distinct in repr and lookup" do
      assert_equal("{True: 1}", KrikriJinja.render("{{ {true: 1} }}"))
      assert_equal("a a", KrikriJinja.render("{{ {1: 'a'}[1.0] }} {{ {1.0: 'a'}[1] }}"))
      assert_equal("a a", KrikriJinja.render("{{ {1: 'a'}[1] }} {{ {true: 'a'}[true] }}"))
    end

    it "renders Undefined as 'Undefined' inside containers" do
      assert_equal("|[Undefined]|{'k': Undefined}", KrikriJinja.render("{{ missing }}|{{ [missing] }}|{{ {'k': missing} }}"))
    end
  end

  describe "parity: dict key lookup" do
    it "finds an integer-keyed entry by an integer index" do
      assert_equal("ten|ten|ten", KrikriJinja.render("{{ d[10] }}|{{ d[v] }}|{{ d[v | default(10)] }}",
        {"d" => json_style_d, "v" => KrikriJinja::AnyValue.new(10i64)}))
    end

    it "finds it through dict.get too" do
      assert_equal("ten|seven", KrikriJinja.render("{{ d.get(10) }}|{{ d.get('7') }}",
        {"d" => json_style_d}))
    end

    it "keeps string-keyed lookups working unchanged" do
      assert_equal("ten|False", KrikriJinja.render("{{ d['10'] }}|{{ d['nope'] is defined }}",
        {"d" => json_style_d}))
    end

    it "does not coerce a non-numeric string key into an integer match" do
      assert_equal("False", KrikriJinja.render("{{ d[10] is defined }}",
        {"d" => KrikriJinja::AnyValue.new({"a" => KrikriJinja::AnyValue.new("b")} of String => KrikriJinja::AnyValue)}))
    end

    it "still matches engine-internal integer keys exactly" do
      assert_equal("ten|seven", KrikriJinja.render("{{ {7: 'seven', 10: 'ten'}[10] }}|{{ {7: 'seven', 10: 'ten'}[v] }}",
        {"v" => KrikriJinja::AnyValue.new(7i64)}))
    end
  end

  describe "parity: undefined" do
    it "iterates empty and has length zero" do
      assert_equal("|", KrikriJinja.render("{% for x in missing %}x{% endfor %}|"))
      assert_equal("0", KrikriJinja.render("{{ missing | length }}"))
      assert_equal("[]", KrikriJinja.render("{{ missing | sort }}"))
    end

    it "raises on attribute access and subscript" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ missing.foo.bar | default('d') }}")
      end
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ missing[0] }}")
      end
    end

    it "passes sequence/iterable tests but not string/mapping" do
      assert_equal("False True True False", KrikriJinja.render("{{ missing is string }} {{ missing is sequence }} {{ missing is iterable }} {{ missing is mapping }}"))
    end

    it "supports StrictUndefined through the engine" do
      engine = KrikriJinja::Engine.new(nil, undefined: KrikriJinja::StrictUndefined.new)
      assert_raises(KrikriJinja::TemplateError) { engine.render_string("{{ missing }}") }
      assert_raises(KrikriJinja::TemplateError) { engine.render_string("{% if missing %}yes{% else %}no{% endif %}") }
      assert_equal("False fallback", engine.render_string("{{ missing is defined }} {{ missing | default('fallback') }}"))
      assert_raises(KrikriJinja::TemplateError) { engine.render_string("{% for x in missing %}{% endfor %}") }
      assert_raises(KrikriJinja::TemplateError) { engine.render_string("{{ missing | length }}") }
    end
    it "renders empty when a conditional has no else" do
      assert_equal("|", KrikriJinja.render("{{ 'a' if missing }}|"))
    end

    it "applies StrictUndefined to structured expressions and comparisons" do
      assert_raises(KrikriJinja::TemplateError) { KrikriJinja.evaluate_expression("missing", strict: true) }
      assert_raises(KrikriJinja::TemplateError) { KrikriJinja.evaluate_expression("missing == none", strict: true) }
      assert_equal("fallback", KrikriJinja.evaluate_expression("missing | default('fallback')", strict: true).not_nil!.as_s)
      assert_equal(false, KrikriJinja.evaluate_expression("missing is defined", strict: true).not_nil!.raw)
    end

    it "is not json serializable" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ missing | tojson }}")
      end
    end
  end

  describe "parity: filters" do
    it "defaults case-insensitive sorting/unique/min/max/dictsort" do
      assert_equal("A,b,C", KrikriJinja.render("{{ ['b', 'A', 'C'] | sort | join(',') }}"))
      assert_equal("a,b", KrikriJinja.render("{{ ['a','A','b'] | unique | join(',') }}"))
      assert_equal("a,B", KrikriJinja.render("{{ {'B': 1, 'a': 2} | dictsort | map('first') | join(',') }}"))
    end

    it "returns undefined for first/last/min/max/random on empty" do
      assert_equal("e1 e2", KrikriJinja.render("{{ [] | first | default('e1') }} {{ [] | last | default('e2') }}"))
      assert_equal("  ", KrikriJinja.render("{{ [] | min }} {{ [] | max }} {{ [] | random }}"))
    end

    it "truncates with leeway and killwords like jinja" do
      assert_equal("abcde...", KrikriJinja.render("{{ 'abcdefghijkl' | truncate(8, true, '...', 3) }}"))
      assert_equal("ab...", KrikriJinja.render("{{ 'ab cd ef' | truncate(6, false, '...', 0) }}"))
    end

    it "wraps long words by default but not with break_long_words=false" do
      assert_equal("aaaaaaaaaa\naaaaaaaa\nbb", KrikriJinja.render("{{ 'aaaaaaaaaaaaaaaaaa bb' | wordwrap(10) }}"))
      assert_equal("aaaaaaaaaa\nbb", KrikriJinja.render("{{ 'aaaaaaaaaa bb' | wordwrap(5, false) }}"))
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ 'ab' | wordwrap(0) }}")
      end
    end

    it "keeps slashes in urlencode and errors on bad pairs" do
      assert_equal("a/b", KrikriJinja.render("{{ 'a/b' | urlencode }}"))
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ ('a b',) | urlencode }}")
      end
    end

    it "does not double-escape Markup" do
      assert_equal("<x>", render_env("{{ '<x>' | safe | escape }}", autoescape: true))
    end

    it "uses jinja quote entities" do
      assert_equal("&#39;&#34;", render_env("{{ \"'\\\"\" | escape }}"))
    end

    it "groups with sorted keys and default" do
      assert_equal("a;b;", KrikriJinja.render("{% for g in items | groupby('k') %}{{ g.grouper }};{% endfor %}",
        {"items" => [{"k" => "b"}, {"k" => "a"}]}))
      assert_equal("a;none;", KrikriJinja.render("{% for g in items | groupby('k', default='none') %}{{ g.grouper }};{% endfor %}",
        {"items" => [{"v" => 1}, {"k" => "a", "v" => 2}]}))
    end

    it "indents without touching blank lines" do
      assert_equal("a\n\n  b|", KrikriJinja.render("{{ 'a\\n\\nb' | indent(2) }}|"))
    end

    it "json-encodes with sorted keys and ascii escaping" do
      assert_equal("{\"none\": 2, \"true\": 1}", KrikriJinja.render("{{ {'true': 1, 'none': 2} | tojson }}"))
      assert_equal("\"\\u003c\\u0026\\u003e\"", KrikriJinja.render("{{ '<&>' | tojson }}"))
      assert_equal("\"h\\u00e9\"", KrikriJinja.render("{{ 'hé' | tojson }}"))
    end

    it "urlizes links, www names and emails" do
      assert_equal("visit <a href=\"http://x.com\" rel=\"noopener\">http://x.com</a> now", KrikriJinja.render("{{ 'visit http://x.com now' | urlize }}"))
      assert_equal("see <a href=\"https://www.example.com\" rel=\"noopener\">www.example.com</a> here", KrikriJinja.render("{{ 'see www.example.com here' | urlize }}"))
      assert_equal("mail <a href=\"mailto:a@b.com\">a@b.com</a> ok", KrikriJinja.render("{{ 'mail a@b.com ok' | urlize }}"))
    end

    it "maps generator results without length" do
      assert_equal("x", KrikriJinja.render("{{ users | map(attribute='n') | list | first }}", {"users" => [{"n" => "x"}]}))
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ users | selectattr('zz') | length }}", {"users" => [{"n" => "a"}]})
      end
    end
  end

  describe "parity: string methods" do
    it "supports python-style methods" do
      assert_equal("a-- --a", KrikriJinja.render("{{ 'a'.ljust(3, '-') }} {{ 'a'.rjust(3, '-') }}"))
      assert_equal("a|=|b=c", KrikriJinja.render("{{ 'a=b=c'.partition('=') | join('|') }}"))
      assert_equal("a,b|c", KrikriJinja.render("{{ 'a,b,c'.rsplit(',', 1) | join('|') }}"))
      assert_equal("a|b|c", KrikriJinja.render("{{ 'a\\nb\\rc'.splitlines() | join('|') }}"))
      assert_equal("ab test", KrikriJinja.render("{{ 'test_ab'.removeprefix('test_') }} {{ 'test_ab'.removesuffix('_ab') }}"))
      assert_equal("a   b", KrikriJinja.render("{{ 'a\\tb'.expandtabs(4) }}"))
      assert_equal("aBc", KrikriJinja.render("{{ 'AbC'.swapcase() }}"))
      assert_equal("True False True", KrikriJinja.render("{{ '12'.isdigit() }} {{ 'ab'.isdigit() }} {{ 'ab'.isalpha() }}"))
      assert_equal("2", KrikriJinja.render("{{ 'banana'.count('an') }}"))
      assert_equal("1 and x ab", KrikriJinja.render("{{ '{} and {}'.format(1, 'x') }} {{ '{0}{1}'.format('a', 'b') }}"))
      assert_equal("Abc 2Nd", KrikriJinja.render("{{ 'abc 2nd'.title() }}"))
    end
  end

  describe "parity: scope" do
    it "hides loop variables from blocks and includes" do
      assert_equal("xx", KrikriJinja.render("{% for i in [1,2] %}{% block b %}x{{ i }}{% endblock %}{% endfor %}"))
      # jinja raises UndefinedError since loop locals are invisible to includes
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"p.html" => "{{ loop.index }}"}))
          .render_string("{% for i in [1,2] %}{% include 'p.html' %}{% endfor %}", KrikriJinja.context({} of String => String))
      end
    end

    it "keeps imported macros free of caller context" do
      assert_equal("none", KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"m.html" => "{% macro g() %}{{ greeting | default('none') }}{% endmacro %}"}
      )).render_string("{% from 'm.html' import g %}{{ g() }}", KrikriJinja.context({"greeting" => "hi"})))
    end

    it "executes child top-level sets when extending" do
      assert_equal("7", KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"base.html" => "{% block b %}{% endblock %}"}
      )).render_string("{% extends 'base.html' %}{% set x = 7 %}{% block b %}{{ x }}{% endblock %}",
        KrikriJinja.context({} of String => String)))
    end

    it "supports super() in block chains" do
      assert_equal("[base]", KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"base.html" => "{% block body %}base{% endblock %}"}
      )).render_string("{% extends 'base.html' %}{% block body %}[{{ super() }}]{% endblock %}",
        KrikriJinja.context({} of String => String)))
    end

    it "chains block overrides through super" do
      assert_equal("[mid(base)]", KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"base.html" => "{% block body %}base{% endblock %}",
         "mid.html"  => "{% extends 'base.html' %}{% block body %}mid({{ super() }}){% endblock %}"}
      )).render_string("{% extends 'mid.html' %}{% block body %}[{{ super() }}]{% endblock %}",
        KrikriJinja.context({} of String => String)))
    end
  end

  describe "parity: globals" do
    it "exposes cycler, joiner and dict methods as callables" do
      assert_equal("abca|b", KrikriJinja.render("{% set c = cycler('a', 'b', 'c') %}{{ c.next() }}{{ c.next() }}{{ c.next() }}{{ c.next() }}|{{ c.current }}"))
      assert_equal("1, 2, 3", KrikriJinja.render("{% set j = joiner(', ') %}{% for i in [1,2,3] %}{{ j() }}{{ i }}{% endfor %}"))
      assert_equal("12", KrikriJinja.render("{% for v in d.values() %}{{ v }}{% endfor %}", {"d" => {"a" => 1, "b" => 2}}))
    end

    it "rejects float arguments to range" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for i in range(2.5) %}{{ i }}{% endfor %}")
      end
    end

    it "rejects invalid range arity and string steps" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for i in range(1, 3, '2') %}{{ i }}{% endfor %}")
      end
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for i in range(1, 3, 1, 9) %}{{ i }}{% endfor %}")
      end
    end

    it "builds dicts from tuples" do
      assert_equal("('a', 1),('b', 2)", KrikriJinja.render("{{ dict([('a', 1), ('b', 2)]) | dictsort | join(',') }}"))
    end
  end

  describe "parity: whitespace and lexer" do
    it "does not lstrip before {%+ tags but keeps trim_blocks" do
      assert_equal("  X", render_env("  {%+ if true %}X{% endif %}", lstrip_blocks: true, trim_blocks: true))
      assert_equal("a\nb\nc", render_env("a\n{%+ if true %}\nb\n{% endif %}\nc", trim_blocks: true))
    end

    it "trims newlines after comments with trim_blocks" do
      assert_equal("a\nb", render_env("a\n{# c #}\nb", trim_blocks: true))
    end

    # Both verified against real Jinja2 3.1.6: a `{%-` strips only the
    # whitespace directly abutting it - if trim_blocks or a right-strip
    # already consumed the whitespace between the previous tag and the
    # `{%-`, the strip must not reach back into earlier content.
    it "does not let {%- reach past whitespace another tag already consumed" do
      assert_equal("Z", render_env("{% if true %}\n{%- endif %}Z", trim_blocks: true))
      assert_equal("a", render_env("{% if true -%}a\n  {%- endif %}", trim_blocks: true))
    end

    it "keeps raw text adjacent to endraw out of a following {%- strip" do
      assert_equal("aXb", render_env("a\n{%- raw %}X{% endraw -%}\nb", trim_blocks: true))
      assert_equal("aXY", render_env("a\n{%- raw %}X{% endraw %}\n{%- if true %}Y{% endif %}"))
    end

    it "normalizes CRLF in source" do
      assert_equal("x\n", render_env("x\r\n", keep_trailing_newline: true))
    end

    it "does not end expressions at }} inside strings or dict literals" do
      assert_equal("a[1]} brace", KrikriJinja.render("{{ 'a[1]}' }} {{ d['k}}'] }}", {"d" => {"k}}" => "brace"}}))
      assert_equal("{\"a\": {\"b\": [1, [2]]}}", KrikriJinja.render("{{ {'a': {'b': [1, [2]]}} | tojson }}"))
    end

    it "parses chained unary not" do
      assert_equal("True", KrikriJinja.render("{{ not not true }}"))
    end

    it "supports set blocks with filters and chained filter blocks" do
      assert_equal("AB", KrikriJinja.render("{% set x | upper %}ab{% endset %}{{ x }}"))
      assert_equal("AB|", KrikriJinja.render("{% filter upper | trim %} ab {% endfilter %}|"))
    end

    it "decodes unicode escapes in string literals" do
      assert_equal("aéb", KrikriJinja.render("{{ 'a\\u00e9b' }}"))
    end
  end

  describe "parity: round 5" do
    it "urlize trims punctuation and escapes html without linkifying" do
      assert_equal("go to <a href=\"http://x.com\" rel=\"noopener\">http://x.com</a>, now", render_env("{{ 'go to http://x.com, now' | urlize }}"))
      assert_equal("(see <a href=\"http://x.com\" rel=\"noopener\">http://x.com</a>)", render_env("{{ '(see http://x.com)' | urlize }}"))
      assert_equal("&lt;a href=&#34;http://x.com&#34;&gt;x&lt;/a&gt;", render_env("{{ '<a href=\"http://x.com\">x</a>' | urlize }}"))
      assert_equal("<a href=\"http://x.com?a=&lt;b&gt;\" rel=\"noopener\">http://x.com?a=&lt;b&gt;</a>", render_env("{{ 'http://x.com?a=<b>' | urlize }}", autoescape: true))
    end

    it "rejects duplicate block names in one template" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% block b %}1{% endblock %}{% block b %}2{% endblock %}")
      end
    end

    it "keeps for-loop variables visible inside blocks that contain the loop" do
      assert_equal("12", KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"base.html" => "{% block b %}{% endblock %}"}
      )).render_string(
        "{% extends 'base.html' %}{% block b %}{% for i in [1,2] %}{{ i }}{% endfor %}{% endblock %}",
        KrikriJinja.context({} of String => String)))
    end

    it "captures set blocks as Markup under autoescape" do
      assert_equal("<y>", render_env("{% set x %}<y>{% endset %}{{ x }}", autoescape: true))
    end

    it "errors on tuple arguments spread into tests" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ 1 is in (1, 2) }}")
      end
    end

    it "supports membership and equality on tuples" do
      assert_equal("True True False", KrikriJinja.render("{{ 2 in (1, 2) }} {{ (1, 2) == (1, 2) }} {{ (1,) == (1, 2) }}"))
    end

    it "sorts groupby keys first and raises on uncomparable ones" do
      assert_equal("2;10;", KrikriJinja.render("{% for g in items | groupby('k') %}{{ g.grouper }};{% endfor %}",
        {"items" => [{"k" => 2}, {"k" => 10}]}))
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for g in items | groupby('k') %}{{ g.grouper }};{% endfor %}",
          {"items" => [{"k" => nil}, {"k" => nil}]})
      end
    end

    it "accepts underscore int literals and bool range args" do
      assert_equal("1000", KrikriJinja.render("{{ 1_000 }}"))
      assert_equal("0", KrikriJinja.render("{% for i in range(true) %}{{ i }}{% endfor %}"))
    end

    it "sums beyond Int64 via big-int fallback" do
      assert_equal("9223372036854775808", KrikriJinja.render("{{ [9223372036854775807, 1] | sum }}"))
    end

    it "rejects super with arguments and indent on non-strings" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"base.html" => "{% block b %}B{% endblock %}"}))
          .render_string("{% extends 'base.html' %}{% block b %}{{ super(1) }}{% endblock %}",
            KrikriJinja.context({} of String => String))
      end
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ 5 | indent(2) }}")
      end
    end

    it "defaults joiner separator to ', '" do
      assert_equal("x, ", KrikriJinja.render("{% set j = joiner() %}{{ j() }}x{{ j() }}"))
    end

    it "rejects over-called filters through map" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ ['ab', 'c'] | map('center', 3, '-') | join('|') }}")
      end
    end
  end

  describe "parity: round 6" do
    it "renders infinity and nan like python" do
      assert_equal("inf", KrikriJinja.render("{{ 1e308 * 10 }}"))
    end

    it "raises when iterating none but not undefined" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for x in none %}x{% endfor %}")
      end
      assert_equal("e", KrikriJinja.render("{% for x in missing %}x{% else %}e{% endfor %}"))
    end

    it "exposes str.upper/lower as callable methods" do
      assert_equal("abc", KrikriJinja.render("{{ 'abc'.upper().lower() }}"))
    end

    it "keeps int inputs int through round" do
      assert_equal("5", KrikriJinja.render("{{ 5 | round }}"))
      assert_equal("1200", KrikriJinja.render("{{ 1234 | round(-2) }}"))
      assert_equal("1200.0", KrikriJinja.render("{{ 1234.0 | round(-2) }}"))
    end

    it "counts empty substring like python" do
      assert_equal("4", KrikriJinja.render("{{ 'abc'.count('') }}"))
    end

    it "handles negative and out-of-range find starts" do
      assert_equal("4 -1", KrikriJinja.render("{{ 'abcabc'.find('b', -3) }} {{ 'abc'.find('b', 5) }}"))
    end

    it "json-encodes tuple, markup and typed keys" do
      assert_equal("[1, 2]", KrikriJinja.render("{{ (1, 2) | tojson }}"))
      assert_equal("\"\\u003cx\\u003e\"", KrikriJinja.render("{{ ('<x>' | safe) | tojson }}"))
      assert_equal("{\"1\": \"a\"}", KrikriJinja.render("{{ {1: 'a'} | tojson }}"))
    end

    it "shows loop targets but not loop in includes" do
      assert_equal("12", KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"p.html" => "{{ i }}"}))
        .render_string("{% for i in [1,2] %}{% include 'p.html' %}{% endfor %}",
          KrikriJinja.context({} of String => String)))
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"p.html" => "{{ loop.index }}"}))
          .render_string("{% for i in [1,2] %}{% include 'p.html' %}{% endfor %}",
            KrikriJinja.context({} of String => String))
      end
    end

    it "rejects unknown macro kwargs unless the body uses kwargs" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% macro m(a=1) %}{{ a }}{% endmacro %}{{ m(b=2) }}")
      end
      assert_equal("2", KrikriJinja.render("{% macro m(a) %}{{ kwargs['b'] | default('nb') }}{% endmacro %}{{ m(1, b=2) }}"))
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% macro m() %}x{% endmacro %}{{ m(1, 2) }}")
      end
      assert_equal("3", KrikriJinja.render("{% macro m() %}{{ varargs | length }}{% endmacro %}{{ m(1, 2, 3) }}"))
    end
  end

  describe "parity: round 7" do
    it "centers with python padding rule" do
      assert_equal("  ab |", KrikriJinja.render("{{ 'ab' | center(5) }}|"))
    end
    it "supports tuple dict keys" do
      assert_equal("{(1, 2): 'v'}", KrikriJinja.render("{{ {(1, 2): 'v'} }}"))
    end
    it "rejects bare caller parameter" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% macro m(caller) %}{{ caller }}{% endmacro %}")
      end
    end
  end

  describe "parity: round 8" do
    it "treats 1 and True as the same dict key, first form wins" do
      assert_equal("b b", KrikriJinja.render("{{ {1: 'a', true: 'b'}[1] }} {{ {1: 'a', true: 'b'}[true] }}"))
      assert_equal("{True: 'b'}", KrikriJinja.render("{{ {true: 'a', 1: 'b'} }}"))
    end
    it "orders tuples lexicographically" do
      assert_equal("(1,),(2,)", KrikriJinja.render("{{ [(2,), (1,)] | sort | join(',') }}"))
    end
    it "wraps with custom wrapstring positionally" do
      assert_equal("a b--c", KrikriJinja.render("{{ 'a b c' | wordwrap(4, true, '--') }}"))
    end
  end

  describe "parity: round 9" do
    it "exposes dict.get with default" do
      assert_equal("none 1", KrikriJinja.render("{{ d.get('zz', 'none') }} {{ d.get('a') }}", {"d" => {"a" => 1}}))
    end

    it "urlizes case-variant schemes with an https prefix" do
      assert_equal("<a href=\"https://HTTP://X.COM\" rel=\"noopener\">HTTP://X.COM</a>", KrikriJinja.render("{{ 'HTTP://X.COM' | urlize }}"))
      assert_equal("ftp://files.com", KrikriJinja.render("{{ 'ftp://files.com' | urlize }}"))
    end

    it "hides super inside includes" do
      assert_equal("False", KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"base.html" => "{% block b %}B{% endblock %}", "p.html" => "{{ super is defined }}"}
      )).render_string("{% extends 'base.html' %}{% block b %}{% include 'p.html' %}{% endblock %}",
        KrikriJinja.context({} of String => String)))
    end
  end

  describe "parity: round 10" do
    it "renders inf and huge floats like python" do
      assert_equal("inf 1000000000000000.0", KrikriJinja.render("{{ 1e308 * 10 }} {{ 1e15 }}"))
    end

    it "repeats Markup like strings in arithmetic" do
      # macros return Markup (a str subclass), so int * macro-result repeats
      assert_equal("1" * 24, KrikriJinja.render("{% macro m(n) %}{{ n if n < 2 else n * m(n - 1) }}{% endmacro %}{{ m(4) }}"))
    end

    it "renders Markup repr inside containers" do
      assert_equal("(Markup(&#39;&lt;x&gt;&#39;), &#39;y&#39;)", render_env("{{ ('<x>' | safe, 'y') }}", autoescape: true))
    end

    it "returns empty for non-integer slice steps" do
      assert_equal("|", KrikriJinja.render("{{ 'abc'[::1.5] }}|"))
    end

    it "sums chains of big integers" do
      assert_equal("18446744073709551615", KrikriJinja.render("{{ [9223372036854775807, 9223372036854775807, 1] | sum }}"))
    end

    it "leaves strings unchanged for non-positive indent" do
      assert_equal("a
b|", KrikriJinja.render("{{ 'a\nb' | indent(-1) }}|"))
    end
  end

  describe "parity: round 11" do
    it "routes int64 subtraction overflow through big ints" do
      assert_equal("-9223372036854775809", KrikriJinja.render("{{ -9223372036854775807 - 2 }}"))
    end

    it "compares Markup with strings" do
      assert_equal("True", render_env("{{ ('x' | safe) == 'x' }}"))
    end

    it "indents blank lines only with blank=true" do
      assert_equal("a\n\n  b|", KrikriJinja.render("{{ 'a\n\nb' | indent(2) }}|"))
      assert_equal("a\n  \n  b|", KrikriJinja.render("{{ 'a\n\nb' | indent(2, blank=true) }}|"))
    end

    it "keeps whitespace-only lines under lstrip_blocks" do
      assert_equal("x\n   \ny", render_env("x\n   \n{% if true %}y{% endif %}", lstrip_blocks: true))
      assert_equal("x
y", render_env("x\n  {% if true %}y{% endif %}", lstrip_blocks: true))
    end

    it "requires single-character fill for ljust/rjust/center" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ 'a'.ljust(4, 'xy') }}")
      end
    end

    it "accepts trim chars as keyword" do
      assert_equal("a", KrikriJinja.render("{{ 'xxaxx' | trim(chars='x') }}"))
    end

    it "treats unique results as generators" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ [1,1] | unique | length }}")
      end
    end
  end

  describe "parity: round 12" do
    it "renders top-level text before extends, drops content after" do
      assert_equal("xB", KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"base.html" => "{% block b %}B{% endblock %}"}))
        .render_string("x{% extends 'base.html' %}", KrikriJinja.context({} of String => String)))
      assert_equal("SE", KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"base.html" => "S{% block b %}D{% endblock %}E"}))
        .render_string("{% extends 'base.html' %}{% block b %}{% endblock %}tail",
          KrikriJinja.context({} of String => String)))
    end

    it "scopes macros defined inside if/for bodies to that frame" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for i in [1,2] %}{% if i == 1 %}{% macro m() %}M1{% endmacro %}{% endif %}{{ m() }}{% endfor %}")
      end
      assert_equal("M", KrikriJinja.render("{% if true %}{% macro m() %}M{% endmacro %}{{ m() }}{% endif %}"))
    end

    it "supports *args and **kwargs call spreading" do
      assert_equal("12", KrikriJinja.render("{% macro m(a, b) %}{{ a }}{{ b }}{% endmacro %}{{ m(*[1, 2]) }}"))
    end

    it "rejects positional arguments after keyword arguments" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ [1] | map(attribute='a', 'x') | join(',') }}", {"users" => [{"a" => 1}]})
      end
    end

    it "batch yields generators without fill, lists with fill" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ [1] | batch(0) | length }}")
      end
      assert_equal("2", KrikriJinja.render("{{ [1,2,3] | batch(2, 0) | length }}"))
    end

    it "rejects urlencode keyword arguments" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ {'a': 'b/c'} | urlencode(for_qs=true) }}")
      end
    end
  end

  describe "parity: round 13" do
    it "compares huge ints and floats exactly" do
      assert_equal("False", KrikriJinja.render("{{ 9223372036854775807 == 9223372036854775807.0 }}"))
      assert_equal("True", KrikriJinja.render("{{ 3 == 3.0 }}"))
    end

    it "accepts Markup in indent and rejects none width" do
      assert_equal("  a\n  b|", render_env("{% filter indent(2, true) %}a\nb{% endfilter %}|", autoescape: true))
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ 'a\nb' | indent(none) }}")
      end
    end

    it "maps numeric attributes as subscripts" do
      assert_equal("a", KrikriJinja.render("{{ [(1, 'a')] | map(attribute=1) | join(',') }}"))
    end

    it "decodes numeric html entities in striptags" do
      assert_equal("aAb", KrikriJinja.render("{{ 'a&#65;b' | striptags }}"))
    end

    it "treats unicode digits with isdigit" do
      assert_equal("True", KrikriJinja.render("{{ '\u0660'.isdigit() }}"))
    end
  end

  describe "parity: round 14" do
    it "rejects kwargs that duplicate positional macro arguments" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% macro m(a) %}{{ a }}{% endmacro %}{{ m(1, a=2) }}")
      end
    end

    it "exposes int.bit_length" do
      assert_equal("1 9", KrikriJinja.render("{{ (1).bit_length() }} {{ (256).bit_length() }}"))
    end
  end

  describe "parity: round 15" do
    it "treats dotted filter names as one unknown filter" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ [1,2] | first.to_s }}")
      end
    end

    it "trims the newline after endraw with trim_blocks" do
      assert_equal("a\n\nb\nc", render_env("a\n{% raw %}\nb\n{% endraw %}\nc", trim_blocks: true))
    end
  end

  describe "parity: round 16" do
    it "isolates block registries of included templates" do
      assert_equal("PC", KrikriJinja::Engine.new(KrikriJinja::DictLoader.new(
        {"p.html" => "{% block b %}P{% endblock %}"}
      )).render_string("{% include 'p.html' %}{% block b %}C{% endblock %}",
        KrikriJinja.context({} of String => String)))
    end
  end

  describe "parity: round 17" do
    it "compares Markup values with each other" do
      assert_equal("True", render_env("{{ ('x' | safe) == ('x' | safe) }}"))
    end
  end

  describe "parity: round 18" do
    it "casts generator results to lists in reverse but not last" do
      assert_equal("2,1", KrikriJinja.render("{{ [1,2] | map('string') | reverse | join(',') }}"))
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ [1,2] | map('string') | last }}")
      end
    end

    it "keeps trim results Markup and macro results plain without autoescape" do
      assert_equal("<x>", render_env("{{ ('<x>' | safe) | trim | escape }}"))
      assert_equal("3", render_env("{% macro m() %}<b>{% endmacro %}{{ m() | length }}"))
      assert_equal("<b>", render_env("{% macro m() %}<b>{% endmacro %}{{ m() | escape }}", autoescape: true))
    end

    it "shows loop to includes inside recursive loops only" do
      assert_equal("True", KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"p.html" => "{{ loop is defined }}"}))
        .render_string("{% for i in [1] recursive %}{% include 'p.html' %}{% endfor %}",
          KrikriJinja.context({} of String => String)))
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja::Engine.new(KrikriJinja::DictLoader.new({"p.html" => "{{ loop.index }}"}))
          .render_string("{% for i in [1,2] %}{% include 'p.html' %}{% endfor %}",
            KrikriJinja.context({} of String => String))
      end
    end
  end

  describe "parity: round 19" do
    it "groups case-insensitively by default, keeping the first key form" do
      assert_equal("A;", KrikriJinja.render("{% for g in items | groupby('k') %}{{ g.grouper }};{% endfor %}",
        {"items" => [{"k" => "A"}, {"k" => "a"}]}))
    end

    it "lstrips before comment tags too" do
      assert_equal("x\n\ny", render_env("x\n  {# c #}\ny", lstrip_blocks: true))
    end
  end

  describe "parity: round 20" do
    it "compares big-int strings with ints exactly" do
      assert_equal("True", KrikriJinja.render("{{ 9223372036854775807 + 1 > 9223372036854775807 }}"))
      assert_equal("True", KrikriJinja.render("{{ 9223372036854775808 == 9223372036854775808 }}"))
    end

    it "raises on zero raised to a negative power" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ 0 ** -1 }}")
      end
    end
  end
  describe "parity: loop details" do
    it "resets depth for nested non-recursive loops" do
      assert_equal("10", KrikriJinja.render("{% for a in [1] %}{% for b in [2] %}{{ loop.depth }}{{ loop.depth0 }}{% endfor %}{% endfor %}"))
    end

    it "raises on wrong arity unpacking" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for a, b in [[1, 2, 3]] %}{{ a }}{% endfor %}")
      end
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% for a, b in [[1]] %}{{ a }}{% endfor %}")
      end
    end

    it "supports nested unpack targets" do
      assert_equal("123", KrikriJinja.render("{% for (a, b), c in [[(1, 2), 3]] %}{{ a }}{{ b }}{{ c }}{% endfor %}"))
    end

    it "slices tuples" do
      assert_equal("2,3", KrikriJinja.render("{{ (1, 2, 3)[1:] | join(',') }}"))
    end
  end
end
