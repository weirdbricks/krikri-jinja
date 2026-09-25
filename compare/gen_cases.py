#!/usr/bin/env python3
"""Generates compare/cases.json - the shared differential test corpus.

Each case is rendered by both real Jinja2 (compare/render.py) and
krikri-jinja (compare/render.cr); results must match byte for byte.
"""
import json

cases = []


def add(name, template, data=None, templates=None, **env):
    case = {"name": name, "template": template, "data": data or {}}
    if templates:
        case["templates"] = templates
    if env:
        case["env"] = env
    cases.append(case)


# --- literals and output ------------------------------------------------
add("plain", "hello")
add("var", "Hello {{ name }}!", {"name": "world"})
add("num literals", "{{ 1 }} {{ 2.5 }} {{ true }} {{ false }} {{ none }}")
add("undefined var renders empty", "[{{ missing }}]")
add("undefined attr", "{{ obj.missing }}|{{ obj['missing'] }}", {"obj": {"a": 1}})
add("none literal", "{{ none }} {{ x | default('d') }}", {"x": None})
add("list repr", "{{ [1, 'a', true, none] }}")
add("dict repr", "{{ {'a': 1, 'b': 'x'} }}")
add("adjacent strings", "{{ 'ab' 'cd' }}")
add("string escapes", "{{ 'a\\tb\\n\\'q\\'' }}")
add("hex oct bin", "{{ 0x1f }} {{ 0o17 }} {{ 0b101 }}")
add("negative float", "{{ -2.5 }} {{ 1e3 }}")

# --- arithmetic ----------------------------------------------------------
add("arith", "{{ 2 + 3 * 4 }} {{ 10 / 4 }} {{ 7 // 2 }} {{ 7 % 3 }} {{ 2 ** 10 }}")
add("neg div mod", "{{ -7 // 2 }} {{ -7 % 2 }} {{ 7 % -2 }} {{ 7.5 // 2 }}")
add("unary", "{{ -5 + 2 }} {{ +3 }} {{ -(2 + 3) }}")
add("float mix", "{{ 1 + 2.5 }} {{ 3 * 0.5 }}")
add("string mult", "{{ 'ab' * 3 }}")
add("concat", "{{ 'a' ~ 1 ~ true ~ none }}")
add("power float", "{{ 2 ** 0.5 }} {{ 9 ** 0.5 }}")

# --- comparisons and logic ----------------------------------------------
add("compare", "{{ 1 < 2 }} {{ 'a' == 'a' }} {{ 2 != 2 }} {{ 3 >= 3 }} {{ 1 <= 0 }}")
add("chained", "{{ 1 < 2 < 3 }} {{ 1 < 2 > 5 }}")
add("in ops", "{{ 1 in [1,2] }} {{ 'x' not in 'abc' }} {{ 'k' in {'k': 1} }} {{ 'a' in 'abc' }}")
add("and or", "{{ true and 5 }} {{ false or 'x' }} {{ not false }} {{ not 0 }}")
add("cond expr", "{{ 'yes' if 1 > 0 else 'no' }} {{ 'y' if 0 else 'n' }} {{ 'x' if 1 }}")
add("undefined truthiness", "{{ 'y' if missing else 'n' }}")

# --- attribute/item/slice ------------------------------------------------
add("getattr getitem", "{{ user.name }} {{ user['name'] }}", {"user": {"name": "bob"}})
add("list index", "{{ items[1] }} {{ items[-1] }}", {"items": [10, 20, 30]})
add("slices", "{{ 'abcdef'[1:3] }}|{{ 'abcdef'[::-1] }}|{{ [1,2,3,4][::2] }}|{{ [1,2,3,4][1:] }}")
add("str methods", "{{ 'hi' | upper }} {{ 'HI' | lower }} {{ 'ab' | length }} {{ 'a-b'.replace('-', '+') }} {{ 'a,b,c'.split(',') | join(';') }}")
add("list methods", "{{ items | first }} {{ items | last }} {{ items | length }}", {"items": [1, 2, 3]})

# --- filters -------------------------------------------------------------
add("upper lower", "{{ 'hi' | upper }} {{ 'HI' | lower }} {{ 'hi there' | capitalize }}")
add("title trim", "{{ 'hELlO wORld' | title }} {{ '  x ' | trim }}")
add("replace", "{{ 'aaa'.replace('a', 'b', 2) }} {{ 'aXbX'.replace('X', '-') }}")
add("default", "{{ missing | default('d') }} {{ '' | default('d', true) }} {{ 0 | default('d', true) }} {{ none | default('n') }}")
add("join", "{{ [1,2,3] | join('-') }} {{ ['a','b'] | join }}")
add("join attr", "{{ users | join(',', attribute='name') }}", {"users": [{"name": "a"}, {"name": "b"}]})
add("sort", "{{ [3,1,2] | sort }} {{ ['b','A','c'] | sort }}")
add("sort reverse", "{{ [1,3,2] | sort(reverse=True) }}")
add("sort attr", "{{ users | sort(attribute='n') | map(attribute='n') | join('') }}", {"users": [{"n": "b"}, {"n": "a"}]})
add("sum min max", "{{ [1,2,3] | sum }} {{ [3,1,2] | min }} {{ [3,1,2] | max }} {{ [1.5,2] | sum }}")
add("sum start attr", "{{ items | sum(start=10, attribute='v') }}", {"items": [{"v": 1}, {"v": 2}]})
add("first last", "{{ [1,2,3] | first }} {{ [1,2,3] | last }} {{ [] | list }}")
add("length", "{{ 'abcd' | length }} {{ [1,2] | length }} {{ {'a': 1} | length }}")
add("abs round", "{{ -4.7 | abs }} {{ 42.55 | round(1) }} {{ 2.7 | round }} {{ 4.5 | round(method='ceil') }}")
add("int float", "{{ '42' | int }} {{ '42.7' | int }} {{ 'x' | int(-1) }} {{ '3.14' | float }} {{ 'x' | float(0.5) }}")
add("int base", "{{ 'ff' | int(0, base=16) }} {{ '0x1f' | int(0, base=16) }}")
add("list filter", "{{ 'abc' | list | join(',') }} {{ {'a': 1} | list | join(',') }}")
add("map attr", "{{ users | map(attribute='name') | join(',') }}", {"users": [{"name": "a"}, {"name": "b"}]})
add("map filter", "{{ [1,2,3] | map('string') | select('string') | join(',') }}")
add("select reject", "{{ [1,2,3,4] | select('odd') | join(',') }} {{ [1,2,3,4] | reject('odd') | join(',') }}")
add("selectattr", "{{ users | selectattr('on') | map(attribute='n') | join(',') }}",
    {"users": [{"n": "a", "on": True}, {"n": "b", "on": False}]})
add("rejectattr", "{{ users | rejectattr('on') | map(attribute='n') | join(',') }}",
    {"users": [{"n": "a", "on": True}, {"n": "b", "on": False}]})
add("selectattr test", "{{ users | selectattr('age', '>=', 30) | map(attribute='n') | join(',') }}",
    {"users": [{"n": "a", "age": 30}, {"n": "b", "age": 20}]})
add("groupby", "{% for g in items | groupby('k') %}{{ g.grouper }}:{{ g.list | map(attribute='v') | join('') }};{% endfor %}",
    {"items": [{"k": "a", "v": 1}, {"k": "b", "v": 2}, {"k": "a", "v": 3}]})
add("unique", "{{ [1,2,1,3,2] | unique | join(',') }}")
add("unique attr", "{{ users | unique(attribute='k') | map(attribute='k') | join(',') }}",
    {"users": [{"k": 1}, {"k": 1}, {"k": 2}]})
add("batch", "{% for row in [1,2,3,4,5] | batch(2, 0) %}[{{ row | join(',') }}]{% endfor %}")
add("slice", "{% for col in [1,2,3,4,5] | slice(2, '-') %}[{{ col | join(',') }}]{% endfor %}")
add("reverse", "{{ [1,2,3] | reverse | join(',') }} {{ 'abc' | reverse }}")
add("truncate", "{{ 'hello world' | truncate(8) }} {{ 'hello world' | truncate(8, true) }} {{ 'short' | truncate(8) }}")
add("wordcount", "{{ 'a b  c' | wordcount }}")
add("indent", "{{ 'a\\nb\\nc' | indent(2) }}")
add("indent first", "{{ 'a\\nb' | indent(2, true) }}")
add("striptags", "{{ '<p>Hello <b>World</b></p>' | striptags }}")
add("urlencode str", "{{ 'a b&c' | urlencode }}")
add("urlencode dict", "{{ {'a b': 'c&d'} | urlencode }}")
add("items", "{% for k, v in d | items %}{{ k }}={{ v }};{% endfor %}", {"d": {"a": 1, "b": 2}})
add("dictsort", "{% for k, v in d | dictsort %}{{ k }}{{ v }};{% endfor %}", {"d": {"b": 2, "a": 1}})
add("dictsort value", "{% for k, v in d | dictsort(by='value') %}{{ k }}{{ v }};{% endfor %}", {"d": {"a": 2, "b": 1}})
add("tojson", "{{ d | tojson }}", {"d": {"a": [1, 2], "b": "x\"y"}})
add("format", "{{ '%s=%d' | format('x', 5) }} {{ '%05d|%x|%r' | format(42, 255, 's') }}")
add("center", "{{ 'ab' | center(6) }}|")
add("wordwrap", "{{ 'the quick brown fox jumped' | wordwrap(10) }}")
add("filesizeformat", "{{ 1000 | filesizeformat }} {{ 1000 | filesizeformat(true) }} {{ 1 | filesizeformat }} {{ 1500000 | filesizeformat }}")
add("escape", "{{ '<b>' | escape }} {{ '&'.e }}")
add("attr", "{{ user | attr('name') }} {{ user | attr('missing') | default('d') }}", {"user": {"name": "x"}})
add("min max attr", "{{ users | min(attribute='age') }} {{ users | max(attribute='age') }}",
    {"users": [{"age": 3}, {"age": 1}, {"age": 2}]})

# --- tests ---------------------------------------------------------------
add("tests basic", "{{ 4 is even }} {{ 3 is odd }} {{ 9 is divisibleby 3 }} {{ x is defined }} {{ m is defined }} {{ x is undefined }}", {"x": 1})
add("type tests", "{{ 'a' is string }} {{ 1 is number }} {{ 1.5 is number }} {{ true is boolean }} {{ d is mapping }} {{ [1] is sequence }} {{ 'a' is iterable }}", {"d": {}})
add("none tests", "{{ none is none }} {{ 1 is none }} {{ x is defined and not x is none }}", {"x": 1})
add("cmp tests", "{{ 1 is eq 1 }} {{ 1 is ne 2 }} {{ 1 is lt 2 }} {{ 2 is le 2 }} {{ 3 is gt 1 }} {{ 3 is ge 3 }}")
add("is not", "{{ 1 is not odd }} {{ none is not defined }}")
add("in test", "{{ 1 is in [1,2] }} {{ 'a' is in 'abc' }}")
add("upper lower tests", "{{ 'AA' is upper }} {{ 'aa' is lower }} {{ 'AA' is lower }}")
add("escaped test", "{{ x is escaped }}", {"x": None})

# --- statements ----------------------------------------------------------
add("if elif else", "{% if x == 1 %}one{% elif x == 2 %}two{% else %}many{% endif %}", {"x": 2})
add("if bool", "{% if list %}has{% else %}empty{% endif %}", {"list": []})
add("for", "{% for i in [1,2,3] %}{{ i }}{% endfor %}")
add("for else", "{% for i in [] %}{{ i }}{% else %}none{% endfor %}")
add("loop vars", "{% for i in [1,2,3] %}{{ loop.index }}{{ loop.index0 }}{{ loop.revindex }}{{ loop.revindex0 }}{{ loop.first }}{{ loop.last }}{{ loop.length }};{% endfor %}")
add("loop prev next", "{% for i in [1,2,3] %}{{ loop.previtem | default('-') }}{{ loop.nextitem | default('-') }};{% endfor %}")
add("loop cycle", "{% for i in [1,2,3,4] %}{{ loop.cycle('a','b') }}{% endfor %}")
add("loop changed", "{% for i in [1,1,2] %}{{ loop.changed(i) }}{% endfor %}")
add("for unpack", "{% for k, v in items %}{{ k }}={{ v }};{% endfor %}", {"items": [[1, "a"], [2, "b"]]})
add("for dict", "{% for k in d %}{{ k }};{% endfor %}", {"d": {"a": 1, "b": 2}})
add("for filtered", "{% for i in [1,2,3,4] if i > 2 %}{{ i }}{% endfor %}")
add("nested for", "{% for a in [1,2] %}{% for b in ['x'] %}{{ a }}{{ b }}{% endfor %}{% endfor %}")
add("set", "{% set x = 5 %}{{ x * 2 }}")
add("set tuple", "{% set a, b = 1, 2 %}{{ a }}{{ b }}")
add("set dict", "{% set d = {'k': 'v'} %}{{ d.k }}")
add("set block", "{% set x %}ab{% endset %}{{ x | upper }}")
add("namespace", "{% set ns = namespace(count=0) %}{% for i in [1,2,3] %}{% set ns.count = ns.count + 1 %}{% endfor %}{{ ns.count }}")
add("with", "{% with a = 3, b = 4 %}{{ a + b }}{% endwith %}")
add("filter block", "{% filter upper %}abc{% endfilter %}")
add("filter block args", "{% filter join(', ') %}ab{% endfilter %}")
add("do", "{% do 1 %}ok")
add("macro", "{% macro greet(name, punct='!') %}hi {{ name }}{{ punct }}{% endmacro %}{{ greet('bob') }} {{ greet('ann', punct='?') }}")
add("macro varargs", "{% macro m(a, b=0) %}{{ a }}|{{ b }}|{{ varargs | join(',') }}|{{ kwargs['extra'] }}{% endmacro %}{{ m(1, 2, 3, 4, extra='x') }}")
add("macro name", "{% macro m() %}{{ name }}{% endmacro %}{{ m() }}")
add("call", "{% macro wrap() %}<{{ caller() }}>{% endmacro %}{% call wrap() %}body{% endcall %}")
add("call params", "{% macro row() %}[{{ caller('x') }}]{% endmacro %}{% call(v) row() %}<{{ v }}>{% endcall %}")
add("recursive loop", "{% for n in nodes recursive %}{{ n.v }}{{ loop(n.kids) }}{% endfor %}",
    {"nodes": [{"v": 1, "kids": [{"v": 2, "kids": []}, {"v": 3, "kids": []}]}]})
add("recursive depth", "{% for n in nodes recursive %}({{ n.v }}:{{ loop.depth }}{{ loop(n.kids) }}){% endfor %}",
    {"nodes": [{"v": 1, "kids": [{"v": 2, "kids": []}]}]})
add("range loop", "{% for i in range(3) %}{{ i }}{% endfor %}|{% for i in range(1, 4) %}{{ i }}{% endfor %}|{% for i in range(0, 6, 2) %}{{ i }}{% endfor %}")
add("range neg", "{% for i in range(3, 0, -1) %}{{ i }}{% endfor %}")
add("dict global", "{{ dict(a=1, b=2) | dictsort | join(',') }}")

# --- whitespace ----------------------------------------------------------
add("default whitespace", "a\n{% if true %}\nb\n{% endif %}\n")
add("keep trailing", "x\n", keep_trailing_newline=True)
add("trim blocks", "a\n{% if true %}\nb\n{% endif %}\nc", trim_blocks=True)
add("lstrip blocks", "  {% if true %}X{% endif %}\n", trim_blocks=True, lstrip_blocks=True)
add("markers var", "a  {{- 'X' -}}  b")
add("markers block", "a\n  {%- if true %}Y{% endif -%}\n  b")
add("markers one sided", "a {{- 'X' }} b|a {{ 'X' -}} b")

# --- raw ------------------------------------------------------------------
add("raw", "{% raw %}{{ x }}{% if y %}{% endraw %}")
add("raw markers", "a\n{%- raw -%}  X  {%- endraw -%}\nb")
add("raw partial", "{% raw %}{%{% endraw %}")

# --- inheritance / includes / imports -------------------------------------
add("extends", "{% extends 'base.html' %}", templates={
    "base.html": "<title>{% block title %}Default{% endblock %}</title>{% block body %}{% endblock %}"})
add("extends override", "{% extends 'base.html' %}{% block body %}X{% endblock %}", templates={
    "base.html": "<title>{% block title %}Default{% endblock %}</title>{% block body %}{% endblock %}"})
add("extends chain", "{% extends 'child.html' %}", templates={
    "base.html": "<title>{% block title %}Default{% endblock %}</title>{% block body %}{% endblock %}",
    "child.html": "{% extends 'base.html' %}{% block title %}{{ page }}{% endblock %}{% block body %}B{% endblock %}"})
add("include", "A {% include 'partial.html' %}", {"x": 7}, templates={"partial.html": "P={{ x }}"})
add("include missing", "{% include 'nope.html' ignore missing %}ok")
add("include fallback", "{% include ['missing.html', 'b.html'] %}", templates={"b.html": "B"})
include_ctx = True
add("include without context", "{% include 'p.html' without context %}", {"x": 7}, templates={"p.html": "{{ x | default('none') }}"})
add("import", "{% import 'module.html' as m %}{{ m.double(21) }} {{ m.answer }}", templates={
    "module.html": "{% macro double(v) %}{{ v * 2 }}{% endmacro %}{% set answer = 42 %}"})
add("from import", "{% from 'module.html' import double %}{{ double(5) }}", templates={
    "module.html": "{% macro double(v) %}{{ v * 2 }}{% endmacro %}"})

# --- autoescape -----------------------------------------------------------
add("autoescape basic", "{{ v }}", {"v": "<b>&"}, autoescape=True)
add("autoescape safe", "{{ v }}|{{ v | safe }}|{{ v | escape }}", {"v": "<b>"}, autoescape=True)
add("autoescape off", "{{ v }}", {"v": "<b>"})
add("autoescape block", "{% autoescape true %}{{ v }}{% endautoescape %}|{% autoescape false %}{{ v }}{% endautoescape %}", {"v": "<b>"})
add("escape no autoescape", "{{ v | escape }}", {"v": "<b>"})


# ================= edge-case expansion (round 2) =================

# --- numbers and float repr ---------------------------------------------
add("float repr", "{{ 1.0 }} {{ 1.50 }} {{ 0.1 + 0.2 }} {{ 1000000.0 }}")
add("float exponent", "{{ 1e20 }} {{ 1e-5 }} {{ 123456789012345678.0 }}")
add("big int", "{{ 2 ** 62 }}")
add("int div zero", "{{ 1 // 0 }}")
add("mod zero", "{{ 1 % 0 }}")
add("float div zero", "{{ 1 / 0 }}")
add("bool arith", "{{ true + true }} {{ true * 3 }}")
add("mixed eq", "{{ 1 == 1.0 }} {{ true == 1 }} {{ 0 == false }} {{ '1' == 1 }}")
add("none compare error", "{{ 1 < none }}")
add("mixed sort error", "{{ [3, 'a'] | min }}")
add("float mod", "{{ 10 % 3.5 }} {{ -10 % 3.5 }}")
add("neg pow", "{{ 2 ** -1 }} {{ 2 ** -2 }}")
add("int overflow pow error", "{{ 10 ** 30 }}")

# --- containers and reprs ------------------------------------------------
add("nested repr", "{{ [1, [2, 'x'], {'k': [3]}] }}")
add("dict nested repr", "{{ {'a': {'b': [1, 'z']}, 'c': none} }}")
add("tuple in list", "{{ d | dictsort }}", {"d": {"b": 1, "a": 2}})
add("empty containers", "{{ [] }} {{ {} }} {{ '' }}")
add("unicode", "{{ 'héllo wörld' | upper }} {{ 'héllo' | length }} {{ 'ä' }}")
add("string index", "{{ 'abc'[0] }} {{ 'abc'[-1] }} {{ 'abc'[5] | default('oob') }}")
add("index error", "{{ [1,2][5] }}")
add("dict int key", "{{ {1: 'a'}[1] }}")
add("dict bool key", "{{ {true: 'a'}[true] }}")
add("dict true key repr", "{{ {true: 1} }}")
add("slice zero step", "{{ 'abc'[::0] }}")
add("slice out of range", "{{ 'abc'[1:100] }} {{ 'abc'[-100:2] }} {{ 'abc'[3:1] }}")
add("slice negative step", "{{ [1,2,3,4,5][::-2] }} {{ [1,2,3,4,5][3:0:-1] }}")

# --- undefined semantics --------------------------------------------------
add("undefined attr of undefined", "{{ missing.foo.bar | default('d') }}")
add("undefined filter chain", "{{ missing | upper | trim }}|")
add("undefined concat", "{{ 'a' ~ missing ~ 'b' }}")
add("undefined eq", "{{ missing == other }} {{ missing == 1 }} {{ missing == none }}")
add("undefined in list", "{{ missing in [1,2] }}")
add("undefined iterate", "{% for x in missing %}x{% endfor %}")
add("undefined arithmetic", "{{ missing + 1 }}")
add("undefined length", "{{ missing | length }}")
add("undefined is none", "{{ missing is none }} {{ none is none }}")
add("undefined string test", "{{ missing is string }} {{ missing is sequence }}")
add("undefined else branch", "{{ 'a' if missing }}|")

# --- filters: edge inputs --------------------------------------------------
add("upper undefined", "{{ missing | upper }}|")
add("join empty", "{{ [] | join(',') }}|{{ [1] | join(',') }}")
add("join mixed types", "{{ [1, 'a', true] | join('-') }}")
add("join none", "{{ [none] | join(',') }}")
add("sort strings case", "{{ ['b', 'A', 'C'] | sort | join(',') }}")
add("sort empty", "{{ [] | sort }}")
add("sort dict keys", "{{ {'b': 1, 'a': 2} | sort }}")
add("min max strings", "{{ ['b', 'a'] | min }} {{ ['b', 'a'] | max }}")
add("min max empty", "{{ [] | min }} {{ [] | max }}")
add("sum empty", "{{ [] | sum }}|{{ [] | sum(start=5) }}")
add("sum strings error", "{{ ['a'] | sum }}")
add("first last empty", "{{ [] | first | default('e1') }} {{ [] | last | default('e2') }}")
add("random empty error", "{{ [] | random }}")
add("round negative", "{{ 1234 | round(-2) }} {{ 1234.0 | round(-2) }}")
add("round precision 0", "{{ 2.5 | round }} {{ 3.5 | round }}")
add("abs bool", "{{ true | abs }}")
add("int float val", "{{ 3.99 | int }} {{ -3.99 | int }} {{ '  42  ' | int }}")
add("int none", "{{ none | int }} {{ none | int(5) }}")
add("float bool", "{{ true | float }}")
add("truncate edge", "{{ '' | truncate(5) }}|{{ 'exactly10!' | truncate(10) }}|{{ 'hello' | truncate(3) }}")
add("truncate killwords", "{{ 'hello world' | truncate(9, true) }}")
add("center odd", "{{ 'abc' | center(4) }}|{{ 'abcdef' | center(3) }}|")
add("indent zero", "{{ 'a\\nb' | indent(0) }}")
add("wordwrap long word", "{{ 'aaaaaaaaaaaaaaaaaa bb' | wordwrap(10) }}")
add("wordwrap exact", "{{ 'aaa bbb' | wordwrap(7) }}")
add("replace empty old", "{{ 'abc'.replace('', '-') }}")
add("replace regex chars", "{{ 'a.b'.replace('.', '-') }}")
add("split no sep found", "{{ 'abc'.split(',') | join('|') }}")
add("split empty", "{{ 'a  b'.split() | join(',') }}")
add("title punct", "{{ \"it's a test-case\" | title }}")
add("capitalize empty", "{{ '' | capitalize }}|")
add("trim chars", "{{ 'xxaxx' | trim('x') }} {{ 'xxaxx' | trim }}")
add("striptags entities", "{{ '<p>a &amp; b</p>' | striptags }}")
add("urlencode slash", "{{ 'a/b' | urlencode }}")
add("urlencode unicode", "{{ 'héllo' | urlencode }}")
add("tojson unicode", "{{ 'hé' | tojson }}")
add("tojson none bool", "{{ [none, true, false] | tojson }}")
add("tojson nested", "{{ {'a': {'b': [1, [2]]}} | tojson }}")
add("tojson indent", "{{ [1, [2]] | tojson(indent=2) }}")
add("format pct", "{{ '100%%' | format }} {{ '%s' | format(none) }}")
add("format f", "{{ '%.2f' | format(3.14159) }} {{ '%5.1f' | format(2.25) }}")
add("format width str", "{{ '%10s|%-10s|' | format('a', 'b') }}")
add("format missing arg", "{{ '%s %s' | format('a') }}")
add("filesizeformat neg", "{{ -5 | filesizeformat }}")
add("filesizeformat big", "{{ 1073741824 | filesizeformat(true) }} {{ 1e15 | filesizeformat }}")
add("unique empty", "{{ [] | unique | join(',') }}|")
add("batch no fill", "{% for row in [1,2,3,4,5] | batch(2) %}[{{ row | join(',') }}]{% endfor %}")
add("batch bigger than list", "{% for row in [1] | batch(3, 0) %}[{{ row | join(',') }}]{% endfor %}")
add("slice equal", "{% for col in [1,2,3,4] | slice(2) %}[{{ col | join(',') }}]{% endfor %}")
add("slice single", "{% for col in [1] | slice(3, '-') %}[{{ col | join(',') }}]{% endfor %}")
add("groupby missing attr", "{% for g in items | groupby('zz') %}{{ g.grouper }};{% endfor %}",
    {"items": [{"v": 1}]})
add("selectattr missing", "{{ users | selectattr('zz') | length }}", {"users": [{"n": "a"}]})
add("map default", "{{ users | map(attribute='age', default=0) | join(',') }}",
    {"users": [{"age": 3}, {"name": "x"}]})
add("first filter undefined", "{{ missing | first | default('d') }}")
add("dictsort case", "{{ {'B': 1, 'a': 2} | dictsort | map('first') | join(',') }}", {"unused": 0})
add("dictsort case sensitive", "{{ {'B': 1, 'a': 2} | dictsort(case_sensitive=true) | map(attribute='0') | join(',') }}", {"unused": 0})

# --- tests: edge inputs -----------------------------------------------------
add("divisibleby zero", "{{ 4 is divisibleby 0 }}")
add("number bool", "{{ true is number }} {{ false is number }}")
add("sequence string", "{{ 'abc' is sequence }} {{ 1 is sequence }}")
add("iterable dict", "{{ {} is iterable }} {{ 1 is iterable }}")
add("integer float tests", "{{ 1 is integer }} {{ 1.0 is integer }} {{ 1.0 is float }}")
add("eq type cross", "{{ '1' is eq 1 }} {{ 1 is eq true }}")
add("sameas none", "{{ x is sameas none }}", {"x": None})
add("in dict", "{{ 'a' is in {'a': 1} }} {{ 'b' is in {'a': 1} }}")
add("in undefined", "{{ 1 is in missing }}")
add("escaped test none", "{{ none is escaped }}")
add("filter test", "{{ 'upper' is filter }} {{ 'nope' is filter }} {{ 'even' is test }}")
add("lower upper nonstring", "{{ 1 is lower }} {{ [] is upper }}")

# --- statements: scoping and edge -------------------------------------------
add("set scope in for", "{% set x = 'outer' %}{% for i in [1] %}{% set x = 'inner' %}{% endfor %}{{ x }}")
add("set scope in if", "{% set x = 'outer' %}{% if true %}{% set x = 'inner' %}{% endif %}{{ x }}")
add("for var leaks not", "{% for i in [1] %}{% endfor %}{{ i is defined }}")
add("nested loop shadow", "{% for i in [1,2] %}{% for j in [3] %}{{ loop.index }}{% endfor %}{{ loop.index }}{% endfor %}")
add("loop after for", "{% for i in [1] %}{% endfor %}{{ loop is defined }}")
add("for string", "{% for c in 'abc' %}{{ c }}{% endfor %}")
add("for dict values", "{% for v in d.values() %}{{ v }}{% endfor %}", {"d": {"a": 1, "b": 2}})
add("for tuple unpack nested", "{% for a, b in [[1, 2], [3, 4]] %}{{ a }}{{ b }};{% endfor %}")
add("for unpack error", "{% for a, b in [[1, 2, 3]] %}x{% endfor %}")
add("for filtered all", "{% for i in [1,2] if i > 5 %}{{ i }}{% else %}none{% endfor %}")
add("for recursive cycle", "{% for n in nodes recursive %}{{ n.v }}{{ loop.cycle('x','y') }}{{ loop(n.kids) }}{% endfor %}",
    {"nodes": [{"v": 1, "kids": [{"v": 2, "kids": []}, {"v": 3, "kids": []}]}]})
add("if complex", "{% if a > 1 and b < 2 or c %}yes{% else %}no{% endif %}", {"a": 1, "b": 2, "c": True})
add("if in for", "{% for i in [1,2,3] %}{% if loop.first %}F{% endif %}{{ i }}{% endfor %}")
add("macro nested call", "{% macro outer() %}o({{ inner() }}){% endmacro %}{% macro inner() %}i{% endmacro %}{{ outer() }}")
add("macro in loop", "{% macro m(x) %}[{{ x }}]{% endmacro %}{% for i in [1,2] %}{{ m(i) }}{% endfor %}")
add("macro override", "{% macro m() %}a{% endmacro %}{% macro m() %}b{% endmacro %}{{ m() }}")
add("macro set not leak", "{% macro m() %}{% set zz = 1 %}{% endmacro %}{{ m() }}{{ zz is defined }}")
add("macro default expr", "{% set base = 10 %}{% macro m(v=base) %}{{ v }}{% endmacro %}{{ m() }}", {"base": 10})
add("call with args macro", "{% macro listit(items) %}{% for i in items %}[{{ caller(i) }}]{% endfor %}{% endmacro %}{% call(v) listit([1,2]) %}{{ v * 2 }}{% endcall %}")
add("set attr dict", "{% set d = {} %}{% set d.k = 'v' %}{{ d.k }}")
d1 = {"d": {"counter": 0}}
add("set item list", "{% set l = [1,2] %}{% set l[0] = 9 %}{{ l | join(',') }}")
add("with nesting", "{% with a = 1 %}{% with b = 2 %}{{ a + b }}{% endwith %}{% endwith %}")
add("with shadow", "{% set a = 1 %}{% with a = 2 %}{{ a }}{% endwith %}{{ a }}")

# --- whitespace control edge -------------------------------------------------
add("comment markers", "a {#- comment -#} b")
add("comment no markers", "a {# comment #} b")
add("plus marker override trim", "a\n{%+ if true %}\nb\n{% endif %}\nc", trim_blocks=True)
add("plus marker override lstrip", "  {%+ if true %}X{% endif %}", trim_blocks=True, lstrip_blocks=True)
add("minus on for else", "{% for i in [1,2] -%}\n{{ i }}\n{% endfor -%}\nend", trim_blocks=True)
add("nested marker mid", "{% for i in [1,2] %}\n  {{- i -}}\n{% endfor %}")
add("keep newline empty template", "\n", keep_trailing_newline=True)
add("crlf trailing", "x\r\n", keep_trailing_newline=True)

# --- inheritance edge --------------------------------------------------------
add("super", "{% extends 'base.html' %}{% block body %}[{{ super() }}]{% endblock %}", templates={
    "base.html": "{% block body %}base{% endblock %}"})
add("super chain", "{% extends 'mid.html' %}{% block body %}[{{ super() }}]{% endblock %}", templates={
    "base.html": "{% block body %}base{% endblock %}",
    "mid.html": "{% extends 'base.html' %}{% block body %}mid({{ super() }}){% endblock %}"})
add("nested blocks", "{% extends 'base.html' %}{% block outer %}O({% block inner %}I{% endblock %}){% endblock %}", templates={
    "base.html": "{% block outer %}{% endblock %}"})
add("block in for", "{% for i in [1,2] %}{% block b %}x{{ i }}{% endblock %}{% endfor %}", templates={})
add("include context var", "{% include 'p.html' %}", {"x": 5}, templates={"p.html": "{{ x }}"})
add("include with context explicit", "{% include 'p.html' with context %}", {"x": 5}, templates={"p.html": "{{ x }}"})
add("import as", "{% from 'm.html' import double as dbl %}{{ dbl(4) }}", templates={
    "m.html": "{% macro double(v) %}{{ v * 2 }}{% endmacro %}"})
add("import multiple", "{% from 'm.html' import a, b %}{{ a }}{{ b }}", templates={
    "m.html": "{% set a = 'A' %}{% set b = 'B' %}"})
add("import without context", "{% import 'm.html' as m without context %}{{ m.v }}", {"x": 9}, templates={
    "m.html": "{% set v = x %}"})
add("extends with filters", "{% extends 'base.html' %}{% block body %}{{ 'ab' | upper }}{% endblock %}", templates={
    "base.html": "{% block body %}{% endblock %}"})

# --- autoescape edge ----------------------------------------------------------
add("autoescape macro", "{% macro m(v) %}{{ v }}{% endmacro %}{{ m('<x>') }}", autoescape=True)
add("autoescape join", "{{ ['<a>', '<b>'] | join(',') }}", autoescape=True)
add("autoescape attr", "{{ obj.v }}", {"obj": {"v": "<i>"}}, autoescape=True)
add("autoescape int", "{{ 5 }} {{ none }}", autoescape=True)
add("autoescape if expr", "{{ '<z>' if true }}", autoescape=True)
add("autoescape safe twice", "{{ v | safe | safe }}", {"v": "<b>"}, autoescape=True)
add("autoescape default", "{{ missing | default('<d>') }}", autoescape=True)
add("forceescape", "{{ v | safe | forceescape }}", {"v": "<b>"}, autoescape=True)
add("escape non string", "{{ 5 | escape }}|{{ none | escape }}", autoescape=True)

# --- misc / tricky -------------------------------------------------------------
add("expr multiline", "{{\n  1 +\n  2\n}}")
add("comment inside expr", "{{ 1 + # c\n 2 }}")
add("double pipe", "{{ 'a' | upper | lower }}")
add("filter on call", "{{ m() | upper }}", templates={}, data={})
add("getattr chain call", "{{ users | map(attribute='n') | list | first }}", {"users": [{"n": "x"}]})
add("ternary in arg", "{{ m(x if true else 'y') }}", data={})
add("deep nesting", "{% if true %}{% if true %}{% if true %}deep{% endif %}{% endif %}{% endif %}")
add("empty template", "")
add("only comment", "{# nothing #}")
add("text around blocks", "a{% if true %}b{% endif %}c")
add("concat in attr", "{{ obj['a' ~ 'b'] }}", {"obj": {"ab": "found"}})
add("getitem with var", "{{ obj[k] }}", {"obj": {"key": "v"}, "k": "key"})
add("negative index var", "{{ l[i] }}", {"l": [1, 2, 3], "i": -1})
add("arith in subscript", "{{ l[1 + 1] }}", {"l": [1, 2, 3]})
add("chained getitem", "{{ d['a']['b'] }}", {"d": {"a": {"b": "c"}}})
add("not not", "{{ not not true }}")
add("precedence mix", "{{ 1 + 2 * 3 - 4 / 2 }}")
add("paren grouping", "{{ (1 + 2) * 3 }}")
add("compare chain with in", "{{ 1 in [1] == true }}")
add("if attr chain", "{% if user.name == 'bob' %}hi bob{% endif %}", {"user": {"name": "bob"}})

# ================= round 3: exotic and edge cases =================
# --- lexer / parser oddities ---------------------------------------------
add("single vs double quotes", "{{ 'a\"b' }} {{ \"a'b\" }}")
add("string with bracket", "{{ 'a[1]}' }} {{ d['k}}'] }}", {"d": {"k}}": "brace"}})
add("multiline for header", "{% for i\n    in [1,2]\n %}{{ i }}{% endfor %}")
add("comment between tags", "a{# c #}{% if true %}b{% endif %}")
add("nested strings in expr", "{{ 'a' == \"a\" }} {{ \"it's\" | length }}")
add("trailing commas call", "{{ m(1,) }}{% macro m(x) %}{{ x }}{% endmacro %}")
add("kwargs trailing comma", "{{ dict(a=1, b=2,) | dictsort | join(',') }}")
add("deep parens", "{{ ((((1)))) }}")
add("keyword-ish names", "{{ none is defined }} {{ true is defined }} {{ false is defined }}")
add("identifier with digits", "{{ v1 + v2 }}", {"v1": 3, "v2": 4})
add("unicode identifier", "{{ värde }}", {"värde": "x"})
add("filter with no arg newline", "{{ 'a' |\nupper }}")
add("if expr inside subscript", "{{ d['a' if true else 'b'] }}", {"d": {"a": 1, "b": 2}})
add("set with complex expr", "{% set x = [1,2] | map('string') | join('+') %}{{ x }}")
add("chained ternary", "{{ 'a' if 0 else 'b' if 1 else 'c' }}")
add("comparison chain parens", "{{ (1 < 2) == true }}")
add("not with is", "{{ not 1 is odd }} {{ 1 is not odd }}")
add("in chain", "{{ 1 in [1] and 'a' in 'abc' }}")
add("float underscoreless big", "{{ 123456.789012 }}")
add("negative zero", "{{ -0 }} {{ -0.0 }} {{ 0.0 }}")
add("int vs float repr", "{{ 2.0 + 2.0 }} {{ 4 // 2 }} {{ 4 / 2 }}")

# --- operator and math edges ----------------------------------------------
add("pow right assoc", "{{ 2 ** 3 ** 2 }}")
add("pow paren", "{{ (2 ** 3) ** 2 }}")
add("mod float negative", "{{ -7.5 % 2 }} {{ 7.5 % -2 }}")
add("floor div float", "{{ -7.5 // 2 }} {{ 7.5 // -2 }}")
add("bool pow", "{{ true ** 2 }} {{ false ** 0 }}")
add("string compare", "{{ 'a' < 'b' }} {{ 'B' < 'a' }} {{ 'ab' < 'b' }}")
add("list compare", "{{ [1,2] < [1,3] }} {{ [1] < [1,2] }}")
add("eq lists", "{{ [1,2] == [1,2] }} {{ [1] == [1.0] }}")
add("eq dicts", "{{ {'a': 1} == {'a': 1.0} }} {{ {} == {} }}")
add("concat numbers", "{{ 1 ~ 2.5 ~ true }}")
add("arith precedence unary", "{{ -2 ** 2 }} {{ (-2) ** 2 }}")
add("not precedence", "{{ not 1 == 1 }} {{ not true and false }}")
add("ternary precedence", "{{ 1 + 1 if true else 0 }} {{ (1 + 1) if true else 0 }}")
add("large int literal", "{{ 9007199254740993 }}")
add("float precision add", "{{ 0.1 + 0.7 }}")
add("int float key equality", "{{ {1: 'a'}[1.0] }} {{ {1.0: 'a'}[1] }}")

# --- string methods (python-style) ------------------------------------------
add("str startswith endswith", "{{ 'abc'.startswith('ab') }} {{ 'abc'.endswith('bc') }}")
add("str find", "{{ 'abcabc'.find('b') }} {{ 'abc'.find('z') }}")
add("str strip variants", "{{ 'xxabcxx'.strip('x') }} {{ 'xxabcxx'.lstrip('x') }} {{ 'xxabcxx'.rstrip('x') }}")
add("str zfill", "{{ '42'.zfill(5) }} {{ '-42'.zfill(5) }}")
add("str ljust rjust", "{{ 'a'.ljust(3, '-') }} {{ 'a'.rjust(3, '-') }}")
add("str splitlines", "{{ 'a\\nb\\rc'.splitlines() | join('|') }}")
add("str rsplit", "{{ 'a,b,c'.rsplit(',', 1) | join('|') }}")
add("str partition", "{{ 'a=b=c'.partition('=') | join('|') }}")
add("str count", "{{ 'banana'.count('an') }}")
add("str isdigit isalpha", "{{ '12'.isdigit() }} {{ 'ab'.isdigit() }} {{ 'ab'.isalpha() }}")
add("str title method", "{{ 'hello world'.title() }}")
add("str casefold swapcase", "{{ 'AbC'.swapcase() }}")
add("str join method", "{{ '-'.join(['a','b']) }}")
add("str format method", "{{ '{} and {}'.format(1, 'x') }} {{ '{0}{1}'.format('a', 'b') }}")
add("str index method", "{{ 'abc'.index('b') }}")
add("str expandtabs", "{{ 'a\\tb'.expandtabs(4) }}")
add("str removeprefix", "{{ 'test_ab'.removeprefix('test_') }} {{ 'test_ab'.removesuffix('_ab') }}")

# --- filters: exotic usage ---------------------------------------------------
add("map two args", "{{ [[1,2],[3,4]] | map('sum') | join(',') }}")
add("map with kwargs", "{{ ['a','b'] | map('center', 5, fillchar='-') | join('|') }}")
add("select with args", "{{ ['abc','ab'] | select('>=', 'ab') | join(',') }}")
add("reject with args", "{{ [5,1,8] | reject('>=', 5) | join(',') }}")
add("select chained", "{{ [1,2,3,4,5,6] | select('even') | select('>', 2) | join(',') }}")
add("map attr chain", "{{ users | map(attribute='name') | map('upper') | join(',') }}",
    {"users": [{"name": "a"}, {"name": "b"}]})
add("groupby multiple loops", "{% for g in items | groupby('k') %}{% for v in g.list %}{{ v.v }}{% endfor %}|{% endfor %}",
    {"items": [{"k": "a", "v": 1}, {"k": "a", "v": 2}, {"k": "b", "v": 3}]})
add("groupby sort reversed", "{% for g in items | groupby('k') %}{{ g.grouper }};{% endfor %}",
    {"items": [{"k": "b", "v": 1}, {"k": "a", "v": 2}]})
add("unique casefold", "{{ ['a','A','b'] | unique | join(',') }}")
add("min casefold attr", "{{ users | min(attribute='n', case_sensitive=False) }}",
    {"users": [{"n": "B"}, {"n": "a"}]})
add("sort numeric strings", "{{ ['10', '9', '2'] | sort | join(',') }}")
add("sort mixed attr", "{{ users | sort(attribute='v') | map(attribute='v') | join(',') }}",
    {"users": [{"v": 2}, {"v": 1.5}]})
add("sum generator", "{{ range(5) | sum }}|{{ 'abc' | join('') }}")
add("length of generator", "{{ range(3) | length }}")
add("first of string", "{{ 'abc' | first }} {{ 'abc' | last }} {{ 'abc' | list | length }}")
add("batch attr", "{% for row in users | batch(2) %}[{{ row | map(attribute='n') | join(',') }}]{% endfor %}",
    {"users": [{"n": "a"}, {"n": "b"}, {"n": "c"}]})
add("tojson bool keys", "{{ d | tojson }}", {"d": {"true": 1, "none": 2}})
add("tojson special chars", "{{ '<&>' | tojson }}")
add("format g", "{{ '%g' | format(0.0001) }} {{ '%e' | format(100.0) }}")
add("format star width", "{{ '%*s' | format(5, 'a') }}")
add("format none width", "{{ '%s' | format([1, 'a']) }}")
add("urlencode none val", "{{ {'a': none} | urlencode }}")
add("urlencode tuple", "{{ ('a b',) | urlencode }}")
add("indent blank lines", "{{ 'a\\n\\nb' | indent(2) }}|")
add("wordwrap tab", "{{ 'a\\tb' | wordwrap(4) }}|")
add("wordwrap none breaks", "{{ 'a b c' | wordwrap(100) }}|")
add("wordwrap wrapstring", "{{ 'a b' | wordwrap(3, wrapstring=';') }}|")
add("truncate leeway", "{{ 'abcdefghijkl' | truncate(8, true, '...', 3) }}")
add("filesizeformat bytes word", "{{ 2 | filesizeformat }} {{ 1023 | filesizeformat(true) }}")
add("attr on list", "{{ l | attr('length') | default('nope') }}", {"l": [1, 2]})
add("striptags script", "{{ '<script>x</script>after' | striptags }}")
add("striptags unclosed", "{{ '<b>x' | striptags }}")
add("escape quotes", "{{ \"'\\\"\" | escape }}", autoescape=False)
add("title unicode", "{{ 'école world' | title }}")
add("upper unicode sharp s", "{{ 'straße' | upper }} {{ 'STRASSE' | lower }}")
add("capitalize unicode", "{{ 'école' | capitalize }}")
add("dictsort by value mixed", "{% for k, v in d | dictsort(by='value', reverse=true) %}{{ k }}{{ v }};{% endfor %}",
    {"d": {"a": 1, "b": 2}})
add("dictsort no items", "{{ {} | dictsort }}")

# --- undefined and error paths ----------------------------------------------
add("undefined add string", "{{ 'a' + missing }}")
add("undefined subscript", "{{ missing['k'] | default('d') }}")
add("undefined call", "{{ missing() }}")
add("undefined iter test", "{{ missing is iterable }} {{ missing is number }}")
add("undefined round", "{{ missing | round | default('d') }}")
add("undefined sort", "{{ missing | sort | default('d') }}")
add("undefined compare lt", "{{ missing < 1 }}")
add("undefined bool in and", "{{ missing and 'x' }}|{{ missing or 'x' }}")
add("undefined neg", "{{ -missing }}")
add("undefined attribute bool", "{{ obj.missing is defined }}", {"obj": {}})
add("loop on undefined attr", "{% for x in obj.missing %}x{% endfor %}", {"obj": {}})
add("divide string", "{{ 'a' / 2 }}")
add("mod string", "{{ 'a' % 2 }}")
add("range error neg step", "{% for i in range(3, 1) %}{{ i }}{% endfor %}|")
add("range zero step", "{% for i in range(1, 3, 0) %}{{ i }}{% endfor %}")
add("range float arg", "{% for i in range(2.5) %}{{ i }}{% endfor %}")

# --- loops: exotic ------------------------------------------------------------
add("loop length outer", "{% for i in [1,2] %}{% set n = loop.length %}{% endfor %}{{ n }}")
add("loop changed objects", "{% for i in [[1],[1],[2]] %}{{ loop.changed(i) }}{% endfor %}")
add("loop depth after recursion", "{% for n in nodes recursive %}{{ loop.depth }}{% if n.kids %}{{ loop(n.kids) }}{% endif %}{% endfor %}",
    {"nodes": [{"v": 1, "kids": [{"v": 2, "kids": []}]}]})
add("recursive loop length", "{% for n in nodes recursive %}{{ loop.length }}{{ loop(n.kids) }}{% endfor %}",
    {"nodes": [{"v": 1, "kids": [{"v": 2, "kids": []}]}]})
add("for over string chars", "{% for c in 'ab' %}[{{ c }}]{% endfor %}")
add("for over generator", "{% for i in range(3) %}{{ i }}{% endfor %}")
add("for over dictsort", "{% for k, v in d | dictsort %}{{ k }}{{ v }}{% endfor %}", {"d": {"b": 1, "a": 2}})
add("for filtered loop vars", "{% for i in [1,2,3] if i != 2 %}{{ loop.index }}:{{ i }};{% endfor %}")
add("for else after filtered", "{% for i in [1] if i > 9 %}{{ i }}{% else %}E{% endfor %}")
add("nested unpack", "{% for (a, b), c in [[(1, 2), 3]] %}{{ a }}{{ b }}{{ c }}{% endfor %}")
add("loop var inside macro", "{% for i in [1] %}{% macro m() %}{{ i }}{% endmacro %}{{ m() }}{% endfor %}")
add("set inside loop iteration", "{% for i in [1,2] %}{% set x = i * 10 %}{{ x }}{% endfor %}")
add("namespace in recursion", "{% set ns = namespace(d=0) %}{% for n in nodes recursive %}{% set ns.d = [ns.d, loop.depth] | max %}{{ loop(n.kids) }}{% endfor %}{{ ns.d }}",
    {"nodes": [{"v": 1, "kids": [{"v": 2, "kids": []}]}]})
add("break-like via filter", "{% for i in [1,2,3] if i < 3 %}{{ i }}{% endfor %}")
add("for else with loop var", "{% for i in [] %}{{ loop.index }}{% else %}{{ loop is defined }}{% endfor %}")

# --- macros / call / namespace exotic ------------------------------------------
add("macro kwargs access", "{% macro m(a) %}{{ kwargs['b'] | default('nb') }}{% endmacro %}{{ m(1) }} {{ m(1, b=2) }}")
add("macro varargs empty", "{% macro m() %}{{ varargs | length }}{% endmacro %}{{ m() }}")
add("macro caller twice", "{% macro m() %}{{ caller() }}{{ caller() }}{% endmacro %}{% call m() %}x{% endcall %}")
add("macro calling macro", "{% macro a() %}A{% endmacro %}{% macro b() %}{{ a() }}B{% endmacro %}{{ b() }}")
add("macro recursion", "{% macro fib(n) %}{% if n < 2 %}{{ n }}{% else %}{{ fib(n - 1) }}{{ fib(n - 2) }}{% endif %}{% endmacro %}{{ fib(5) }}")
add("macro returns markup", "{% macro m() %}<b>{% endmacro %}{{ m() | length }}")
add("call without macro error", "{% call m() %}x{% endcall %}")
add("macro default none", "{% macro m(v=none) %}{{ v is none }}{% endmacro %}{{ m() }}")
add("macro shadow builtin", "{% macro range(x) %}{{ x }}!{% endmacro %}{{ range(3) }}|{{ range(2) }}")
add("namespace attribute missing", "{% set ns = namespace() %}{{ ns.x | default('d') }}")
add("namespace bool", "{% set ns = namespace(f=false) %}{% if true %}{% set ns.f = true %}{% endif %}{{ ns.f }}")
add("set block with filter", "{% set x | upper %}ab{% endset %}{{ x }}")

# --- whitespace exotic -----------------------------------------------------------
add("block marker both sides", "{%- set x = 1 -%}   {{ x }}")
add("var marker lstrip only", "a  {{- 'b' }}")
add("trim blocks var line", "{{ 1 }}\n{{ 2 }}", trim_blocks=True)
add("trim blocks comment", "a\n{# c #}\nb", trim_blocks=True)
add("nested if markers", "{% if true %}\n{%- if true %}X{% endif %}\n{% endif %}")
add("marker on endset", "{% set x -%}\n  v\n{%- endset %}[{{ x }}]")
add("marker on macro body", "{% macro m() -%}\n  X\n{%- endmacro %}[{{ m() }}]")
add("raw with markers inline", "{% raw -%} X {%- endraw %}")
add("multiline var expr markers", "a\n  {{-\n 1 -}}\n  b")
add("trailing spaces preserved", "a  \nb")

# --- autoescape / Markup exotic ---------------------------------------------------
add("autoescape nested list repr", "{{ ['<a>'] }}", autoescape=True)
add("autoescape dict repr", "{{ {'k': '<v>'} }}", autoescape=True)
add("autoescape join markup", "{{ ['<a>'] | join }}", autoescape=True)
add("autoescape safe in concat", "{{ '<a>' | safe ~ '<b>' }}", autoescape=True)
add("autoescape macro result filter", "{% macro m() %}<x>{% endmacro %}{{ m() | upper }}", autoescape=True)
add("autoescape uppercase filter", "{{ '<x>' | upper }}", autoescape=True)
add("escape Markup again", "{{ '<x>' | safe | escape }}", autoescape=True)
add("autoescape trim", "{{ ' <x> ' | trim }}", autoescape=True)
add("autoescape default markup", "{{ missing | default('<d>') | safe }}", autoescape=True)
add("autoescape first filter", "{{ ['<a>'] | first }}", autoescape=True)
add("autoescape ternary both", "{{ ('<a>' if true else '<b>') }}", autoescape=True)

# --- inheritance / import exotic ---------------------------------------------------
add("block scope var", "{% extends 'base.html' %}{% set x = 7 %}{% block b %}{{ x }}{% endblock %}", templates={
    "base.html": "{% block b %}{% endblock %}"})
add("include loop context", "{% for i in [1,2] %}{% include 'p.html' %}{% endfor %}", templates={
    "p.html": "{{ loop.index }}"})
add("import macro uses context var", "{% import 'm.html' as m %}{{ m.g() }}", {"greeting": "yo"}, templates={
    "m.html": "{% macro g() %}{{ greeting | default('none') }}{% endmacro %}"})
add("from import context needed", "{% from 'm.html' import g %}{{ g() }}", {"greeting": "hi"}, templates={
    "m.html": "{% macro g() %}{{ greeting | default('none') }}{% endmacro %}"})
add("extends nested block override inner", "{% extends 'base.html' %}{% block inner %}X{% endblock %}", templates={
    "base.html": "{% block outer %}O({% block inner %}D{% endblock %}){% endblock %}"})
add("super twice", "{% extends 'base.html' %}{% block b %}{{ super() }}|{{ super() }}{% endblock %}", templates={
    "base.html": "{% block b %}B{% endblock %}"})
add("include self", "{% include 'self.html' %}{% set stop = true %}", templates={
    "self.html": "s"})
add("import alias usage", "{% import 'm.html' as m with context %}{{ m.v }}", {"x": 3}, templates={
    "m.html": "{% set v = x * 2 %}"})
add("block required", "{% extends 'base.html' %}", templates={
    "base.html": "{% block required b %}D{% endblock %}"})
add("include list all missing", "{% include ['a.html', 'b.html'] ignore missing %}ok")
add("macro in included template", "{% include 'm.html' %}{{ greet('x') }}", templates={
    "m.html": "{% macro greet(n) %}hi {{ n }}{% endmacro %}"})

# --- global functions ---------------------------------------------------------------
add("range step float error", "{% for i in range(0, 3, 0.5) %}{{ i }}{% endfor %}")
add("range single arg zero", "{% for i in range(0) %}{{ i }}{% endfor %}|{{ range(0) | length }}")
add("dict global empty", "{{ dict() }}|{{ dict(a=1) }}")
add("cycler next reset", "{% set c = cycler('a', 'b', 'c') %}{{ c.next() }}{{ c.next() }}{{ c.next() }}{{ c.next() }}|{{ c.current }}")
add("cycler reset", "{% set c = cycler('x', 'y') %}{{ c.next() }}{{ c.reset() }}{{ c.next() }}")
add("joiner", "{% set j = joiner(', ') %}{% for i in [1,2,3] %}{{ j() }}{{ i }}{% endfor %}")
add("namespace deep", "{% set ns = namespace(x=namespace(y=1)) %}{% set ns.x.y = 2 %}{{ ns.x.y }}")

# --- misc structural ------------------------------------------------------------------
add("statement in ternary output", "{{ 'x' if true else ('y' if false else 'z') }}")
add("set to tuple", "{% set t = (1, 'a') %}{{ t }} {{ t[0] }}")
add("empty tuple repr", "{% set t = () %}{{ t }}")
add("single tuple repr", "{% set t = (1,) %}{{ t }}")
add("tuple iteration", "{% for x in (1, 2) %}{{ x }}{% endfor %}")
add("dict in literal", "{{ {'a': [1, {'b': 2}]} }}")
add("nested function call", "{{ 'a-b-c'.split('-') | last }}")
add("subscript chain on literal", "{{ [1,2,3][0] }} {{ {'k': 'v'}['k'] }} {{ 'ab'[1] }}")
add("filter on subscript", "{{ d['a'] | upper }}", {"d": {"a": "x"}})
add("boolean keys in json data", "{{ m['true'] }} {{ m[true] }}", {"m": {"true": "A"}})
add("very deep attr chain", "{{ a.b.c.d.e }}", {"a": {"b": {"c": {"d": {"e": "deep"}}}}})
add("list of tuples repr", "{{ [[1, 2], [3, 4]] }}")
add("mixed container repr", "{{ (1, [2, (3,)]) }}")


# ================= edge-case expansion (round 3) =================

# --- string methods: round 2 ---------------------------------------------
add("str center method", "{{ 'a'.center(5, '*') }} {{ 'ab'.center(6, '-') }}")
add("str center no fill", "{{ 'a'.center(5) }}|")
add("str count start end", "{{ 'banana'.count('an', 2) }} {{ 'aaaa'.count('aa') }}")
add("str find start end", "{{ 'abcabc'.find('b', 2) }} {{ 'abc'.find('z') }} {{ 'abcabc'.index('b', 2) }}")
add("str rfind", "{{ 'abcabc'.rfind('b') }} {{ 'abc'.rfind('z') }}")
add("str islower isupper", "{{ 'ab'.islower() }} {{ 'AB'.isupper() }} {{ 'aB'.islower() }} {{ ''.islower() }}")
add("str istitle", "{{ 'Hello World'.istitle() }} {{ 'Hello world'.istitle() }}")
add("str isspace isalnum", "{{ '  '.isspace() }} {{ 'a1'.isalnum() }} {{ 'a 1'.isalnum() }}")
add("str title digits", "{{ 'abc 2nd'.title() }}")
add("str strip multi", "{{ 'xxayx'.strip('xy') }} {{ 'xxayx'.lstrip('x') }} {{ 'xxayx'.rstrip('x') }}")
add("str split maxsplit", "{{ 'a,b,c'.split(',', 1) | join('|') }}")
add("str split empty sep error", "{{ 'abc'.split('') }}")
add("str rsplit no max", "{{ 'a,b,c'.rsplit(',') | join('|') }}")
add("str zfill 2", "{{ '5'.zfill(3) }} {{ '-5'.zfill(3) }} {{ '55'.zfill(1) }}")
add("str replace count", "{{ 'aaaa'.replace('a', 'b', 2) }}")
add("str endswith tuple", "{{ 'abc'.endswith('b') }} {{ 'abc'.endswith('bc') }}")
add("str startswith empty", "{{ 'abc'.startswith('') }}")
add("str format index repeat", "{{ '{0}{0}{1}'.format('a', 'b') }}")
add("str format escaped brace", "{{ '{{}}'.format() }}")
add("str swapcase mixed", "{{ 'aBc123'.swapcase() }}")
add("str removeprefix no match", "{{ 'abc'.removeprefix('x') }} {{ 'abc'.removesuffix('x') }}")
add("str removeprefix whole", "{{ 'abc'.removeprefix('abc') }}|")
add("str ljust beyond", "{{ 'ab'.ljust(2) }}|")
add("str expandtabs default", "{{ 'a\\tb'.expandtabs() }}")
add("str expandtabs zero", "{{ 'a\\tb'.expandtabs(0) }}")
add("str splitlines keepends", "{{ 'a\\nb'.splitlines(True) | join(';') }}")
add("str empty splitlines", "{{ ''.splitlines() | length }}")
add("str casefold upper", "{{ 'STRASSE'.casefold() }}")

# --- filters: round 3 -------------------------------------------------------
add("replace count kwarg", "{{ 'aaaa' | replace('a', 'b', count=2) }}")
add("format r conv", "{{ '%r' | format('a') }} {{ '%r' | format(1) }}")
add("format x hash", "{{ '%x' | format(255) }} {{ '%X' | format(255) }} {{ '%o' | format(8) }}")
add("format e", "{{ '%e' | format(1234.5678) }}")
add("format zero pad", "{{ '%05d' | format(42) }} {{ '%-5d|' | format(42) }}")
add("format percent only", "{{ '%%' | format() }}")
add("int base16", "{{ 'ff' | int(base=16) }} {{ '0x10' | int(base=16) }}")
add("int float default", "{{ 'x' | int(default=7) }} {{ missing | int }}")
add("float default", "{{ missing | float(default=2.5) }}")
add("round ceil floor", "{{ 2.1 | round(method='ceil') }} {{ 2.9 | round(method='floor') }}")
add("round precision 1", "{{ 2.25 | round(1) }} {{ 2.35 | round(1) }}")
add("round common negative half", "{{ -2.5 | round }} {{ -0.5 | round }}")
add("dictsort by value", "{{ {'a': 3, 'b': 1} | dictsort(by='value') | map('last') | join(',') }}")
add("dictsort reverse", "{{ {'a': 1, 'b': 2} | dictsort(reverse=true) | map('first') | join(',') }}")
add("sort attribute missing error", "{{ users | sort(attribute='zz') | length }}", {"users": [{"n": "a"}]})
add("min max bool", "{{ [true, false] | min }} {{ [true, false] | max }}")
add("unique attribute", "{{ users | unique(attribute='g') | map(attribute='n') | join(',') }}",
    {"users": [{"n": "a", "g": 1}, {"n": "b", "g": 1}, {"n": "c", "g": 2}]})
add("join attribute missing", "{{ users | join(',', attribute='zz') }}", {"users": [{"n": "a"}]})
add("sum attribute", "{{ items | sum(attribute='v') }}", {"items": [{"v": 1}, {"v": 2}]})
add("sum start", "{{ [1,2] | sum(start=10) }}")
add("sum floats", "{{ [1.5, 2.5] | sum }}")
add("batch fill tuple repr", "{% for row in [1,2,3] | batch(2, 0) %}{{ row }}{% endfor %}")
add("slice uneven", "{% for col in [1,2,3,4,5] | slice(2) %}[{{ col | join(',') }}]{% endfor %}")
add("select with args 2", "{{ [1,2,3,4] | select('divisibleby', 2) | join(',') }}")
add("reject with args 2", "{{ [1,2,3,4] | reject('divisibleby', 2) | join(',') }}")
add("selectattr eq test", "{{ users | selectattr('n', 'eq', 'a') | map(attribute='n') | join(',') }}",
    {"users": [{"n": "a"}, {"n": "b"}]})
add("rejectattr missing", "{{ users | rejectattr('zz') | length }}", {"users": [{"n": "a"}]})
add("groupby default arg", "{% for g in items | groupby('k', default='none') %}{{ g.grouper }};{% endfor %}",
    {"items": [{"v": 1}, {"k": "a", "v": 2}]})
add("tojson indent zero", "{{ [1] | tojson(indent=0) }}")
add("tojson string escapes", "{{ 'a\"b\\\\c\\nd' | tojson }}")
add("filesizeformat binary", "{{ 1024 | filesizeformat(true) }} {{ 1000 | filesizeformat }}")
add("filesizeformat small", "{{ 1 | filesizeformat }} {{ 0 | filesizeformat }}")
add("wordwrap width 1", "{{ 'ab cd' | wordwrap(1) }}")
add("wordwrap break off", "{{ 'aaaaaaaaaa bb' | wordwrap(5, false) }}")
add("truncate end longer", "{{ 'abcdefgh' | truncate(4, true, '...', 0) }}")
add("truncate no killwords", "{{ 'ab cd ef' | truncate(6, false, '...', 0) }}")
add("indent first 2", "{{ 'a\\nb' | indent(2, true) }}|")
add("indent tab char", "{{ 'a\\nb' | indent(1, true, ' ') }}|")
add("capitalize digits", "{{ '2nd place' | capitalize }}")
add("trim whitespace mixed", "{{ ' \\t a \\n ' | trim }}|")
add("title unicode 2", "{{ 'caf\u00e9 bar' | title }}")
add("urlencode for_qs", "{{ {'a b': 'c/d'} | urlencode }}")
add("urlencode string plus", "{{ 'a b+c' | urlencode }}")
add("default false boolean", "{{ false | default('d', true) }} {{ false | default('d') }}")
add("map attribute default none", "{{ users | map(attribute='age', default=none) | join(',') }}",
    {"users": [{"age": 3}, {"n": "x"}]})
add("list dict keys", "{{ {'b': 1, 'a': 2} | list | join(',') }}")
add("reverse tuple", "{{ (1, 2, 3) | reverse | join(',') }}")
add("first string", "{{ 'abc' | first }} {{ 'abc' | last }}")
add("length tuple", "{{ (1, 2) | length }}")
add("striptags script 2", "{{ '<script>x</script>ok' | striptags }}")
add("striptags unclosed 2", "{{ '<p>abc' | striptags }}")

# --- tests: round 2 ---------------------------------------------------------
add("test eq ne", "{{ 1 is eq 1 }} {{ 1 is ne 2 }} {{ 1 is equalto 1 }}")
add("test lt ge", "{{ 1 is lt 2 }} {{ 2 is ge 2 }} {{ 2 is gt 3 }}")
add("test sameas", "{{ 1 is sameas 1 }} {{ 1 is sameas 1.0 }} {{ none is sameas none }}")
add("test odd even neg", "{{ -3 is odd }} {{ -4 is even }} {{ 0 is even }}")
add("test escaped", "{{ '<x>' is escaped }} {{ 'x' | escape is escaped }}", autoescape=False)
add("test in not", "{{ 1 is not in [2] }} {{ 'a' is not in 'abc' }}")
add("test none vs undefined", "{{ missing is none }} {{ none is defined }} {{ missing is defined }}")
add("test boolean", "{{ true is boolean }} {{ 1 is boolean }}")
add("test callable", "{{ range is callable }} {{ 1 is callable }} {{ missing is callable }}")
add("test filter chained", "{{ [1,2] is iterable | string }}")

# --- loops: round 2 ---------------------------------------------------------
add("loop revindex", "{% for i in [1,2,3] %}{{ loop.revindex }}{% endfor %}")
add("loop first last", "{% for i in [1,2] %}{{ loop.first }}{{ loop.last }} {% endfor %}")
add("loop previtem nextitem", "{% for i in [1,2,3] %}{{ loop.previtem | default('-') }}{{ loop.nextitem | default('-') }} {% endfor %}")
add("loop depth0 nested", "{% for a in [1] %}{% for b in [2] %}{{ loop.depth }}{{ loop.depth0 }}{% endfor %}{% endfor %}")
add("loop cycle multi", "{% for i in [1,2,3,4] %}{{ loop.cycle('a', 'b') }}{% endfor %}")
add("loop changed 2", "{% for i in [1,1,2,2] %}{{ loop.changed(i) }} {% endfor %}")
add("loop length outer unchanged", "{% for i in [1,2] %}{% for j in [1] %}{{ loop.length }}{% endfor %}{{ loop.length }}{% endfor %}")
add("nested loop outer var", "{% for a in [1,2] %}{% for b in [3] %}{{ a }}{{ b }}{% endfor %}{% endfor %}")
add("for else with filter empty", "{% for x in [] | select('odd') %}x{% else %}e{% endfor %}")
add("for string iterate", "{% for c in 'ab' %}{{ c }}{% endfor %}")
add("for dict iterate values", "{% for k in {'a': 1, 'b': 2} %}{{ k }}{% endfor %}")
add("recursive loop depth", "{% for i in [1] recursive %}{{ loop.depth }}{{ i }}{{ loop(item.children) if item.children }}{% endfor %}",
    {"children": []})
add("for tuple unpack pairs", "{% for a, b in [(1,2), (3,4)] %}{{ a }}{{ b }}{% endfor %}")
add("for unpack too few", "{% for a, b in [[1]] %}{{ a }}{% endfor %}")

# --- arithmetic: round 2 ----------------------------------------------------
add("string times negative", "{{ 'ab' * -1 }}|")
add("list times int", "{{ [1] * 3 }} {{ [0] * 0 }}|")
add("comparison chain", "{{ 1 < 2 < 3 }} {{ 1 < 2 > 3 }}")
add("precedence mixed", "{{ 2 + 3 * 4 }} {{ (2 + 3) * 4 }} {{ 2 ** 3 * 4 }}")
add("float int compare", "{{ 1.0 < 2 }} {{ 2 > 1.5 }}")
add("negative floor div", "{{ -7 // 2 }} {{ 7 // -2 }} {{ -7.0 // 2 }}")
add("negative mod float", "{{ -7.5 % 2 }} {{ 7.5 % -2 }}")
add("pow zero", "{{ 5 ** 0 }} {{ 0 ** 0 }} {{ 0 ** 2 }}")
add("pow negative base", "{{ (-2) ** 3 }} {{ (-2) ** 2 }}")
add("unary minus filter", "{{ -4.7 | abs }} {{ -(4.7 | abs) }}")
add("plus unary", "{{ +5 }} {{ +'5' }}")
add("big float", "{{ 1.7976931348623157e+308 }} {{ 5e-324 }}")
add("int literal hex oct bin", "{{ 0x10 }} {{ 0o10 }} {{ 0b10 }}")
add("division sign", "{{ -6 / 3 }} {{ 6 / -3 }} {{ -6 // 3 }}")

# --- macros: round 2 --------------------------------------------------------
add("macro default expr 2", "{% macro m(a, b=a + 1) %}{{ a }}{{ b }}{% endmacro %}{{ m(1) }} {{ m(1, 5) }}")
add("macro kwargs printing", "{% macro m() %}{{ kwargs | dictsort | join(',') }}{% endmacro %}{{ m(x=1) }}")
add("macro varargs printing", "{% macro m() %}{{ varargs | join(',') }}{% endmacro %}{{ m(1, 2) }}")
add("macro caller args", "{% macro m() %}{{ caller('x') }}{% endmacro %}{% call m(a) %}[{{ a }}]{% endcall %}")
add("macro nested call scope", "{% macro outer() %}{% macro inner() %}i{% endmacro %}{{ inner() }}o{% endmacro %}{{ outer() }}")
add("macro with filter body", "{% macro m() %}ab{% endmacro %}{{ m() | upper }}")
add("call macro no caller param", "{% macro m(a) %}{{ a }}{% endmacro %}{{ m(1) }}")
add("macro name shadowed var", "{% set m = 'v' %}{% macro m() %}M{% endmacro %}{{ m() }}")

# --- whitespace: round 2 ----------------------------------------------------
add("marker minus minus", "a  {%- set x = 1 -%}  b{{ x }}")
add("var minus right", "{{ 'x' -}} y")
add("comment markers 2", "a {#- c -#} b")
add("raw tag lstrip", "x\n  {% raw %}y{% endraw %}", lstrip_blocks=True)
add("nested raw", "{% raw %}{% raw %}x{% endraw %}{% endraw %}")
add("if trim both", "{% if true -%}  X  {%- endif %}|")

# --- autoescape: round 2 ----------------------------------------------------
add("escape then safe then upper", "{{ ('<x>' | escape) | safe }}", autoescape=True)
add("autoescape int 2", "{{ 5 }} {{ none }} {{ true }}", autoescape=True)
add("autoescape loop var", "{% for x in ['<a>'] %}{{ x }}{% endfor %}", autoescape=True)
add("autoescape set reuse", "{% set x = '<a>' %}{{ x }}{{ x | upper }}", autoescape=True)
add("safe double", "{{ '<x>' | safe | safe }}", autoescape=True)
add("escape non string 2", "{{ 5 | escape }}", autoescape=False)

# --- misc: round 3 -----------------------------------------------------------
add("nested with shadow", "{% with x = 1 %}{% with x = 2 %}{{ x }}{% endwith %}{{ x }}{% endwith %}")
add("set in with leaks", "{% with x = 1 %}{% set y = 2 %}{% endwith %}{{ x | default('d') }}{{ y | default('d') }}")
add("dict key dotted access", "{{ d.'k' }}")
add("getitem chained", "{{ d['a']['b'] }}", {"d": {"a": {"b": "c"}}})
add("attr of list result", "{{ [1,2] | first + 1 }}")
add("concat with int", "{{ 'a' ~ 1 ~ true ~ none }}")
add("if elif", "{% if false %}a{% elif true %}b{% else %}c{% endif %}")
add("if elif chain", "{% if false %}a{% elif false %}b{% elif true %}c{% else %}d{% endif %}")
add("filter block no filter args", "{% filter upper %}ab{% endfilter %}")
add("filter block chained", "{% filter upper | trim %} ab {% endfilter %}|")
add("expression in attribute arg", "{{ users | map(attribute='n') | join(',') }}", {"users": [{"n": "x"}, {"n": "y"}]})
add("boolean keys in json data 2", "{{ m['true'] }} {{ m[true] }}", {"m": {"true": "A"}})


# ================= edge-case expansion (round 4) =================

# --- urlize and misc filters ---------------------------------------------
add("urlize basic", "{{ 'visit http://x.com now' | urlize }}")
add("urlize www", "{{ 'see www.example.com here' | urlize }}")
add("urlize email", "{{ 'mail a@b.com ok' | urlize }}")
add("urlize plain", "{{ 'no links here' | urlize }}")
add("wordcount", "{{ 'a b  c' | wordcount }} {{ '' | wordcount }}")
add("batch then join", "{{ [1,2,3,4] | batch(2) | map('join', '-') | join('|') }}")
add("slice join", "{{ [1,2,3] | slice(2) | map('join', '+') | join('|') }}")
add("map test reject", "{{ ['a', 'bb', 'ccc'] | map('length') | join(',') }}")
add("attr selects combined", "{{ users | selectattr('active') | rejectattr('n', 'eq', 'b') | map(attribute='n') | join(',') }}",
    {"users": [{"n": "a", "active": True}, {"n": "b", "active": True}, {"n": "c", "active": False}]})
add("items dictsort", "{{ {'b': 1, 'a': 2} | items | list | first | join(',') }}")
add("first on tuple", "{{ (7, 8) | first }} {{ (7, 8) | last }}")
add("reverse string", "{{ 'abc' | reverse }}")
add("sort reverse", "{{ [3,1,2] | sort(reverse=true) | join(',') }}")
add("sort attribute numeric", "{{ users | sort(attribute='age') | map(attribute='n') | join(',') }}",
    {"users": [{"n": "a", "age": 3}, {"n": "b", "age": 1}]})
add("sum bool", "{{ [true, true] | sum }}")
add("min string attr", "{{ users | min(attribute='n') }}", {"users": [{"n": "b"}, {"n": "a"}]})
add("max attr", "{{ users | max(attribute='n') }}", {"users": [{"n": "b"}, {"n": "a"}]})
add("unique mixed case attr", "{{ users | unique(attribute='n') | map(attribute='n') | join(',') }}",
    {"users": [{"n": "a"}, {"n": "A"}, {"n": "b"}]})
add("tojson float", "{{ 1.0 | tojson }} {{ 0.5 | tojson }}")
add("tojson empty", "{{ [] | tojson }} {{ {} | tojson }}")
add("tojson nested indent", "{{ {'a': [1, {'b': 2}]} | tojson(indent=2) }}")
add("filesizeformat tiny binary", "{{ 512 | filesizeformat(true) }}")
add("filesizeformat big binary", "{{ 1048576 | filesizeformat(true) }}")
add("center filter", "{{ 'a' | center(5) }}|{{ 'ab' | center(6) }}|")
add("indent blank", "{{ 'a\\n\\nb' | indent(2) }}|")
add("replace regex special", "{{ 'a+b' | replace('+', '-') }}")
add("trim single char", "{{ 'xx' | trim('x') }}|")
add("title filter digits", "{{ '2nd abc' | title }}")
add("urlencode dict", "{{ {'a': 'b c', 'd': 'e&f'} | urlencode }}")
add("striptags nested", "{{ '<div><p>a</p> <b>b</b></div>' | striptags }}")
add("wordwrap width 0", "{{ 'ab' | wordwrap(0) }}")

# --- tests: round 3 -------------------------------------------------------
add("test in tuple", "{{ 1 is in (1, 2) }} {{ 3 is in (1, 2) }}")
add("test in none", "{{ 1 is in none }}")
add("test mapping vs sequence", "{{ [1] is mapping }} {{ {} is sequence }} {{ 'a' is mapping }}")
add("test divisibleby negative", "{{ 4 is divisibleby -2 }} {{ 3 is divisibleby 2 }}")
add("test eq bool int", "{{ true is eq 1 }} {{ true is eq 2 }}")
add("test lt string", "{{ 'a' is lt 'b' }}")
add("test sameas strings", "{{ 'a' is sameas 'a' }}")
add("test number string", "{{ '1' is number }}")
add("test float int", "{{ 1 is float }} {{ 1.0 is float }}")
add("test escaped markup", "{{ ('<x>' | safe) is escaped }}", autoescape=False)
add("test odd float", "{{ 1.0 is odd }}")
add("test defined nested", "{{ a.b is defined }}", {"a": {"b": 1}})

# --- comparisons and boolean ----------------------------------------------
add("in string", "{{ 'b' in 'abc' }} {{ 'x' in 'abc' }}")
add("in list nested", "{{ [1] in [[1], [2]] }} {{ 1 in [[1]] }}")
add("in dict value", "{{ 'a' in {'a': 1} }} {{ 1 in {'a': 1} }}")
add("not in", "{{ 1 not in [2] }} {{ 1 not in [1] }}")
add("and or shortcircuit", "{{ false and missing.attr }} {{ true or missing.attr }}")
add("bool in arithmetic compare", "{{ true > false }} {{ true >= 1 }}")
add("compare str num error", "{{ 'a' < 1 }}")
add("ternary nested", "{{ (false if true else true) ? no }} {{ 'a' if false else ('b' if false else 'c') }}")

# --- arithmetic: round 3 ----------------------------------------------------
add("float int mix repr", "{{ 2 + 1.5 }} {{ 3 * 0.5 }} {{ 10 / 4 }}")
add("mod bool", "{{ 7 % true }}")
add("floor div bool", "{{ 7 // true }}")
add("pow chain", "{{ 2 ** 2 ** 2 ** 1 }}")
add("pow float negative", "{{ 2.0 ** -2 }}")
add("neg div float", "{{ -6.0 // 4 }}")
add("add string list error", "{{ 'a' + [1] }}")
add("sub string error", "{{ 'a' - 'b' }}")
add("compare bool float", "{{ true == 1.0 }} {{ false == 0.0 }}")
add("big mul", "{{ 3000000 * 3000000 }}")
add("overflow add", "{{ 9223372036854775807 + 1 }}")

# --- undefined: round 3 -----------------------------------------------------
add("undefined repr", "{{ missing }}|{{ [missing] }}|{{ {'k': missing} }}")
add("undefined in if", "{% if missing %}a{% else %}b{% endif %}")
add("undefined and", "{{ missing and 'x' }}|")
add("undefined or value", "{{ missing or 'x' }}")
add("undefined tojson", "{{ missing | tojson }}")
add("undefined upper default", "{{ missing | upper | default('d') }}")
add("undefined attr then filter", "{{ missing.attr | length }}")
add("undefined getattr default", "{{ missing.attr | default('d') }}")
add("undefined not", "{{ not missing }} {{ not missing.attr }}")

# --- statements: round 3 ----------------------------------------------------
add("for if filter else", "{% for x in [1,2,3] if x > 1 %}{{ x }}{% else %}e{% endfor %}")
add("set multiple", "{% set a, b = 1, 2 %}{{ a }}{{ b }}")
add("set attr namespace", "{% set ns = namespace() %}{% set ns.v = 5 %}{{ ns.v }}")
add("set item dict", "{% set d = {'a': 1} %}{% set d['b'] = 2 %}{{ d | dictsort | join(',') }}")
add("with scope nested var", "{% with x = 1 %}{% set y = x + 1 %}{{ y }}{% endwith %}{{ y | default('d') }}")
add("autoescape block nested", "{% autoescape true %}{% autoescape false %}{{ v }}{% endautoescape %}{{ v }}{% endautoescape %}",
    {"v": "<x>"})
add("do tag", "{% set x = [] %}{% do x.append(1) %}{% do x.append(2) %}{{ x | join(',') }}")
add("elif without else", "{% if false %}a{% elif false %}b{% endif %}|")

# --- loops: round 3 ----------------------------------------------------------
add("loop index deep recursive", "{% for i in [[1, [2]]] recursive %}{{ loop.depth }}:{{ i if i is not mapping and i is not sequence else '' }}{{ loop(i) if i is sequence }}{% endfor %}")
add("recursive nested list", "{% for i in data recursive %}{{ i.v if i.v is defined else '' }}{{ loop(i.c | default([])) }}{% endfor %}",
    {"data": [{"v": "a", "c": [{"v": "b", "c": []}]}]})
add("loop previtem first", "{% for i in [1,2] %}{{ loop.previtem | default('none') }}{% endfor %}")
add("loop nextitem last", "{% for i in [1,2] %}{{ loop.nextitem | default('none') }}{% endfor %}")
add("loop cycle unequal", "{% for i in [1,2,3,4,5] %}{{ loop.cycle('x', 'y') }}{% endfor %}")
add("loop length access", "{% for i in [1,2,3] %}{{ loop.length }}{% endfor %}")
add("for over generator map", "{% for x in [1,2] | map('string') %}{{ x }}{% endfor %}")
add("for over selectattr", "{% for x in users | selectattr('ok') %}{{ x.n }}{% endfor %}",
    {"users": [{"n": "a", "ok": True}, {"n": "b", "ok": False}]})
add("for nested unpack triple", "{% for a, b, c in [(1,2,3)] %}{{ a }}{{ b }}{{ c }}{% endfor %}")
add("nested unpack deep", "{% for (a, (b, c)), d in [[(1, (2, 3)), 4]] %}{{ a }}{{ b }}{{ c }}{{ d }}{% endfor %}")

# --- macros: round 3 ----------------------------------------------------------
add("macro varargs length", "{% macro m() %}{{ varargs | length }}{% endmacro %}{{ m(1, 2, 3) }}")
add("macro kwargs iterate", "{% macro m() %}{% for k in kwargs | dictsort %}{{ k[0] }}={{ k[1] }};{% endfor %}{% endmacro %}{{ m(b=2, a=1) }}")
add("macro param default filter", "{% macro m(a='x' | upper) %}{{ a }}{% endmacro %}{{ m() }}")
add("macro passes kwargs through", "{% macro m(a) %}{{ a }}{% endmacro %}{{ m(a=9) }}")
add("macro nested call", "{% macro outer() %}[{{ caller('A') }}]{% endmacro %}{% call outer(x) %}<{{ x }}>{% endcall %}")
add("macro recursion depth", "{% macro r(n) %}{{ n }}{% if n > 0 %}{{ r(n - 1) }}{% endif %}{% endmacro %}{{ r(3) }}")
add("macro in if defined later", "{% if true %}{% macro m() %}M{% endmacro %}{{ m() }}{% endif %}")
add("call with args unused", "{% macro m(a, b) %}{{ a }}-{{ b }}{% endmacro %}{% call(1, 2) m(1, 2) %}c{% endcall %}")

# --- inheritance: round 3 ------------------------------------------------------
add("extends block not in parent", "{% extends 'base.html' %}{% block extra %}E{% endblock %}", templates={
    "base.html": "base"})
add("nested block override both", "{% extends 'base.html' %}{% block outer %}O({% block inner %}I{% endblock %}){% endblock %}", templates={
    "base.html": "{% block outer %}[{% block inner %}D{% endblock %}]{% endblock %}"})
add("super in middle only", "{% extends 'mid.html' %}{% block b %}C+{{ super() }}{% endblock %}", templates={
    "base.html": "{% block b %}B{% endblock %}",
    "mid.html": "{% extends 'base.html' %}{% block b %}M({{ super() }}){% endblock %}"})
add("include with context", "{% set v = 'cv' %}{% include 'p.html' %}", {"x": "dv"}, templates={
    "p.html": "{{ x | default('none') }}"})
add("include without context", "{% include 'p.html' without context %}", {"x": "dv"}, templates={
    "p.html": "{{ x | default('none') }}"})
add("include ignore missing single", "{% include 'nope.html' ignore missing %}ok")
add("import set from module", "{% import 'm.html' as m %}{{ m.v }}", templates={
    "m.html": "{% set v = 42 %}"})
add("from import multiple alias", "{% from 'm.html' import a, b as bb %}{{ a }}{{ bb }}", templates={
    "m.html": "{% set a = 'A' %}{% set b = 'B' %}"})
add("block in included template ignored", "{% include 'p.html' %}", templates={
    "p.html": "{% block b %}B{% endblock %}"})
add("extends chain three", "{% extends 'mid.html' %}{% block b %}C{% endblock %}", templates={
    "base.html": "{% block b %}B{% endblock %}",
    "mid.html": "{% extends 'base.html' %}"})
add("required block with default", "{% extends 'base.html' %}{% block req %}X{% endblock %}", templates={
    "base.html": "{% block req required %}D{% endblock %}"})

# --- whitespace: round 3 ---------------------------------------------------------
add("strip both markers", "a\n  {{- 'x' -}}  \nb")
add("lstrip only no trim", "a\n  {% if true %}x{% endif %}", lstrip_blocks=True)
add("trim only no lstrip", "a\n  {% if true %}\nx\n{% endif %}", trim_blocks=True)
add("comment midline", "a{# c #}b")
add("comment with tags inside", "a{# {{ x }} {% if %} #}b")
add("marker on elif", "{% if false %}a\n{% elif true -%}\nb\n{% endif %}")
add("var marker multiline", "{{-\n 1 -}}")
add("raw multiline lstrip", "x\n  {% raw %}\ny\n{% endraw %}\nz", lstrip_blocks=True)
add("blocks adjacent", "{% if true %}{% if true %}x{% endif %}{% endif %}")

# --- lexer/parser: round 2 --------------------------------------------------------
add("string with both quotes", "{{ 'a\"b\'c' }}")
add("string with newline escape", "{{ 'a\\nb' }}")
add("string with unicode escape", "{{ 'a\\u00e9b' }}")
add("nested quotes in dict", "{{ {'a': 'x', 'b': \"y\"} }}")
add("comment in expression", "{{ 1 + # c }}")
add("trailing comma dict", "{{ {'a': 1,} }}")
add("trailing comma list", "{{ [1, 2,] }}")
add("unterminated string error", "{{ 'abc }}")
add("unterminated tag error", "{{ abc")
add("unclosed if error", "{% if true %}x")
add("unexpected endraw", "{% raw %}x")
add("nested brackets", "{{ [[1], [2]] | length }}")
add("negative index slice", "{{ 'abc'[-2:] }} {{ [1,2,3][-2:] }}")
add("step only slice", "{{ [1,2,3,4,5][::2] | join(',') }}")
add("slice on tuple", "{{ (1,2,3)[1:] | join(',') }}")
add("chained getitem call", "{{ d['a'] }}", {"d": {"a": [1, 2]}})

# --- autoescape: round 3 -------------------------------------------------------------
add("autoescape include", "{% include 'p.html' %}", {"v": "<x>"}, autoescape=True, templates={
    "p.html": "{{ v }}"})
add("autoescape macro param", "{% macro m(v) %}{{ v }}{% endmacro %}{{ m('<x>') }}", autoescape=True)
add("autoescape join sep", "{{ ['<a>', '<b>'] | join('<') }}", autoescape=True)
add("autoescape concat markup", "{{ '<a>' | safe ~ 'b' }}", autoescape=True)
add("escape markup safe", "{{ '<x>' | escape | safe }}", autoescape=False)
add("autoescape default undefined", "{{ missing | default('<d>') }}", autoescape=True)

# --- globals: round 2 ------------------------------------------------------------------
add("range negative step", "{% for i in range(5, 0, -2) %}{{ i }}{% endfor %}")
add("range start stop only", "{% for i in range(-2, 2) %}{{ i }}{% endfor %}")
add("range huge", "{{ range(1000000) | length }}")
add("cycler current initial", "{% set c = cycler('a', 'b') %}{{ c.current }}")
add("joiner custom sep", "{% set j = joiner('--') %}{{ j() }}a{{ j() }}b")
add("namespace init with kwargs", "{% set ns = namespace(a=1, b=2) %}{{ ns.a }}{{ ns.b }}")
add("namespace attr getitem", "{% set ns = namespace(v=3) %}{{ ns['v'] }}")
add("dict from pairs", "{{ dict([('a', 1), ('b', 2)]) | dictsort | join(',') }}")
add("lipsum markup length", "{{ lipsum() | length > 0 }}")


# ================= edge-case expansion (round 5) =================

# --- urlize edge -----------------------------------------------------------
add("urlize trailing punct", "{{ 'go to http://x.com, now' | urlize }}")
add("urlize paren", "{{ '(see http://x.com)' | urlize }}")
add("urlize https", "{{ 'https://secure.io' | urlize }}")
add("urlize multiple", "{{ 'a http://x.com b www.y.io c' | urlize }}")
add("urlize href attr", "{{ '<a href=\'http://x.com\'>x</a>' | urlize }}")

# --- filter arg validation and errors --------------------------------------
add("batch negative size", "{{ [1,2] | batch(-1) | length }}")
add("slice zero count", "{{ [1,2] | slice(0) | length }}")
add("round huge precision", "{{ 1.5 | round(50) }}")
add("int garbage base", "{{ 'zz' | int(base=36) }}")
add("float nan literal", "{{ none if false else 1 }}")
add("replace no args", "{{ 'a' | replace }}")
add("tojson set", "{{ {1, 2} | tojson }}")
add("min mixed error", "{{ [1, 'a'] | min }}")
add("max mixed error", "{{ [1, 'a'] | max }}")
add("sort mixed error", "{{ [1, 'a'] | sort }}")
add("dictsort on list", "{{ [1] | dictsort }}")
add("join on int", "{{ 5 | join(',') }}")
add("batch on int", "{{ 5 | batch(2) | length }}")
add("first on int", "{{ 5 | first }}")
add("list on int", "{{ 5 | list }}")
add("urlencode int", "{{ 5 | urlencode }}")
add("indent int", "{{ 5 | indent(2) }}")
add("reverse int", "{{ 5 | reverse }}")

# --- container operations ---------------------------------------------------
add("list compare eq", "{{ [1, 2] == [1, 2] }} {{ [1] == [2] }} {{ [1] == 'x' }}")
add("dict compare eq", "{{ {'a': 1} == {'a': 1} }} {{ {'a': 1} == {'a': 2} }}")
add("list compare lt", "{{ [1, 2] < [2] }} {{ [2] < [1, 2] }}")
add("tuple compare eq", "{{ (1, 2) == (1, 2) }} {{ (1,) == (1, 2) }}")
add("string compare", "{{ 'a' < 'b' }} {{ 'b' < 'a' }} {{ 'A' < 'a' }}")
add("nested in tuple", "{{ 2 in (1, 2) }}")
add("dictsort tuple repr", "{{ {'a': 1} | dictsort }}")
add("items tuple repr", "{{ {'a': 1} | items | list }}")

# --- nested filters and tests -----------------------------------------------
add("filter on filter result", "{{ 'ab' | upper | lower | reverse }}")
add("test on filter result", "{{ 'abc' | upper is eq 'ABC' }}")
add("filter in for iter", "{% for x in 'ab' | list %}{{ x }}{% endfor %}")
add("filter in if cond", "{% if 'a' | upper is eq 'A' %}y{% endif %}")
add("map filter with args", "{{ ['ab', 'c'] | map('center', 3, '-') | join('|') }}")
add("map test with args", "{{ [1, 2, 3, 4] | map('even') | join(',') }}")
add("selectattr with test args", "{{ users | selectattr('age', 'gt', 2) | map(attribute='n') | join(',') }}",
    {"users": [{"n": "a", "age": 3}, {"n": "b", "age": 1}]})
add("reject test on undefined attr", "{{ users | rejectattr('zz', 'defined') | length }}", {"users": [{"n": "a"}]})
add("groupby numeric keys", "{% for g in items | groupby('k') %}{{ g.grouper }};{% endfor %}",
    {"items": [{"k": 2, "v": 1}, {"k": 10, "v": 2}]})
add("groupby none values", "{% for g in items | groupby('k') %}{{ g.grouper }};{% endfor %}",
    {"items": [{"k": None, "v": 1}, {"k": None, "v": 2}]})
add("unique numbers", "{{ [1, 1.0, 2, true] | unique | join(',') }}")
add("sort stability", "{{ [{'k': 1, 'v': 'a'}, {'k': 1, 'v': 'b'}, {'k': 0, 'v': 'c'}] | sort(attribute='k') | map(attribute='v') | join(',') }}")

# --- undefined chains ---------------------------------------------------------
add("undefined nested in loop", "{% for x in [missing] %}{{ x | default('d') }}{% endfor %}")
add("undefined arithmetic default", "{{ (missing + 1) | default('d') }}")
add("undefined is defined test", "{{ missing.x is defined }} {{ missing is defined }}")
add("undefined bool int", "{{ missing == false }} {{ missing == 0 }}")
add("undefined truthiness if", "{% if missing %}a{% endif %}|")
add("undefined in dict", "{{ missing in {'a': 1} }}")
add("loop var after loop", "{% for i in [1] %}{% endfor %}{{ loop | default('d') }}")

# --- inheritance: round 4 -------------------------------------------------------
add("block nested in for in block", "{% extends 'base.html' %}{% block b %}{% for i in [1,2] %}{{ i }}{% endfor %}{% endblock %}", templates={
    "base.html": "{% block b %}{% endblock %}"})
add("extends then include", "{% extends 'base.html' %}{% block b %}{% include 'p.html' %}{% endblock %}", templates={
    "base.html": "{% block b %}{% endblock %}",
    "p.html": "P"})
add("import inside block", "{% extends 'base.html' %}{% block b %}{% import 'm.html' as m %}{{ m.v }}{% endblock %}", templates={
    "base.html": "{% block b %}{% endblock %}",
    "m.html": "{% set v = 'V' %}"})
add("macro defined in parent", "{% extends 'base.html' %}{% block b %}{{ mm() }}{% endblock %}", templates={
    "base.html": "{% macro mm() %}MM{% endmacro %}{% block b %}{% endblock %}"})
add("set in parent visible in child block", "{% extends 'base.html' %}{% block b %}{{ v }}{% endblock %}", templates={
    "base.html": "{% set v = 'PV' %}{% block b %}{% endblock %}"})
add("super with args error", "{% extends 'base.html' %}{% block b %}{{ super(1) }}{% endblock %}", templates={
    "base.html": "{% block b %}B{% endblock %}"})
add("super in non-block context", "{{ super() }}")
add("block name reuse", "{% block b %}1{% endblock %}{% block b %}2{% endblock %}")

# --- macros: round 4 --------------------------------------------------------------
add("macro caller default param", "{% macro m() %}{{ caller() }}{% endmacro %}{% call m() %}C{% endcall %}")
add("macro shadow loop var", "{% for m in [1] %}{% macro m2() %}{{ m }}{% endmacro %}{{ m2() }}{% endfor %}")
add("macro uses global", "{% macro m() %}{{ range(2) | join(',') }}{% endmacro %}{{ m() }}")
add("macro recursive via variable", "{% macro outer() %}{{ inner() }}{% endmacro %}{% macro inner() %}I{% endmacro %}{{ outer() }}")
add("macro arg expression", "{% macro m(a) %}{{ a * 2 }}{% endmacro %}{{ m(1 + 2) }}")
add("macro param shadowing global", "{% macro m(range) %}{{ range }}{% endmacro %}{{ m(7) }}")

# --- whitespace: round 4 -------------------------------------------------------------
add("trim on else", "{% if false %}a\n{% else -%}\nb\n{% endif %}", trim_blocks=True)
add("marker between text", "a\n  {%- if true %}b{% endif %}\n  c")
add("raw with var markers", "{{- 'x' -}}{% raw %}y{% endraw %}")
add("nested if markers deep", "{%- if true -%}\n{%- if true -%}X{%- endif -%}\n{%- endif -%}")
add("set marker inline", "a {%- set x = 1 -%} b{{ x }}")
add("lstrip nested blocks", "{% if true %}\n  {% if true %}\n    x\n  {% endif %}\n{% endif %}", lstrip_blocks=True, trim_blocks=True)

# --- lexer: round 3 --------------------------------------------------------------------
add("string backslash at end", "{{ 'a\\' }}")
add("string triple quote attempt", "{{ 'a' 'b' }}")
add("int with underscores", "{{ 1_000 }}")
add("float leading dot", "{{ .5 }}")
add("float trailing e", "{{ 1e }}")
add("negative exponent literal", "{{ 1e-2 }} {{ 1E+2 }}")
add("adjacent operators", "{{ 1 - -2 }} {{ 1 -+2 }}")
add("comment only template", "{# just a comment #}|")
add("comment unclosed error", "{# c }}x")
add("percent in text", "100% done")
add("brace in text", "a { b } c")
add("lone opener", "a { b")
add("deep nesting", "{% if true %}{% if true %}{% if true %}x{% endif %}{% endif %}{% endif %}")
add("deep nested lists", "{{ [[[[1]]]] }}")
add("deep nested dicts", "{{ {'a': {'b': {'c': {'d': 1}}}} | tojson }}")

# --- autoescape: round 4 ------------------------------------------------------------------
add("escape urlize", "{{ 'http://x.com?a=<b>' | urlize }}", autoescape=True)
add("markup through concat", "{{ ('<a>' | safe) ~ ('<b>') }}", autoescape=True)
add("escape in loop", "{% for x in ['<a>', '<b>'] %}{{ x }}{% endfor %}", autoescape=True)
add("escape conditional markup", "{{ ('<a>' | safe) if true else 'b' }}", autoescape=True)
add("escape macro caller", "{% macro m() %}{{ caller() }}{% endmacro %}{% call m() %}<x>{% endcall %}", autoescape=True)
add("escape set block", "{% set x %}<y>{% endset %}{{ x }}", autoescape=True)
add("escape with filter block", "{% filter upper %}<x>{% endfilter %}", autoescape=True)

# --- numbers: round 4 -----------------------------------------------------------------------
add("int edge values", "{{ 0 }} {{ -0 }} {{ 2147483647 }} {{ 2147483648 }}")
add("float precision", "{{ 0.1 }} {{ 0.2 }} {{ 0.1 + 0.2 }}")
add("float compare epsilon", "{{ 0.1 + 0.2 == 0.3 }} {{ abs(0.1 + 0.2 - 0.3) < 1e-9 }}")
add("division always float", "{{ 4 / 2 }} {{ 1 / 3 }}")
add("modulo one", "{{ 5 % 1 }} {{ 5.5 % 1 }}")
add("pow large float", "{{ 2.0 ** 10 }} {{ 10 ** 2.0 }}")
add("sum overflow error", "{{ [9223372036854775807, 1] | sum }}")
add("negative zero int ops", "{{ -0 + 0 }} {{ -0 * 5 }}")
add("bool modulo", "{{ true % false }}")
add("float to int truncation", "{{ 1.9 | int }} {{ -1.9 | int }} {{ 1.5 | round(0) | int }}")

# --- statements: round 4 ----------------------------------------------------------------------
add("if with filter test combo", "{% if [1,2,3] | length is gt 2 %}y{% endif %}")
add("set conditional", "{% set x = 'a' if true else 'b' %}{{ x }}")
add("set in loop visible after", "{% set last = none %}{% for i in [1,2,3] %}{% set last = i %}{% endfor %}{{ last }}")
add("with nested loop var", "{% with x = 10 %}{% for x in [1] %}{{ x }}{% endfor %}{{ x }}{% endwith %}")
add("for over dict keys sorted", "{% for k in {'b': 1, 'a': 2} | dictsort %}{{ k[0] }}{% endfor %}")
add("elif chain precedence", "{% if 1 == 1 %}a{% elif 2 == 2 %}b{% endif %}")
add("do with filter", "{% set x = 1 %}{% do x.__nothing__ %}{{ x }}")

# --- globals: round 3 ---------------------------------------------------------------------------
add("range bool arg", "{% for i in range(true) %}{{ i }}{% endfor %}")
add("range huge step", "{% for i in range(0, 10, 100) %}{{ i }}{% endfor %}")
add("cycler one item", "{% set c = cycler('a') %}{{ c.next() }}{{ c.next() }}")
add("cycler empty error", "{% set c = cycler() %}{{ c.next() }}")
add("joiner no args", "{% set j = joiner() %}{{ j() }}x{{ j() }}")
add("namespace positional dict", "{% set ns = namespace({'a': 1}) %}{{ ns.a }}")


# ================= edge-case expansion (round 6) =================

# --- filters on none/bool -------------------------------------------------
add("upper none", "{{ none | upper }}")
add("lower none", "{{ none | lower }}")
add("title none", "{{ none | title }}")
add("trim none", "{{ none | trim }}|")
add("capitalize none", "{{ none | capitalize }}")
add("replace none", "{{ none | replace('a', 'b') }}")
add("length none", "{{ none | length }}")
add("first none", "{{ none | first }}")
add("list none", "{{ none | list }}")
add("join none", "{{ none | join(',') }}")
add("sort none", "{{ none | sort }}")
add("reverse none", "{{ none | reverse }}")
add("escape none", "{{ none | escape }}")
add("int true", "{{ true | int }} {{ false | int }}")
add("abs float int", "{{ -2.5 | abs }} {{ -2 | abs }}")
add("round on int", "{{ 5 | round }}")
add("upper markup", "{{ '<x>' | upper }}", autoescape=False)
add("striptags markup", "{{ ('<b>x</b>' | safe) | striptags }}", autoescape=False)
add("urlencode markup", "{{ ('a b' | safe) | urlencode }}", autoescape=False)

# --- string methods: round 3 ----------------------------------------------
add("str find negative", "{{ 'abcabc'.find('b', -3) }} {{ 'abc'.find('b', 5) }}")
add("str split maxsplit zero", "{{ 'a,b,c'.split(',', 0) | join('|') }}")
add("str rsplit maxsplit zero", "{{ 'a,b,c'.rsplit(',', 0) | join('|') }}")
add("str count zero sub", "{{ 'abc'.count('') }}")
add("str replace empty old", "{{ 'abc'.replace('', '-') }}")
add("str ljust zero", "{{ 'a'.ljust(0) }}|")
add("str center small", "{{ 'abc'.center(2) }}")
add("str zfill zero", "{{ 'a'.zfill(0) }}")
add("str isdigit empty", "{{ ''.isdigit() }} {{ ''.isalpha() }}")
add("str expandtabs multi", "{{ 'a\\t\\tb'.expandtabs(3) }}")
add("str splitlines cr only", "{{ 'a\\rb'.splitlines() | join('|') }}")
add("str rpartition no sep", "{{ 'abc'.rpartition('x') | join('|') }}")
add("str partition multi sep", "{{ 'a=b=c'.partition('=') | join('|') }} {{ 'a=b=c'.rpartition('=') | join('|') }}")
add("str casefold digits", "{{ 'A1b'.casefold() }}")

# --- tojson and encoding ---------------------------------------------------
add("tojson markup", "{{ ('<x>' | safe) | tojson }}", autoescape=False)
add("tojson tuple", "{{ (1, 2) | tojson }}")
add("tojson key order", "{{ {'b': 1, 'a': 2, 'A': 3} | tojson }}")
add("tojson slash", "{{ 'a/b' | tojson }}")
add("tojson control char", "{{ 'a\\u0001b' | tojson }}")
add("tojson int keys", "{{ {1: 'a'} | tojson }}")
add("urlencode dict unicode", "{{ {'k\u00e9y': 'v\u00e9l'} | urlencode }}")

# --- loop and scope corners -------------------------------------------------
add("loop outside for", "{{ loop | default('none') }}")
add("caller outside call", "{{ caller | default('none') }}")
varargs_outside = "{% macro m() %}{{ varargs | length }}{% endmacro %}{{ m() }}"
add("varargs outside macro", "{{ varargs | length }}")
add("loop in nested for shadow", "{% for i in [1] %}{% for j in [2] %}{{ i }}{{ j }}{% endfor %}{{ i }}{% endfor %}")
add("set inside for stays", "{% for i in [1] %}{% set x = i %}{% endfor %}{{ x | default('d') }}")
add("namespace in loop", "{% set ns = namespace(n=0) %}{% for i in [1,2,3] %}{% set ns.n = ns.n + i %}{% endfor %}{{ ns.n }}")
add("for else on filtered empty", "{% for x in [1,2,3] if false %}x{% else %}e{% endfor %}")
add("for over string with filter", "{% for c in 'ab' | upper %}{{ c }}{% endfor %}")
add("recursive with else", "{% for i in [] recursive %}x{% else %}e{% endfor %}")
add("loop.changed objects", "{% for x in ['a','a','b'] %}{{ loop.changed(x) }}{% endfor %}")

# --- macros: round 5 ---------------------------------------------------------
add("macro call in attr chain", "{% macro m() %}x{% endmacro %}{{ m() | upper }}")
add("macro returning list", "{% macro m() %}{{ [1,2] }}{% endmacro %}{{ m() }}")
add("macro with expression default", "{% macro m(a, b=a ~ '!') %}{{ b }}{% endmacro %}{{ m('hi') }}")
add("macro kwargs without call", "{% macro m(a=1) %}{{ a }}{% endmacro %}{{ m(b=2) }}")
add("call nested macros", "{% macro a() %}{{ caller() }}{% endmacro %}{% call a() %}in{% endcall %}")
add("macro access loop outer", "{% for x in [1] %}{% macro m() %}{{ x }}{% endmacro %}{{ m() }}{% endfor %}")

# --- inheritance: round 5 -------------------------------------------------------
add("extends with expression name", "{% extends name %}{% block b %}C{% endblock %}", {"name": "base.html"}, templates={
    "base.html": "{% block b %}B{% endblock %}"})
add("block with scoped", "{% extends 'base.html' %}{% block b scoped %}C{% endblock %}", templates={
    "base.html": "{% block b %}B{% endblock %}"})
add("three level super chain", "{% extends 'mid.html' %}{% block b %}3({{ super() }}){% endblock %}", templates={
    "base.html": "{% block b %}1{% endblock %}",
    "mid.html": "{% extends 'base.html' %}{% block b %}2({{ super() }}){% endblock %}"})
add("include in for with macro", "{% for i in [1,2] %}{% include 'p.html' %}{% endfor %}", templates={
    "p.html": "{{ i }}"})
add("import then from same", "{% import 'm.html' as m %}{% from 'm.html' import v %}{{ m.v }}{{ v }}", templates={
    "m.html": "{% set v = 'V' %}"})
add("extends missing error", "{% extends 'nope.html' %}")

# --- whitespace: round 5 -----------------------------------------------------------
add("marker on for", "{% for i in [1,2] -%}\n {{ i }}\n{%- endfor %}")
add("marker on set line", "x {%- set y = 2 -%} y{{ y }}")
add("trim blocks plus marker", "a\n{%+ if true %}\nb\n{% endif %}", trim_blocks=True)
add("lstrip marker on var", "x\n  {{- 1 }}", lstrip_blocks=True)
add("nested raw in if", "{% if true %}{% raw %}{{ x }}{% endraw %}{% endif %}")
add("comment between blocks", "{% if true %}a{# c #}{% endif %}")

# --- numbers: round 5 ------------------------------------------------------------------
add("float compare big", "{{ 1e308 * 10 }}")
add("int neg literal", "{{ - - 5 }} {{ - -5 }}")
add("chained add sub", "{{ 1 + 2 - 3 + 4 }}")
add("mixed mul div", "{{ 6 / 2 * 3 }}")
add("pow float frac", "{{ 4 ** 0.5 }} {{ 8 ** (1/3) | round(2) }}")
add("mod negative float", "{{ -7.5 % 2 }}")
add("floor div float neg", "{{ -7.5 // 2 }}")
add("compare float int", "{{ 1 == 1.0 }} {{ 1 < 1.5 }} {{ 2 > 1.9 }}")
add("bool in range", "{{ range(true) | length }}")
add("division by negative", "{{ 7 / -2 }} {{ 7 // -2 }} {{ 7 % -2 }}")

# --- statements: round 5 -----------------------------------------------------------------
add("if not in", "{% if 1 not in [1] %}a{% else %}b{% endif %}")
add("if is not test", "{% if none is not none %}a{% else %}b{% endif %}")
add("set attr on undefined", "{% set missing.x = 1 %}")
add("set item on int", "{% set x = 5 %}{% set x[0] = 1 %}")
add("with dict unpack", "{% with a, b = 1, 2 %}{{ a }}{{ b }}{% endwith %}")
add("for over none", "{% for x in none %}x{% else %}e{% endfor %}")
add("for over int", "{% for x in 5 %}x{% endfor %}")
add("elif after else error", "{% if false %}a{% else %}b{% elif true %}c{% endif %}")

# --- globals: round 4 ----------------------------------------------------------------------
add("range equal bounds", "{% for i in range(2, 2) %}x{% else %}e{% endfor %}")
add("range reverse", "{% for i in range(3, 0) %}{{ i }}{% endfor %}|")
add("cycler reset then current", "{% set c = cycler('a', 'b') %}{{ c.next() }}{{ c.reset() }}{{ c.current }}")
add("joiner reused", "{% set j = joiner('-') %}{{ j() }}{{ j() }}{{ j() }}")
add("namespace bool set", "{% set ns = namespace() %}{% set ns.flag = true %}{{ ns.flag }}")
add("dict from dict", "{{ dict({'a': 1}) }}")
add("namespace with context", "{% set ns = namespace(x=1) %}{% with y = 2 %}{% set ns.x = y %}{% endwith %}{{ ns.x }}")

# --- misc: round 4 ----------------------------------------------------------------------------
add("deep filter chain", "{{ '  ab  ' | trim | upper | reverse | length }}")
add("filter with block var", "{% set x = 'ab' %}{{ x | upper }}")
add("test with filter arg", "{{ ['a'] | first is eq 'a' }}")
add("getattr chain method", "{{ 'abc'.upper().lower() }}")
add("method on literal", "{{ 5.to_string }}")
add("getitem on undefined error", "{{ missing['k'] }}")
add("slice undefined error", "{{ missing[1:] }}")
add("negative tuple index", "{{ (1,2,3)[-1] }}")
add("empty call parens", "{{ range }}{{ range() is iterable }}")
add("dict access after filter", "{{ {'a': {'b': 'c'}}['a']['b'] }}")
add("concat markup autoescape", "{{ 'a' ~ ('<b>' | safe) }}", autoescape=True)


# ================= edge-case expansion (round 7) =================

# --- filter option combos ---------------------------------------------------
add("sort attr reverse", "{{ users | sort(attribute='age', reverse=true) | map(attribute='n') | join(',') }}",
    {"users": [{"n": "a", "age": 1}, {"n": "b", "age": 3}]})
add("sort strings reverse", "{{ ['b', 'A', 'C'] | sort(reverse=true) | join(',') }}")
add("unique attr case", "{{ users | unique(attribute='g', case_sensitive=true) | map(attribute='g') | join(',') }}",
    {"users": [{"g": "a"}, {"g": "A"}]})
add("min attr reverse n/a", "{{ users | min(attribute='age') }} {{ users | max(attribute='age') }}",
    {"users": [{"age": 2}, {"age": 1}]})
add("batch fill string", "{% for row in [1,2,3] | batch(2, 'x') %}[{{ row | join(',') }}]{% endfor %}")
add("slice fill string", "{% for col in [1,2,3] | slice(2, '-') %}[{{ col | join(',') }}]{% endfor %}")
add("map test with arg", "{{ ['a', 'b', 'c'] | select('in', 'abc') | join(',') }}")
add("truncate width one", "{{ 'abcdef' | truncate(1, true, '...', 0) }}")
add("truncate exact length", "{{ 'abcde' | truncate(5, true, '...', 0) }}")
add("wordwrap tabs", "{{ 'a\\tb' | wordwrap(3) }}|")
add("wordwrap multiple spaces", "{{ 'a  b' | wordwrap(10) }}|")
add("indent width first false", "{{ 'a\\nb' | indent(2, false) }}|")
add("center even width", "{{ 'ab' | center(5) }}|")
add("filesizeformat 999", "{{ 999 | filesizeformat }} {{ 1000 | filesizeformat(true) }}")
add("filesizeformat huge", "{{ 1.5e15 | filesizeformat }}")
add("replace count zero", "{{ 'aaa' | replace('a', 'b', 0) }}")
add("trim multi chars", "{{ 'xyaxy' | trim('xy') }}")
add("default with false arg", "{{ false | default('d', false) }} {{ none | default('d') }}")
add("sum negative", "{{ [1, -2, 3] | sum }}")
add("abs int min", "{{ -9223372036854775807 | abs }}")

# --- tests and comparisons ----------------------------------------------------
add("test sameas bool", "{{ true is sameas true }} {{ 1 is sameas true }}")
add("test in empty", "{{ 1 is in [] }} {{ none is in [none] }}")
add("test ge le", "{{ 1 is le 1 }} {{ 2 is ge 3 }}")
add("test defined falsy", "{{ false is defined }} {{ none is defined }} {{ 0 is defined }}")
add("test odd negative", "{{ -3 is odd }}")
add("test iterable generator", "{{ [1] | map('string') is iterable }} {{ 5 is iterable }}")
add("test sequence tuple", "{{ (1,) is sequence }} {{ (1,) is mapping }}")
add("compare dict lt", "{{ {'a': 1} < {'a': 2} }}")
add("compare list ge", "{{ [2] >= [1] }}")
add("in with markup", "{{ 'a' in ('<a>' | safe) }}")
add("chain eq ne", "{{ 1 == 1 != 2 }}")

# --- macros: signatures ---------------------------------------------------------
add("macro positional after kwarg", "{% macro m(a, b) %}{{ a }}{{ b }}{% endmacro %}{{ m(b=2, a=1) }}")
add("macro default then positional", "{% macro m(a=1, b=2) %}{{ a }}{{ b }}{% endmacro %}{{ m(9) }}")
add("macro extra positional error", "{% macro m(a) %}{{ a }}{% endmacro %}{{ m(1, 2) }}")
add("macro kwarg named param", "{% macro m(a) %}{{ a }}{% endmacro %}{{ m(a=5) }}")
add("macro varargs with call", "{% macro m() %}{{ varargs | join(',') }}{{ caller() if caller }}{% endmacro %}{{ m(1, 2) }}")
add("macro nested definition order", "{% macro a() %}{{ b() }}{% endmacro %}{% macro b() %}B{% endmacro %}{{ a() }}")
add("caller param shadow", "{% macro m(caller) %}{{ caller }}{% endmacro %}{{ m('x') }}")

# --- inheritance / includes ------------------------------------------------------
add("include same twice", "{% include 'p.html' %}{% include 'p.html' %}", templates={"p.html": "x"})
add("extends empty child block", "{% extends 'base.html' %}{% block b %}{% endblock %}tail", templates={
    "base.html": "S{% block b %}D{% endblock %}E"})
add("nested blocks three deep", "{% extends 'base.html' %}{% block inner %}X{% endblock %}", templates={
    "base.html": "{% block outer %}O({% block inner %}D{% endblock %}){% endblock %}"})
add("block override in nested for", "{% extends 'base.html' %}{% block b %}C{% endblock %}", templates={
    "base.html": "{% for i in [1,2] %}{% block b %}D{% endblock %}{% endfor %}"})
add("import macro calls macro", "{% import 'm.html' as m %}{{ m.outer() }}", templates={
    "m.html": "{% macro inner() %}I{% endmacro %}{% macro outer() %}O{{ inner() }}{% endmacro %}"})
add("from import macro with kwargs", "{% from 'm.html' import g %}{{ g(n='x') }}", templates={
    "m.html": "{% macro g(n) %}hi {{ n }}{% endmacro %}"})
add("child set visible in parent block", "{% extends 'base.html' %}{% set v = 'X' %}{% block b %}{{ v }}{% endblock %}", templates={
    "base.html": "[{% block b %}{% endblock %}]"})

# --- whitespace / lexer -----------------------------------------------------------
add("marker after block name", "{% if true -%} X {%- endif %}")
add("var with comment inside", "{{ 1 # not a comment }}")
add("comment multiline", "a{# c\n d #}b")
add("raw contains block end", "{% raw %}{% endraw2 %}{% endraw %}")
add("raw contains opener", "{% raw %}{{ x }}{% endraw %}")
add("string with percent", "{{ '100%' }}")
add("string with brace", "{{ '{' }} {{ '}' }}")
add("adjacent var tags", "{{ 1 }}{{ 2 }}")
add("tag inside string in expression", "{{ 'x{% if %}' }}")
add("whitespace before eof", "abc  ")
add("only whitespace", "  ")
add("text with tab", "a\\tb")
add("marker on else", "{% if false %}a{% elif false %}b{% else -%}c{% endif %}")
add("double minus marker", "a  {{- - 'x' -}}  b")

# --- arithmetic / numbers ------------------------------------------------------------
add("float string multiply", "{{ 'a' * 2.0 }}")
add("div by bool", "{{ 6 / true }} {{ 6 // false }}")
add("pow bool exp", "{{ 3 ** false }}")
add("negative pow result int", "{{ 2 ** 0 }}")
add("long chain mod", "{{ 17 % 5 % 3 }}")
add("compare chains num", "{{ 1 < 2 == true }}")
add("float eq int neg", "{{ -1.0 == -1 }}")
add("sub bool", "{{ true - false }}")
add("negate float", "{{ -1.5 }} {{ --1.5 }}")
add("paren precedence", "{{ (2 + 3) % 4 * 2 }}")

# --- undefined / errors ------------------------------------------------------------
add("undefined filter with args", "{{ missing | replace('a', 'b') | default('d') }}")
add("undefined getitem default", "{{ missing['k'] | default('d') }}")
add("undefined in loop else", "{% for x in missing %}{{ x }}{% else %}e{% endfor %}")
add("undefined attr in test", "{{ missing.x is defined }}")
add("undefined slice default", "{{ missing[1:2] | default('d') }}")
add("none attr error", "{{ none.upper() }}")
add("int attr error", "{{ (5).missing }}")
add("getitem none", "{{ none['k'] | default('d') }}")
add("bool arithmetic in string", "{{ true ~ false }}")

# --- containers ------------------------------------------------------------------------
add("list append do", "{% set l = [] %}{% do l.append('a') %}{% do l.append('b') %}{{ l | join(',') }}")
add("list pop method", "{{ [1,2,3] | list }}")
add("nested dict getitem attr", "{{ d['a'].b }}", {"d": {"a": {"b": "c"}}})
add("dict with tuple key", "{{ {(1, 2): 'v'} }}")
add("list of dict repr", "{{ [{'a': 1}] }}")
add("string iteration index", "{{ 'ab'[1] }} {{ 'ab' | list | last }}")
add("tuple nested index", "{{ ((1, 2), (3, 4))[1][0] }}")
add("dict length", "{{ {'a': 1, 'b': 2} | length }}")
add("empty dict truthiness", "{% if {} %}a{% else %}b{% endif %} {% if [0] %}c{% endif %}")


# ================= edge-case expansion (round 8) =================

# --- wordwrap / truncate deep options ---------------------------------------
add("wordwrap wrapstring custom", "{{ 'a b c' | wordwrap(4, true, '--') }}")
add("wordwrap single long", "{{ 'abcdef' | wordwrap(3) }}")
add("wordwrap exact fit", "{{ 'ab cd' | wordwrap(5) }}|")
add("wordwrap empty", "{{ '' | wordwrap(5) }}|")
add("truncate false killwords space", "{{ 'a b c d' | truncate(6, false, '~', 0) }}")
add("truncate leeway boundary", "{{ 'abcdefgh' | truncate(5, true, '...', 3) }}")
add("truncate unicode", "{{ 'héllo wörld' | truncate(7, true, '…', 0) }}")

# --- urlencode deep -----------------------------------------------------------
add("urlencode tilde", "{{ '~' | urlencode }}")
add("urlencode parens", "{{ '(a)' | urlencode }}")
add("urlencode apostrophe", "{{ \"'\" | urlencode }}")
add("urlencode star", "{{ '*' | urlencode }}")
add("urlencode exclaim", "{{ '!' | urlencode }}")
add("urlencode dict empty", "{{ {} | urlencode }}|")
add("urlencode bool val", "{{ {'a': true} | urlencode }}")
add("urlencode int val", "{{ {'a': 5} | urlencode }}")

# --- loop edge -----------------------------------------------------------------
add("loop index0 last combo", "{% for i in [1,2] %}{{ loop.index0 }}{{ loop.last }} {% endfor %}")
add("loop revindex0", "{% for i in [1,2,3] %}{{ loop.revindex0 }}{% endfor %}")
add("loop depth recursive triple", "{% for i in data recursive %}{{ loop.depth }}{{ loop(i.c) if i.c }}{% endfor %}",
    {"data": [{"c": [{"c": []}]}]})
add("recursive loop length", "{% for i in [1] recursive %}{{ loop.length }}{{ loop([2]) if false }}{% endfor %}")
add("for filtered with loop", "{% for i in [1,2,3] if i != 2 %}{{ loop.index }}:{{ i }} {% endfor %}")
add("for filtered length", "{% for i in [1,2,3] if i != 2 %}{{ loop.length }}{% endfor %}")
add("nested for with same var", "{% for i in [1,2] %}{% for i in [3] %}{{ i }}{% endfor %}{{ i }}{% endfor %}")
add("for else break via slice", "{% for x in [] %}x{% else %}none{% endfor %}")
add("loop over chars unicode", "{% for c in 'éx' %}{{ c }}{% endfor %}")
add("cycle with undefined args", "{% for i in [1,2] %}{{ loop.cycle(missing, 'b') | default('d') }}{% endfor %}")

# --- macro / caller deep ---------------------------------------------------------
add("macro caller nested two", "{% macro outer() %}O[{{ caller() }}]{% endmacro %}{% call outer() %}i{% endcall %}")
add("macro varargs and kwargs both", "{% macro m() %}{{ varargs | join(',') }}/{{ kwargs | dictsort | join(',') }}{% endmacro %}{{ m(1, x=2) }}")
add("macro default none arg", "{% macro m(a=none) %}{{ a is none }}{% endmacro %}{{ m() }} {{ m(1) }}")
add("macro inside for reuse", "{% for i in [1,2] %}{% macro m() %}M{{ i }}{% endmacro %}{{ m() }}{% endfor %}")
add("call body with loop var", "{% macro m() %}{{ caller() }}{% endmacro %}{% for i in [1] %}{% call m() %}c{{ i }}{% endcall %}{% endfor %}")
add("macro return used in expr", "{% macro m() %}5{% endmacro %}{{ m() + 1 }}")
add("macro empty body", "{% macro m() %}{% endmacro %}[{{ m() }}]")

# --- inheritance deep -------------------------------------------------------------
add("extends with set after block", "{% extends 'base.html' %}{% block b %}B{% endblock %}{% set x = 1 %}", templates={
    "base.html": "{% block b %}{% endblock %}"})
add("include with macro call arg", "{% include 'p.html' %}", {"v": "V"}, templates={
    "p.html": "{{ v | upper }}"})
add("super then text", "{% extends 'base.html' %}{% block b %}a{{ super() }}b{% endblock %}", templates={
    "base.html": "{% block b %}S{% endblock %}"})
add("block self-nesting", "{% block a %}{% block b %}x{% endblock %}{% endblock %}")
add("import within if", "{% if true %}{% import 'm.html' as m %}{{ m.v }}{% endif %}", templates={
    "m.html": "{% set v = 'IV' %}"})
add("include list fallback second", "{% include ['nope.html', 'yes.html'] %}", templates={
    "yes.html": "Y"})

# --- whitespace deep ------------------------------------------------------------------
add("lstrip tabs", "x\n\t{% if true %}y{% endif %}", lstrip_blocks=True)
add("marker no-op plain", "{% set x = 1 %}{{ x }}")
add("marker on include", "a\n  {%- include 'p.html' %}", templates={"p.html": "P"})
add("trim blocks with space after tag", "{% if true %} \nx{% endif %}", trim_blocks=True)
add("marker both on var multiline", "a\n  {{-\n x\n -}}\n  b")
add("raw with minus inside", "{% raw %}a -{% endraw %}")
add("nested markers inherit", "{%- if true %}\n  {%- set x = 1 %}{{ x }}\n{%- endif %}")

# --- numbers deep -----------------------------------------------------------------------
add("float mod int", "{{ 7.5 % 2 }} {{ 7 % 2.5 }}")
add("neg floor float", "{{ -0.5 // 1 }}")
add("pow zero base zero", "{{ 0 ** 0 }} {{ 0 ** 1 }}")
add("div float precision", "{{ 1 / 3 == 0.3333333333333333 }}")
add("big int add chain", "{{ 9223372036854775807 + 9223372036854775807 }}")
add("big int mul overflow", "{{ 9223372036854775807 * 2 }}")
add("int compare big", "{{ 9223372036854775807 > 9223372036854775806 }}")
add("mod chain neg", "{{ -17 % 5 }} {{ 17 % -5 }} {{ -17 % -5 }}")

# --- undefined deep ------------------------------------------------------------------------
add("undefined arithmetic compare", "{{ missing == missing }} {{ missing != 1 }}")
add("undefined concat order", "{{ missing ~ 'a' ~ missing }}")
add("undefined in tuple", "{{ missing in (1, 2) }}")
add("undefined min max", "{{ [missing] | min | default('d') }}")
add("undefined attr chain deep", "{{ a.b.c }}", {"a": {"b": {}}})
add("undefined bool not", "{{ not missing.x }}")
add("undefined tojson nested", "{{ {'k': [missing]} | tojson }}")

# --- misc deep -------------------------------------------------------------------------------
add("dict key int vs bool distinct", "{{ {1: 'a', true: 'b'}[1] }} {{ {1: 'a', true: 'b'}[true] }}")
add("list eq tuple", "{{ [1] == (1,) }} {{ (1,) == [1] }}")
add("concat tuple", "{{ 'a' ~ (1, 2) }}")
add("markup in list repr", "{{ ['<x>'] }}", autoescape=False)
add("filter on tuple", "{{ (1, 2) | sum }} {{ (3, 1) | min }}")
add("sort tuple items", "{{ [(2,), (1,)] | sort | join(',') }}")
add("length of generator via list", "{{ [1,2] | map('string') | list | length }}")
add("test is number bool", "{{ true is number }} {{ true is integer }}")
add("string filter on markup", "{{ ('<x>' | safe) | length }}", autoescape=False)
add("escape length", "{{ '<x>' | escape | length }}")


# ================= edge-case expansion (round 9) =================

# --- string methods deep ---------------------------------------------------
add("str title mixed delims", "{{ \"it's-a_test\".title() }}")
add("str cap title", "{{ 'ABC def'.title() }}")
add("str isalnum unicode", "{{ 'h\u00e9llo'.isalpha() }}")
add("str center odd rem", "{{ 'ab'.center(5, '*') }} {{ 'abc'.center(6, '*') }}")
add("str find empty sub", "{{ 'abc'.find('') }} {{ 'abc'.rfind('') }}")
add("str count negatives", "{{ 'abcabc'.count('b', -4) }}")
add("str ljust neg", "{{ 'a'.ljust(-1) }}|")
add("str split whitespace kinds", "{{ 'a\\t\\nb'.split() | join(',') }}")
add("str strip none found", "{{ 'abc'.strip('z') }}")
add("str removesuffix overlap", "{{ 'aaaa'.removesuffix('aa') }}")
add("str swapcase digits", "{{ 'a1B2'.swapcase() }}")
add("str zfill sign plus", "{{ '+5'.zfill(4) }}")
add("str index error message", "{{ 'abc'.index('z') }}")

# --- urlencode/urlize deep --------------------------------------------------
add("urlencode dict key quote", "{{ {'a\"b': 'c'} | urlencode }}")
add("urlencode dict slash val", "{{ {'a': 'b/c'} | urlencode }}")
add("urlize ftp", "{{ 'ftp://files.com' | urlize }}")
add("urlize email trailing dot", "{{ 'a@b.com.' | urlize }}")
add("urlize www path", "{{ 'www.x.io/path?q=1' | urlize }}")
add("urlize uppercase scheme", "{{ 'HTTP://X.COM' | urlize }}")

# --- filter interactions -------------------------------------------------------
add("select then sort", "{{ [3,1,2] | select('odd') | sort | join(',') }}")
add("map then unique", "{{ ['a','b','a'] | map('upper') | unique | join(',') }}")
add("batch map flatten", "{{ [1,2,3,4] | batch(2) | map('first') | join(',') }}")
add("groupby then map attr", "{% for g in items | groupby('k') %}{{ g.list | map(attribute='v') | join('+') }};{% endfor %}",
    {"items": [{"k": "a", "v": 1}, {"k": "a", "v": 2}]})
add("dictsort then items", "{{ {'b': 1, 'a': 2} | dictsort | map('list') | join(',') }}")
add("first of generator", "{{ [1,2] | select('odd') | first }}")
add("sum of generator", "{{ [1,2,3] | select('odd') | sum }}")
add("join of rejectattr", "{{ users | rejectattr('x') | map(attribute='n') | join(',') }}",
    {"users": [{"n": "a", "x": 1}, {"n": "b"}]})
add("sort of unique", "{{ ['b','a','b'] | unique | sort | join(',') }}")
add("reverse of sort", "{{ [1,3,2] | sort | reverse | join(',') }}")

# --- loops: structure -------------------------------------------------------------
add("for tuple target single", "{% for a, in [(1,)] %}{{ a }}{% endfor %}")
add("nested loop filtering", "{% for a in [1,2] %}{% for b in [1,2] if b != a %}{{ a }}{{ b }} {% endfor %}{% endfor %}")
add("recursive nested deeper", "{% for i in data recursive %}{{ loop.depth }}{{ loop(i.c) if i.c }}{% endfor %}",
    {"data": [{"c": [{"c": [{"c": []}]}]}]})
add("for over range in expr", "{% for i in range(2) | reverse %}{{ i }}{% endfor %}")
add("loop cycle single", "{% for i in [1,2] %}{{ loop.cycle('z') }}{% endfor %}")
add("loop changed types", "{% for x in [1, '1', 1] %}{{ loop.changed(x) }} {% endfor %}")
add("for with attr test on tuple", "{% for a, b in [(1, 2)] if a == 1 %}{{ b }}{% endfor %}")

# --- inheritance: scope edges ------------------------------------------------------
add("super inside include", "{% extends 'base.html' %}{% block b %}{% include 'p.html' %}{% endblock %}", templates={
    "base.html": "{% block b %}B{% endblock %}",
    "p.html": "{{ super is defined }}"})
add("block var scope from for", "{% extends 'base.html' %}{% block b %}{% for i in [1] %}{{ i }}{% endfor %}{% endblock %}", templates={
    "base.html": "{% block b %}{% endblock %}"})
add("macro in parent used in child block", "{% extends 'base.html' %}{% block b %}{{ gm() }}{% endblock %}", templates={
    "base.html": "{% macro gm() %}G{% endmacro %}{% block b %}{% endblock %}"})
add("import alias then from alias", "{% import 'm.html' as m %}{% from 'm.html' import v as vv %}{{ m.v }}{{ vv }}", templates={
    "m.html": "{% set v = 'V' %}"})
add("include changes nothing after", "{% include 'p.html' %}{{ z | default('d') }}", templates={
    "p.html": "{% set z = 1 %}"})

# --- whitespace: round 6 -----------------------------------------------------------
add("trim blocks lstrip combined tag", "x\n  {% if true %}y{% endif %}\nz", lstrip_blocks=True, trim_blocks=True)
add("marker minus on endif", "{% if true %}\na\n{% endif -%}\nb")
add("var marker between words", "a {{- 'b' -}} c")
add("raw inside for markers", "{% for i in [1] %}{%- raw -%}r{%- endraw -%}{% endfor %}")
add("comment tag no trim", "a\n{# c #}\nb", trim_blocks=False)
add("multiple blank lines", "a\n\n\nb")

# --- numbers: round 6 -----------------------------------------------------------------
add("float division big", "{{ 1e308 / 1e-308 }}")
add("mod large", "{{ 1000000007 % 998244353 }}")
add("pow nested parens", "{{ (2 ** 3) ** 2 }} {{ 2 ** (3 ** 2) }}")
add("compare mixed int float chain", "{{ 1 < 1.5 < 2 }}")
add("neg zero compare", "{{ -0.0 == 0 }} {{ -0.0 < 0 }}")
add("sum mixed int float", "{{ [1, 2.5] | sum }}")
add("abs big", "{{ -1e308 | abs }}")

# --- errors: shapes ----------------------------------------------------------------------
add("undefined call error", "{{ missing() }}")
add("int call error", "{{ (5)() }}")
add("string call error", "{{ 'a'() }}")
add("add list int error", "{{ [1] + 1 }}")
add("compare dict num error", "{{ {'a': 1} < 2 }}")
add("mod string error", "{{ 'a' % 2 }}")
add("unpack dict error", "{% for a, b in {'x': 1} %}{{ a }}{% endfor %}")

# --- misc: round 5 -------------------------------------------------------------------------
add("nested with in for", "{% for i in [1] %}{% with x = i + 1 %}{{ x }}{% endwith %}{% endfor %}")
add("set in with reused after", "{% with x = 1 %}{% set y = x %}{% endwith %}{{ y | default('d') }}")
add("ternary in attr arg", "{{ users | map(attribute='n' if true else 'x') | join(',') }}", {"users": [{"n": "a"}]})
add("filter in subscript", "{{ d['a' | upper] }}", {"d": {"A": "v"}})
add("test in subscript key", "{{ {'a': 1}['a' is string] }}")
add("dict get chain with default", "{{ d.get('zz', 'none') }}", {"d": {"a": 1}})
add("chained method call on filter result", "{{ ' ab '.strip().upper() }}")
add("boolean kwargs truthy", "{{ [1,2] | batch(2, fill_with=0) | first | join(',') }}")
add("long template stress", "{% for i in range(3) %}{% if i % odd %}{{ i }}{% endif %}{% endfor %}")


# ================= edge-case expansion (round 10) =================

# --- string methods: final edges ---------------------------------------------
add("str find max range", "{{ 'aaaa'.find('aa', 0, 3) }} {{ 'aaaa'.rfind('aa') }}")
add("str count end only", "{{ 'abab'.count('ab', 0, 3) }}")
add("str split keep empties", "{{ 'a,,b'.split(',') | join('|') }}")
add("str strip empty chars", "{{ 'abc'.strip('') }}")
add("str title apostrophe", "{{ \"o'brien\".title() }}")
add("str isupper mixed digit", "{{ 'A1'.isupper() }} {{ 'a1'.islower() }}")
add("str partition empty str", "{{ ''.partition('x') | join('|') }}")
add("str expandtabs tabs only", "{{ '\\t\\t'.expandtabs(2) }}|")
add("str zfill width neg", "{{ '5'.zfill(-1) }}")
add("str startswith multi args", "{{ 'abc'.startswith('x') }} {{ 'abc'.endswith('') }}")
add("str casefold already lower", "{{ 'abc'.casefold() }}")
add("str rsplit sep only", "{{ 'a,,b'.rsplit(',') | join('|') }}")

# --- filters: final edges -----------------------------------------------------
add("unique all same", "{{ [1,1,1] | unique | join(',') }}")
add("sort empty attr", "{{ [] | sort(attribute='x') | length }}")
add("min max single", "{{ [5] | min }} {{ [5] | max }}")
add("batch equal size", "{% for r in [1,2] | batch(2) %}[{{ r | join(',') }}]{% endfor %}")
add("slice more than items", "{% for c in [1] | slice(5) %}[{{ c | join(',') }}]{% endfor %}")
add("map attribute on tuple", "{{ [(1, 'a')] | map(attribute='0') | join(',') }}")
add("selectattr false attr", "{{ users | selectattr('ok') | length }}", {"users": [{"ok" : False}]})
add("groupby empty", "{% for g in [] | groupby('k') %}x{% endfor %}|")
add("join markup sep", "{{ ['a'] | join('<b>') }}", autoescape=False)
add("tojson deep indent", "{{ {'a': {'b': {'c': 1}}} | tojson(indent=4) }}")
add("trim only end chars", "{{ 'xxax' | trim('x') }}")
add("striptags comment", "{{ 'a<!-- c -->b' | striptags }}")
add("striptags br", "{{ 'a<br/>b' | striptags }}")
add("wordcount unicode", "{{ 'h\u00e9llo w' | wordcount }}")
add("filesizeformat float", "{{ 1536.0 | filesizeformat }}")
add("urlencode dict multi", "{{ {'a': 1, 'b': 2} | urlencode }}")
add("center negative width", "{{ 'ab' | center(-1) }}")
add("indent negative", "{{ 'a\\nb' | indent(-1) }}|")

# --- tests: final ---------------------------------------------------------------
add("test in nested list", "{{ [1] is in [[1]] }} {{ 1 is in [[1]] }}")
add("test eq containers", "{{ [1] is eq [1] }} {{ (1,) is eq [1] }}")
add("test divisibleby float", "{{ 4.0 is divisibleby 2 }}")
add("test even float", "{{ 2.0 is even }}")
add("test mapping tuple", "{{ (1,) is mapping }}")
add("test defined on method", "{{ 'a'.upper is defined }}")
add("test sameas tuple", "{{ (1,) is sameas (1,) }}")
add("test ne containers", "{{ {'a': 1} is ne {'b': 2} }}")

# --- loops: final -----------------------------------------------------------------
add("loop index in recursive leaf", "{% for i in data recursive %}{{ loop.index }}{{ loop(i.c) if i.c }}{% endfor %}",
    {"data": [{"c": [{"c": []}]}]})
add("for else filtered nonzero", "{% for x in [1,2] if false %}x{% else %}e{% endfor %}")
add("loop variable leak check", "{% for i in [1] %}{% endfor %}{{ i | default('d') }}")
add("loop cycle kwargs", "{% for i in [1,2] %}{{ loop.cycle('a', 'b') }}{% endfor %}")
add("for unpack string", "{% for a, b in ['ab'] %}{{ a }}{{ b }}{% endfor %}")
add("deep nested for three", "{% for a in [1] %}{% for b in [2] %}{% for c in [3] %}{{ a }}{{ b }}{{ c }}{% endfor %}{% endfor %}{% endfor %}")

# --- macros / call: final -----------------------------------------------------------
add("macro arg default references param", "{% macro m(a, b=a ~ 'x') %}{{ b }}{% endmacro %}{{ m('v') }} {{ m('v', 'w') }}")
add("macro calls varargs join", "{% macro m() %}{{ varargs | join('-') }}{% endmacro %}{{ m('a', 'b') }}")
add("caller with args from macro", "{% macro m(v) %}{{ caller(v) }}{% endmacro %}{% call m(x) %}[{{ x }}]{% endcall %}")
add("macro self reference name", "{% macro fact(n) %}{{ n if n < 2 else n * fact(n - 1) }}{% endmacro %}{{ fact(4) }}")
add("nested macro closures", "{% macro outer(x) %}{% macro inner(y) %}{{ x }}{{ y }}{% endmacro %}{{ inner(2) }}{% endmacro %}{{ outer(1) }}")

# --- whitespace: final -----------------------------------------------------------------
add("lstrip with marker only tag", "x\n  {%- if true %}y{% endif %}", lstrip_blocks=True)
add("trim inside nested if", "{% if true %}\n{% if true %}\nx\n{% endif %}\n{% endif %}", trim_blocks=True)
add("marker on endfor", "{% for i in [1] %}\na\n{% endfor -%}\nb")
add("spaces around markers", "a  {{- 'b' -}}  c  {%- if true -%} d {%- endif -%}  e")

# --- numbers: final ----------------------------------------------------------------------
add("float nan compare", "{{ 1 / 0 == 1 / 0 }}")
add("inf add", "{{ 1e308 + 1e308 }}")
add("neg inf", "{{ -1e308 * 10 }}")
add("big pow two", "{{ 2 ** 63 }}")
add("mod neg float result", "{{ -5.5 % 2 }}")
add("floor big", "{{ (1e15 + 0.5) | round(0) }}")
add("sum big chain", "{{ [9223372036854775807, 9223372036854775807, 1] | sum }}")

# --- errors: final -------------------------------------------------------------------------
add("deep undefined chain error", "{{ a.b.c.d }}", {"a": {}})
add("filter on int error", "{{ 5 | upper }}")
add("test on undefined error", "{{ missing is eq 1 }}")
add("slice str step float", "{{ 'abc'[::1.5] }}")
add("call int attr", "{{ (5).foo() }}")
add("joiner in nested loop", "{% for a in [1] %}{% for b in [1,2] %}{% set j = joiner(',') %}{{ j() }}{{ b }}{% endfor %}{% endfor %}")

# --- misc: final ----------------------------------------------------------------------------
add("deep concat markup", "{{ ('<a>' | safe) ~ ('<b>' | safe) }}", autoescape=True)
add("markup in tuple", "{{ ('<x>' | safe, 'y') }}", autoescape=True)
add("nested filter block", "{% filter upper %}{% filter lower %}AB{% endfilter %}{% endfilter %}")
add("set block with markup", "{% set x %}<b>{% endset %}{{ x }}{{ x | length }}", autoescape=True)
add("ternary with filters", "{{ ('ab' | upper) if true else ('cd' | lower) }}")
add("comment inside expression", "{{ 'a' ~ # x }}")
add("dict method call chain", "{{ {'a': 'x'}.get('b', 'd').upper() }}")
add("long attribute chain method", "{{ 'ab'.upper().lower().upper() }}")
add("filter with expression arg", "{{ 'abc' | replace('a', 'b' | upper) }}")
add("nested dict literal key expr", "{{ {('a' | upper): 1} }}")


# ================= edge-case expansion (round 11) =================

# --- filters: untouched option combos ---------------------------------------
add("truncate all defaults", "{{ 'abcdefghij' | truncate }}")
add("truncate killwords only", "{{ 'abcdefgh' | truncate(5, true) }}")
add("wordwrap break true pos", "{{ 'aaaa bb' | wordwrap(3, true) }}")
add("indent first kwarg", "{{ 'a\\nb' | indent(first=true) }}|")
add("indent blank kwarg", "{{ 'a\\n\\nb' | indent(2, blank=true) }}|")
add("trim chars kwarg", "{{ 'xxaxx' | trim(chars='x') }}")
add("replace kwargs", "{{ 'aaa' | replace(old='a', new='b') }}")
add("int base kwarg", "{{ '10' | int(base=2) }}")
add("round method kwarg", "{{ 2.5 | round(method='ceil') }} {{ 2.5 | round(method='floor') }}")
add("filesizeformat binary kwarg", "{{ 1024 | filesizeformat(binary=true) }}")
add("dictsort by kwarg", "{{ {'a': 2, 'b': 1} | dictsort(by='value') | map('first') | join(',') }}")
add("unique attr kwarg", "{{ users | unique(attribute='g') | length }}", {"users": [{"g": 1}, {"g": 1}]})
add("sum start kwarg", "{{ [1] | sum(start='x') }}")
add("join d kwarg", "{{ [1,2] | join(d='-') }}")
add("default boolean kwarg", "{{ false | default('d', boolean=true) }}")
add("tojson indent kwarg", "{{ [1] | tojson(indent=1) }}")
add("sort attribute kwarg", "{{ users | sort(attribute='n') | map(attribute='n') | join(',') }}", {"users": [{"n": "b"}, {"n": "a"}]})
add("min case_sensitive kwarg", "{{ ['B', 'a'] | min }} {{ ['B', 'a'] | max }}")

# --- string methods: option combos --------------------------------------------
add("str count end clip", "{{ 'ababab'.count('ab', 2, 5) }}")
add("str rfind end clip", "{{ 'ababab'.rfind('ba', 0, 4) }}")
add("str find whole range", "{{ 'abc'.find('c', 0, 3) }}")
add("str rjust exact", "{{ 'abc'.rjust(3, '0') }}|")
add("str ljust fill multi", "{{ 'a'.ljust(4, 'xy') }}")
add("str center fill multi", "{{ 'a'.center(4, 'xy') }}")
add("str zfill large", "{{ '1'.zfill(10) }}")
add("str split max neg", "{{ 'a,b,c'.split(',', -1) | join('|') }}")
add("str rsplit max neg", "{{ 'a,b,c'.rsplit(',', -1) | join('|') }}")
add("str strip mixed args", "{{ 'aaXbb'.strip('ab') }}")
add("str removesuffix all", "{{ 'xx'.removesuffix('xx') }}|")
add("str replace same str", "{{ 'aa'.replace('aa', 'b') }}")

# --- comparisons and logic deep ---------------------------------------------------
add("and returns right value", "{{ 5 and 'x' }} {{ none and 'x' }}")
add("or returns first truthy", "{{ 'a' or 'b' }} {{ '' or 'b' }} {{ 0 or 1 }}")
add("not chain values", "{{ not 0 }} {{ not [] }} {{ not 'a' }}")
add("compare tuple list error", "{{ (1,) < [1] }}")
add("eq dict order irrelevant", "{{ {'a': 1, 'b': 2} == {'b': 2, 'a': 1} }}")
add("eq nested containers", "{{ {'a': [1, {'b': 2}]} == {'a': [1, {'b': 2}]} }}")
add("eq markup string", "{{ ('x' | safe) == 'x' }}", autoescape=False)

# --- loop edge: round 4 -------------------------------------------------------------
add("loop over dict items order", "{% for k in {'b': 1, 'a': 2} %}{{ k }}{% endfor %}")
add("for with recursive flag no use", "{% for i in [1,2] recursive %}{{ i }}{% endfor %}")
add("loop.length constant", "{% for i in [1,2,3] %}{{ loop.length }}-{% endfor %}")
add("nested recursive depth", "{% for i in data recursive %}{{ loop.depth }}{{ loop(i.c) if i.c }}{% endfor %}",
    {"data": [{"c": [{"c": [{"c": []}]}]}]})
add("loop cycle two same", "{% for i in [1,2,3] %}{{ loop.cycle('x', 'x') }}{% endfor %}")
add("for unpack deeper error", "{% for (a, b), c in [[(1, 2), 3, 4]] %}{{ a }}{% endfor %}")
add("loop previtem in filtered", "{% for x in [1,2,3] if x != 2 %}{{ loop.previtem | default('-') }}{% endfor %}")
add("loop last with filter", "{% for x in [1,2,3] if x != 1 %}{{ loop.last }}{% endfor %}")

# --- inheritance: round 6 ------------------------------------------------------------
add("extends var in grandparent", "{% extends 'mid.html' %}{% block b %}{{ v | default('d') }}{% endblock %}", templates={
    "base.html": "{% set v = 'BV' %}{% block b %}{% endblock %}",
    "mid.html": "{% extends 'base.html' %}"})
add("include inside macro", "{% macro m() %}{% include 'p.html' %}{% endmacro %}{{ m() }}", templates={
    "p.html": "P"})
add("import with context macro", "{% set g = 'G' %}{% import 'm.html' as m with context %}{{ m.h() }}", templates={
    "m.html": "{% macro h() %}{{ g | default('none') }}{% endmacro %}"})
add("block in loop child override", "{% extends 'base.html' %}{% block b %}C{% endblock %}", templates={
    "base.html": "{% for i in [1,2] %}{% block b %}D{% endblock %}{% endfor %}"})
add("from import same name twice", "{% from 'm.html' import v, v %}{{ v }}", templates={
    "m.html": "{% set v = 'V' %}"})
add("three includes", "{% include 'a.html' %}{% include 'b.html' %}{% include 'c.html' %}", templates={
    "a.html": "A", "b.html": "B", "c.html": "C"})

# --- whitespace: round 7 ----------------------------------------------------------------
add("marker on import", "x\n  {%- import 'm.html' as m %}{{ m.v }}", templates={
    "m.html": "{% set v = 'V' %}"})
add("lstrip only whitespace line", "x\n   \n{% if true %}y{% endif %}", lstrip_blocks=True)
add("trim with comment only line", "a\n{# x #}\n{# y #}\nb", trim_blocks=True)
add("marker on for else", "{% for x in [] %}x{% else -%}e{% endfor %}")
add("var markers no spaces", "{{- 'a' -}}")

# --- numbers: round 7 --------------------------------------------------------------------
add("pow negative base frac exp", "{{ (-8) ** (1/3) != 0 }}")
add("float int floor div", "{{ 7.5 // 2 }} {{ -7.5 // 2 }}")
add("mod float negative div", "{{ -7.5 % -2 }}")
add("compare bool strings", "{{ true < 'a' }}")
add("arithmetic chain parens", "{{ ((1 + 2) * (3 + 4)) / 7 }}")
add("unary nested minus", "{{ -(-(-1)) }}")
add("big add negative", "{{ -9223372036854775807 - 2 }}")
add("big mul three", "{{ 9223372036854775807 * 3 }}")

# --- undefined / errors: round 3 ------------------------------------------------------------
add("undefined nested loop both", "{% for a in [missing] %}{% for b in missing %}x{% endfor %}{{ a | default('d') }}{% endfor %}")
add("undefined arithmetic div", "{{ missing / 2 }}")
add("undefined floor div", "{{ missing // 2 }}")
add("undefined mod", "{{ missing % 2 }}")
add("undefined pow", "{{ missing ** 2 }}")
add("undefined unary minus", "{{ -missing }}")
add("undefined getitem call", "{{ missing['k'](1) }}")
add("int undefined compare", "{{ missing == 0 }} {{ missing < 1 }}")
add("none vs undefined in dict key", "{{ {none: 'a'}[none] }} {{ {missing: 'a'}[missing] }}")

# --- misc: round 6 -----------------------------------------------------------------------------
add("set markup upper autoescape", "{% set x %}<b>{% endset %}{{ x | upper }}", autoescape=True)
add("filter chain on tuple", "{{ (1, 2) | reverse | first }}")
add("method on filter result list", "{{ [3,1] | sort | first }}")
add("expression dict key with filter", "{{ d[(1 | string)] }}", {"d": {"1": "v"}})
add("nested ternary in arg", "{{ [1,2] | join('a' if true else 'b') }}")
add("deep method chain string", "{{ 'a b'.split()[0].upper() }}")
add("test arg with parens", "{{ 4 is divisibleby (2) }}")
add("multiline expression in var", "{{\n 1 +\n 2\n}}")


# ================= edge-case expansion (round 12) =================

# --- filter kwarg coverage round 2 ------------------------------------------
add("map default pos kwarg mix", "{{ users | map(attribute='a', 'x') | join(',') }}", {"users": [{"a": 1}]})
add("batch zero", "{{ [1] | batch(0) | length }}")
add("slice one", "{% for c in [1,2] | slice(1) %}[{{ c | join(',') }}]{% endfor %}")
add("truncate zero end", "{{ 'abcd' | truncate(2, true, '', 0) }}")
add("wordwrap width exact", "{{ 'ab cd' | wordwrap(5) }}|")
add("round prec bool", "{{ 1.6 | round(precision=0) }}")
add("filesizeformat base2 kwarg", "{{ 2048 | filesizeformat(true) }} {{ 2048 | filesizeformat(false) }}")
add("urlencode for_qs kwarg", "{{ {'a': 'b/c'} | urlencode(for_qs=true) }}")
add("default boolean pos", "{{ 0 | default('d', true) }} {{ '' | default('d', true) }}")
add("indent width kwarg", "{{ 'a\\nb' | indent(width=1, first=true) }}|")
add("int default kwarg", "{{ 'zz' | int(default=3) }}")
add("float default kwarg", "{{ 'zz' | float(default=1.5) }}")

# --- loop / recursive edge ------------------------------------------------------
add("recursive loop index reset", "{% for i in data recursive %}{{ loop.index }}{{ loop(i.c) if i.c }}{% endfor %}",
    {"data": [{"c": [{"c": []}]}, {"c": []}]})
add("loop depth after recursive call", "{% for i in data recursive %}{{ loop.depth }}{% for j in i.c %}{{ loop.depth }}{% endfor %}{% endfor %}",
    {"data": [{"c": [{}]}]})
add("for over generator with test", "{% for x in [1,2,3] | select('odd') %}{{ x }}{% endfor %}")
add("loop cycle arg mismatch", "{% for i in [1] %}{{ loop.cycle() }}{% endfor %}")
add("loop changed no args", "{% for i in [1] %}{{ loop.changed() }}{% endfor %}")

# --- macro/caller edge: round 3 ---------------------------------------------------
add("macro default undefined expr", "{% macro m(a=missing | default('d')) %}{{ a }}{% endmacro %}{{ m() }}")
add("macro kwargs merge order", "{% macro m(a, b) %}{{ a }}{{ b }}{% endmacro %}{{ m(1, b=2) }}")
add("macro varargs spread call", "{% macro m(a, b) %}{{ a }}{{ b }}{% endmacro %}{{ m(*[1, 2]) }}")
add("caller inside caller", "{% macro outer() %}{{ caller() }}{% endmacro %}{% call outer() %}x{% endcall %}")
add("macro defined in loop scope", "{% for i in [1,2] %}{% if i == 1 %}{% macro m() %}M1{% endmacro %}{% endif %}{{ m() }}{% endfor %}")

# --- inheritance: round 7 ------------------------------------------------------------
add("extends after content error", "x{% extends 'base.html' %}", templates={"base.html": "{% block b %}B{% endblock %}"})
add("block required empty ok", "{% extends 'base.html' %}{% block b required %}{% endblock %}", templates={
    "base.html": "{% block b %}D{% endblock %}"})
add("include recursive self safe", "{% include 'a.html' %}", templates={"a.html": "A{% set stop = true %}"})
add("child block without parent block", "{% extends 'base.html' %}{% block other %}O{% endblock %}", templates={
    "base.html": "B"})
add("super in second block", "{% extends 'base.html' %}{% block a %}{{ super() }}{% endblock %}{% block b %}{{ super() }}{% endblock %}", templates={
    "base.html": "{% block a %}A{% endblock %}{% block b %}B{% endblock %}"})

# --- whitespace: round 8 ----------------------------------------------------------------
add("marker on endif nested", "{% if true %}a\n{%- endif %}b")
add("lstrip marker plus", "x\n  {%+ if true %}y{% endif %}", lstrip_blocks=True)
add("trim after var tag", "{{ 'x' }}\ny", trim_blocks=True)
add("marker in nested blocks", "{% if true -%}\n{% for i in [1] -%}\n{{ i }}\n{%- endfor %}\n{%- endif %}")

# --- numbers / operators: round 8 ----------------------------------------------------------
add("pow right assoc check", "{{ 2 ** 2 ** 3 }}")
add("float eq bool", "{{ 1.0 == true }} {{ 0.0 == false }}")
add("neg zero equal", "{{ -0 == 0 }} {{ -0.0 == 0.0 }}")
add("div negative float", "{{ -7 / 2 }}")
add("mod zero float", "{{ 1 % 0.0 }}")
add("comparison mixed tuple", "{{ (1,) < (2,) }} {{ (2,) < (1,) }}")
add("in on markup", "{{ 'a' in ('abc' | safe) }}")

# --- errors: round 4 -------------------------------------------------------------------------
add("unknown filter error", "{{ 1 | nosuchfilter }}")
add("unknown test error", "{{ 1 is nosuchtest }}")
add("unknown global error", "{{ nosuchglobal() }}")
add("include missing no ignore", "{% include 'nope.html' %}")
add("import missing error", "{% import 'nope.html' as m %}")
add("div by zero error", "{{ 1 / 0 }}")
add("mod by zero error", "{{ 1 % 0 }}")

# --- misc: round 7 ------------------------------------------------------------------------------
add("self reference in set", "{% set x = 1 %}{% set x = x + 1 %}{{ x }}")
add("dict in dict in list repr", "{{ [{'a': {'b': [1]}}] }}")
add("markup concat in tuple", "{{ ('<a>' | safe) ~ ('<b>' | safe) }}", autoescape=True)
add("nested filter args with filters", "{{ 'aXb' | replace('X', 'y' | upper) }}")
add("deep ternary chain", "{{ 'a' if false else 'b' if false else 'c' }}")
add("loop var name shadow global", "{% set loop = 'x' %}{{ loop | default('d') }}")
add("macro name reuse across blocks", "{% block a %}{% macro m() %}M{% endmacro %}{{ m() }}{% endblock %}{% block b %}{% macro m() %}N{% endmacro %}{{ m() }}{% endblock %}")


# ================= edge-case expansion (round 13) =================

# --- filters: less common ones ------------------------------------------------
add("pprint", "{{ {'a': 1} | pprint }}")
add("format dict access", "{{ '%s' | format(d) }}", {"d": {"a": 1}})
add("attr filter", "{{ users | attr('n') | join(',') }}", {"users": [{"n": "a"}]})
add("map attribute int", "{{ [(1, 'a')] | map(attribute=1) | join(',') }}")
add("batch attr", "{% for r in users | batch(2, {'n': 'x'}) %}[{{ r | map(attribute='n') | join(',') }}]{% endfor %}",
    {"users": [{"n": "a"}, {"n": "b"}, {"n": "c"}]})
add("slice attr", "{% for c in users | slice(2) | map('map', ...) %}x{% endfor %}", {"users": []})
add("tojson sorted deep", "{{ {'b': {'d': 1, 'c': 2}} | tojson }}")
add("wordcount punctuation", "{{ 'a, b. c?' | wordcount }}")
add("title with newlines", "{{ 'a\nb c' | title }}")
add("urlencode empty string", "{{ '' | urlencode }}|")
add("escape empty", "{{ '' | escape }}|")
add("capitalize whitespace", "{{ ' a' | capitalize }}")
add("trim numbers", "{{ 5 | trim }}")
add("striptags entities numeric", "{{ 'a&#65;b' | striptags }}")
add("indent none arg", "{{ 'a\\nb' | indent(none) }}|")

# --- string methods: rounding out ------------------------------------------------
add("str find on empty", "{{ ''.find('a') }} {{ ''.rfind('a') }}")
add("str split no args", "{{ ' a  b '.split() | join(',') }}")
add("str title single", "{{ 'a'.title() }}")
add("str isdigit unicode digit", "{{ '\\u0660'.isdigit() }}")
add("str swapcase empty", "{{ ''.swapcase() }}|")
add("str ljust default fill", "{{ 'a'.ljust(3) }}|")
add("str center default fill", "{{ 'a'.center(3) }}|")
add("str count case", "{{ 'aAa'.count('a') }}")
add("str removeprefix empty", "{{ 'ab'.removeprefix('') }}")
add("str partition single", "{{ 'ab'.partition('ab') | join('|') }}")

# --- loop: round 5 ------------------------------------------------------------------
add("recursive through loop callable", "{% for i in data recursive %}[{{ i.v }}{{ loop(i.c | default([])) }}]{% endfor %}",
    {"data": [{"v": "a", "c": [{"v": "b", "c": []}]}]})
add("loop.index0 recursion", "{% for i in data recursive %}{{ loop.index0 }}{{ loop(i.c | default([])) }}{% endfor %}",
    {"data": [{"c": [{"c": []}]}]})
add("for filtered all out", "{% for x in [1,2] if x > 5 %}x{% else %}e{% endfor %}")
add("loop.revindex filtered", "{% for x in [1,2,3] if x != 2 %}{{ loop.revindex }}{% endfor %}")
add("for over zip-like pairs", "{% for a, b in [[1,2],[3,4]] %}{{ a }}-{{ b }};{% endfor %}")
add("loop depth in non-recursive nested recursive", "{% for a in data recursive %}{{ loop.depth }}{% for b in a.c | default([]) %}{{ loop.depth }}{% endfor %}{% endfor %}",
    {"data": [{"c": [{}]}]})

# --- inheritance: round 8 -------------------------------------------------------------
add("super with context var", "{% extends 'base.html' %}{% block b %}{{ super() }}{{ v }}{% endblock %}", {"v": "V"}, templates={
    "base.html": "{% block b %}B{% endblock %}"})
add("block in if in parent", "{% extends 'base.html' %}{% block b %}C{% endblock %}", templates={
    "base.html": "{% if true %}{% block b %}D{% endblock %}{% endif %}"})
add("import in included template", "{% include 'p.html' %}", templates={
    "p.html": "{% import 'm.html' as m %}{{ m.v }}",
    "m.html": "{% set v = 'IV' %}"})
add("nested extends with blocks in both", "{% extends 'mid.html' %}{% block a %}CA{% endblock %}{% block b %}CB{% endblock %}", templates={
    "base.html": "{% block a %}BA{% endblock %}-{% block b %}BB{% endblock %}",
    "mid.html": "{% extends 'base.html' %}{% block a %}MA({{ super() }}){% endblock %}"})

# --- whitespace: round 9 ------------------------------------------------------------------
add("marker on elif chain", "{% if false %}a\n{%- elif true -%}\nb\n{%- endif %}")
add("lstrip deep nested", "{% for i in [1] %}\n  {% if true %}\n    x\n  {% endif %}\n{% endfor %}", lstrip_blocks=True, trim_blocks=True)
add("trim between markers", "a\n{{- 'x' }}\n{{- 'y' -}}\nz")
add("raw around markers", "{% raw -%}\nX\n{%- endraw %}")

# --- numbers: round 9 ------------------------------------------------------------------------
add("float tiny repr", "{{ 1e-7 }} {{ 1.5e-10 }}")
add("big int compare float", "{{ 9223372036854775807 == 9223372036854775807.0 }}")
add("neg pow int result", "{{ (-2) ** 3 }}")
add("mod float precision", "{{ 5.5 % 2.0 }}")
add("int div round toward zero", "{{ -7 // 2 }} {{ int(-7 / 2) }}")
add("sum bools floats", "{{ [true, 1.5] | sum }}")

# --- undefined: round 4 -----------------------------------------------------------------------
add("undefined default nested", "{{ missing.a | default(missing.b) | default('d') }}")
add("undefined in arithmetic guarded", "{{ (missing + 1) if missing is defined else 'ok' }}")
add("undefined iteration in comprehension style", "{{ [missing] | join(',') }}")
add("undefined attr of none", "{{ none.a | default('d') }}")
add("undefined dict access default", "{{ d[missing] | default('d') }}", {"d": {"a": 1}})

# --- misc: round 8 -------------------------------------------------------------------------------
add("filter block with kwargs", "{% filter indent(2, true) %}a\\nb{% endfilter %}|")
add("set tuple unpack", "{% set a, b = (1, 2) %}{{ a }}{{ b }}")
add("set from filter chain", "{% set x = ' a ' | trim | upper %}{{ x }}")
add("nested macro in macro call", "{% macro outer(fn) %}{{ fn() }}{% endmacro %}{% macro inner() %}I{% endmacro %}{{ outer(inner) }}")
add("method chain on tuple", "{{ (1, 2) | join('+') }}")
add("expression in dict value", "{{ {'k': 1 + 2} }}")
add("boolean keys tojson", "{{ {true: 1, false: 0} | tojson }}")
add("multiline string in template", "{{ 'a' }}")
add("deeply nested parens", "{{ ((1)) }} {{ ((( 'x' ))) }}")


# ================= edge-case expansion (round 14) =================

# --- filter chains with generators -------------------------------------------
add("generator repr guard", "{{ [1] | map('string') | select('string') | join(',') }}")
add("map of map", "{{ [[1],[2]] | map('first') | map('string') | join(',') }}")
add("select of batch", "{{ [1,2,3,4] | batch(2) | select('first') | length }}")
add("groupby of generator", "{% for g in [1,1,2] | map('string') | groupby('x') %}{{ g.grouper }}{% endfor %}")
add("unique then select", "{{ ['a','a','b'] | unique | select('eq', 'a') | join(',') }}")
add("sort of generator", "{{ [3,1] | map('string') | sort | join(',') }}")
add("reverse generator", "{{ [1,2] | map('string') | reverse | join(',') }}")
add("first of reject", "{{ [1,2] | reject('odd') | first }}")
add("sum selectattr chain", "{{ users | selectattr('v') | map(attribute='v') | sum }}",
    {"users": [{"v": 2}, {"v": 3}]})

# --- comparisons: cross-type ----------------------------------------------------
add("eq none vs empty", "{{ none == '' }} {{ none == [] }} {{ none == {} }}")
add("eq undefined containers", "{{ missing == [1] }} {{ [missing] == [none] }}")
add("lt bool int mixed", "{{ true < 2 }} {{ false < true }}")
add("eq tuple nested", "{{ ((1,),) == ((1,),) }}")
add("eq dict tuple key", "{{ {(1,): 'v'} == {(1,): 'v'} }}")
add("ne mixed num str", "{{ 1 != '1' }} {{ none != 0 }}")

# --- loops: recursion stress ------------------------------------------------------
add("recursive sibling order", "{% for i in data recursive %}{{ i.v }}{{ loop(i.c | default([])) }}{% endfor %}",
    {"data": [{"v": "a", "c": [{"v": "b", "c": []}]}, {"v": "c", "c": []}]})
add("recursive loop index after call", "{% for i in data recursive %}{{ loop.index }}{{ loop(i.c | default([])) }};{% endfor %}",
    {"data": [{"c": [{"c": []}]}, {"c": []}]})
add("recursive empty call", "{% for i in data recursive %}{{ loop([]) if false }}{{ i }}{% endfor %}", {"data": [1]})
add("recursive with filter and else", "{% for i in data recursive if i.v != 'x' %}{{ i.v }}{% else %}e{% endfor %}",
    {"data": [{"v": "a"}]})

# --- macros: signatures edge --------------------------------------------------------
add("macro param defaults eval order", "{% macro m(a='x', b=a) %}{{ b }}{% endmacro %}{{ m() }}")
add("macro kwargs override positional", "{% macro m(a) %}{{ a }}{% endmacro %}{{ m(1, a=2) }}")
add("caller with default param", "{% macro m() %}{{ caller('c') }}{% endmacro %}{% call m(x='d') %}{{ x }}{% endcall %}")
add("macro referencing later set", "{% macro m() %}{{ v | default('d') }}{% endmacro %}{{ m() }}{% set v = 1 %}")

# --- inheritance: round 9 --------------------------------------------------------------
add("extends relative depth", "{% extends 'mid.html' %}{% block b %}C{{ super() }}{% endblock %}", templates={
    "base.html": "{% block b %}1{% endblock %}",
    "mid.html": "{% extends 'base.html' %}{% block b %}2{{ super() }}{% endblock %}"})
add("include inside block inside for", "{% extends 'base.html' %}{% block b %}{% for i in [1] %}{% include 'p.html' %}{% endfor %}{% endblock %}", templates={
    "base.html": "{% block b %}{% endblock %}",
    "p.html": "P{{ i }}"})
add("macro imported used in parent block", "{% extends 'base.html' %}{% import 'm.html' as m %}{% block b %}{{ m.g() }}{% endblock %}", templates={
    "base.html": "{% block b %}{% endblock %}",
    "m.html": "{% macro g() %}G{% endmacro %}"})

# --- whitespace: round 10 -----------------------------------------------------------------
add("marker interleave blocks", "{% for i in [1,2] %}{% if i == 1 -%}X{% else -%}Y{% endif -%}{% endfor %}")
add("var marker before comment", "a {{- 'b' }} {# c #} d")
add("lstrip with marker tag", "x\n  {%- set y = 1 %}{{ y }}", lstrip_blocks=True)
add("raw between markers", "{%- raw -%} x {%- endraw -%}")

# --- numbers: round 10 ----------------------------------------------------------------------
add("float pow assoc", "{{ 2.0 ** 3 ** 2 }}")
add("neg int pow neg", "{{ (-2) ** -3 }}")
add("big add float mix", "{{ 9223372036854775807 + 0.5 }}")
add("mod bool negative", "{{ -7 % true }}")
add("chain compare bools", "{{ true == 1 == 1.0 }}")
add("div int float forms", "{{ 6 / 2 }} {{ 6 // 2.0 }} {{ 6.0 // 2 }}")

# --- undefined: round 5 -----------------------------------------------------------------------
add("undefined or undefined", "{{ (missing or other) | default('d') }}")
add("undefined string op", "{{ missing + 'x' | default('d') }}")
add("undefined attr in ternary", "{{ missing.a if missing else 'ok' }}")
add("nested undefined equality", "{{ [missing] == [missing] }}")

# --- misc: round 9 -------------------------------------------------------------------------------
add("set block autoescape upper", "{% set x %}a{% endset %}{{ x | upper }}", autoescape=True)
add("filter block inside for", "{% for i in [1] %}{% filter upper %}a{{ i }}{% endfilter %}{% endfor %}")
add("include output in expression", "{% set x %}{% include 'p.html' %}{% endset %}{{ x | upper }}", templates={
    "p.html": "p"})
add("multiline dict literal", "{{ {\n 'a': 1,\n 'b': 2\n} | dictsort | join(',') }}")
add("chained comparisons on results", "{{ [2,1] | sort | first == 1 }}")
add("kwarg with expression value", "{{ 'ab' | truncate(length=2 + 1, killwords=true) }}")
add("tuple in dict value", "{{ {'t': (1, 2)} }}")
add("method on int literal error", "{{ (1).bit_length() }}")


# ================= edge-case expansion (round 15) =================

# --- filter chains: deeper ------------------------------------------------------
add("map reject map", "{{ users | map(attribute='n') | reject('eq', 'b') | join(',') }}",
    {"users": [{"n": "a"}, {"n": "b"}, {"n": "c"}]})
add("batch of strings", "{% for r in 'abcd' | batch(2) %}[{{ r | join }}]{% endfor %}")
add("groupby attr then join list", "{% for g in items | groupby('k') %}{{ g.list | map(attribute='v') | join('|') }};{% endfor %}",
    {"items": [{"k": 1, "v": "a"}, {"k": 1, "v": "b"}]})
add("select on string", "{{ 'abc' | select('in', 'ac') | join(',') }}")
add("min of generator", "{{ [2,1,3] | map('float') | min }}")
add("unique of tuples", "{{ [(1,), (1,), (2,)] | unique | length }}")
add("truncate after upper", "{{ 'abcdefgh' | upper | truncate(5, true, '...', 0) }}")
add("indent after join", "{{ ['a', 'b'] | join('\n') | indent(2) }}|")
add("tojson of markup list", "{{ ['<x>'] | tojson }}", autoescape=False)
add("urlencode of none", "{{ none | urlencode }}")

# --- whitespace: round 11 -----------------------------------------------------------
add("marker between nested ifs", "{% if true %}\n {%- if true %}a{% endif %}\n{% endif %}")
add("lstrip after var line", "{{ 1 }}\n   {% if true %}x{% endif %}", lstrip_blocks=True)
add("trim blocks raw", "a\n{% raw %}\nb\n{% endraw %}\nc", trim_blocks=True)
add("marker on with", "a\n  {%- with x = 1 %}{{ x }}{%- endwith %}")

# --- loops: round 6 -------------------------------------------------------------------
add("loop over dict values()", "{% for v in {'a': 1}.values() %}{{ v }}{% endfor %}")
add("loop over dict keys()", "{% for k in {'a': 1}.keys() %}{{ k }}{% endfor %}")
add("loop over dict items()", "{% for k, v in {'a': 1}.items() %}{{ k }}{{ v }}{% endfor %}")
add("recursive loop over empty root", "{% for i in data recursive %}{{ loop(i.c | default([])) }}{% endfor %}", {"data": []})
add("for filter references loop", "{% for x in [1,2,3] if loop.index != 2 %}{{ x }}{% endfor %}")
add("nested for filter outer var", "{% for a in [1,2] %}{% for b in [1,2] if b == a %}{{ a }}{{ b }}{% endfor %}{% endfor %}")

# --- macros: round 4 --------------------------------------------------------------------
add("macro calling imported macro", "{% import 'm.html' as m %}{% macro local() %}L{{ m.g() }}{% endmacro %}{{ local() }}", templates={
    "m.html": "{% macro g() %}G{% endmacro %}"})
add("macro default with kwargs ref", "{% macro m(a, k=kwargs | length) %}{{ a }}{{ k }}{% endmacro %}{{ m(1) }} {{ m(1, x=2) }}")
add("macro nested call body scope", "{% macro m() %}{{ caller() }}{% endmacro %}{% call m() %}{% set x = 1 %}{{ x }}{% endcall %}")
add("macro shadow global function", "{% macro dict(a) %}D{{ a }}{% endmacro %}{{ dict(1) }}|{{ dict(a=2) }}")

# --- inheritance: round 10 ------------------------------------------------------------------
add("block in nested include in block", "{% extends 'base.html' %}{% block b %}{% include 'p.html' %}{% endblock %}", templates={
    "base.html": "{% block b %}{% endblock %}",
    "p.html": "{% block inner %}X{% endblock %}"})
add("import then include same module", "{% import 'm.html' as m %}{% include 'm.html' %}{{ m.v }}", templates={
    "m.html": "{% set v = 'V' %}"})
add("super chain with sets", "{% extends 'mid.html' %}{% block b %}C{{ super() }}{% endblock %}", templates={
    "base.html": "{% set v = 1 %}{% block b %}B{{ v }}{% endblock %}",
    "mid.html": "{% extends 'base.html' %}{% block b %}M({{ super() }}){% endblock %}"})

# --- numbers: round 11 -------------------------------------------------------------------------
add("float equality close", "{{ 0.1 + 0.2 == 0.3 }} {{ (0.1 + 0.2) - 0.3 < 1e-9 }}")
add("int div negative floor", "{{ -1 // 2 }} {{ 1 // -2 }}")
add("pow big negative", "{{ 10 ** -2 }}")
add("float inf compare", "{{ 1e308 * 10 > 1e308 }}")
add("bool arithmetic order", "{{ false + true * 2 }}")
add("long add chain", "{{ 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 }}")

# --- undefined: round 6 ---------------------------------------------------------------------------
add("undefined in filter chain deep", "{{ missing | join(',') | default('d') }}")
add("undefined attr default chain", "{{ missing.a.b | default('x') }}")
add("undefined compared to none", "{{ missing == none }} {{ none == missing }}")
add("undefined with loop var name", "{% for missing in [1] %}{{ missing }}{% endfor %}")

# --- misc: round 10 ----------------------------------------------------------------------------------
add("escape length after markup", "{{ ('<x>' | safe) | escape | length }}", autoescape=False)
add("filter with tuple arg", "{{ 'aXb' | replace('X', ('y' | upper)) }}")
add("dict literal with tuple value access", "{{ {'t': (1, 2)}.t[1] }}")
add("nested attribute assignment namespace", "{% set ns = namespace(a=namespace(b=1)) %}{% set ns.a.b = 2 %}{{ ns.a.b }}")
add("loop in set block", "{% set x %}{% for i in [1,2] %}{{ i }}{% endfor %}{% endset %}{{ x }}")
add("concat in test arg", "{{ 'a' is eq ('a' ~ '') }}")
add("filter in test arg", "{{ 4 is divisibleby (2 | first if false else 2) }}")
add("call expression on filter result", "{{ [1,2] | first.to_s }}")


# ================= edge-case expansion (round 16) =================

# --- generator chains: exhaustiveness -------------------------------------------
add("generator nested twice", "{{ [1,2] | map('string') | map('upper') | join(',') }}")
add("selectattr rejectattr chain", "{{ users | selectattr('v') | rejectattr('v', 'eq', 2) | map(attribute='n') | join(',') }}",
    {"users": [{"n": "a", "v": 1}, {"n": "b", "v": 2}]})
add("groupby then batch", "{% for g in items | groupby('k') %}[{{ g.list | batch(2) | map('join', '-') | join(',') }}]{% endfor %}",
    {"items": [{"k": 1, "v": 1}, {"k": 1, "v": 2}, {"k": 1, "v": 3}]})
add("sort attr on generator", "{{ users | map(attribute='n') | list | sort | join(',') }}", {"users": [{"n": "b"}, {"n": "a"}]})
add("unique generator then first", "{{ ['a','a','b'] | unique | first }}")
add("reverse then sort", "{{ [2,1] | reverse | sort | join(',') }}")

# --- error shape consistency ------------------------------------------------------
add("add undefined error msg", "{{ 1 + missing }}")
add("mul undefined error", "{{ 2 * missing }}")
add("div undefined error", "{{ 1 / missing }}")
add("floor undefined error", "{{ 1 // missing }}")
add("mod undefined error", "{{ 1 % missing }}")
add("pow undefined error", "{{ 2 ** missing }}")
add("compare undefined error", "{{ 1 < missing }}")

# --- loop: deep nesting -----------------------------------------------------------
add("for in if in for", "{% for a in [1] %}{% if true %}{% for b in [2] %}{{ a }}{{ b }}{% endfor %}{% endif %}{% endfor %}")
add("loop vars three deep", "{% for a in [1] %}{% for b in [2] %}{% for c in [3] %}{{ loop.depth }}{% endfor %}{% endfor %}{% endfor %}")
add("recursive deep branches", "{% for i in data recursive %}{{ i.v }}{{ loop(i.c | default([])) }}{% endfor %}",
    {"data": [{"v": "a", "c": [{"v": "b", "c": [{"v": "c", "c": []}, {"v": "d", "c": []}]}]}]})
add("loop cycle inside recursive", "{% for i in data recursive %}{{ loop.cycle('x', 'y') }}{{ loop(i.c | default([])) }}{% endfor %}",
    {"data": [{"c": [{"c": []}]}]})
add("for over range nested expr", "{% for i in range(2) %}{% for j in range(i + 1) %}{{ j }}{% endfor %}{% endfor %}")

# --- macros: round 5 -----------------------------------------------------------------
add("macro kwargs iterate sorted", "{% macro m() %}{% for k, v in kwargs | dictsort %}{{ k }}{{ v }}{% endfor %}{% endmacro %}{{ m(b=2, a=1) }}")
add("macro default references earlier param", "{% macro m(x, y=x ~ '!') %}{{ y }}{% endmacro %}{{ m('a') }}")
add("macro in macro body scope", "{% macro outer() %}{% macro inner() %}I{% endmacro %}{{ inner() }}O{% endmacro %}{{ outer() }}{{ inner is defined }}")

# --- inheritance: round 11 --------------------------------------------------------------
add("block with same name across include", "{% include 'p.html' %}{% block b %}C{% endblock %}", templates={
    "p.html": "{% block b %}P{% endblock %}"})
add("super after include in block", "{% extends 'base.html' %}{% block b %}{% include 'p.html' %}{{ super() }}{% endblock %}", templates={
    "base.html": "{% block b %}B{% endblock %}",
    "p.html": "P"})
add("import inside for", "{% for i in [1] %}{% import 'm.html' as m %}{{ m.v }}{% endfor %}", templates={
    "m.html": "{% set v = 'V' %}"})
add("from import inside block", "{% extends 'base.html' %}{% block b %}{% from 'm.html' import v %}{{ v }}{% endblock %}", templates={
    "base.html": "{% block b %}{% endblock %}",
    "m.html": "{% set v = 'FV' %}"})

# --- whitespace: round 12 -------------------------------------------------------------------
add("trim blocks only newlines", "{% set x = 1 %}\n{{ x }}", trim_blocks=True)
add("lstrip deep chain", "{% if true %}\n  {% for i in [1] %}\n    x\n  {% endfor %}\n{% endif %}", lstrip_blocks=True)
add("markers around else", "{% if false %}a\n{%- else -%}\nb\n{%- endif %}")

# --- numbers: round 12 -------------------------------------------------------------------------
add("float big pow", "{{ 10.0 ** 20 }}")
add("neg mod neg int", "{{ -7 % -3 }}")
add("floor div exact", "{{ 10 // 5 }} {{ -10 // 5 }}")
add("compare inf nan", "{{ 1e308 * 10 > 0 }}")
add("bool chain arith", "{{ true + true + true }}")
add("mixed div chain", "{{ 10 / 4 * 2 }}")

# --- misc: round 11 -------------------------------------------------------------------------------
add("markup through join autoescape", "{{ ['<a>', 'b'] | join('|') }}", autoescape=True)
add("filter on tuple method", "{{ (1, 2) | last }}")
add("dict get numeric", "{{ {1: 'a'}.get(1) }} {{ {1: 'a'}.get(2, 'd') }}")
add("chained getitem attr mix", "{{ d['a'].b[0] }}", {"d": {"a": {"b": [7]}}})
add("set attr on namespace in loop", "{% set ns = namespace(n=0) %}{% for i in [1,2] %}{% set ns.n = ns.n + i %}{% endfor %}{{ ns.n }}")
add("test arg via variable", "{{ 4 is divisibleby d }}", {"d": 2})
add("filter arg via variable", "{{ 'a.b' | replace(sep, '-') }}", {"sep": "."})
add("nested set block render", "{% set x %}a{% set y %}b{% endset %}{% endset %}{{ x }}")
add("comment between var tags", "{{ 1 }}{# c #}{{ 2 }}")


# ================= edge-case expansion (round 17) =================

# --- filter arg shapes ---------------------------------------------------------
add("join sep markup", "{{ ['a', 'b'] | join(sep) }}", {"sep": "-"})
add("sort by variable attr", "{{ users | sort(attribute=attr) | map(attribute='n') | join(',') }}",
    {"users": [{"n": "b", "age": 1}, {"n": "a", "age": 2}], "attr": "age"})
add("truncate via variables", "{{ s | truncate(l, kw, e, lw) }}", {"s": "abcdefgh", "l": 6, "kw": True, "e": "...", "lw": 0})
add("round via variable", "{{ x | round(p) }}", {"x": 1.25, "p": 1})
add("groupby variable attr", "{% for g in items | groupby(k) %}{{ g.grouper }};{% endfor %}",
    {"items": [{"t": "a"}, {"t": "b"}], "k": "t"})
add("map variable filter name", "{{ ['a'] | map(f) | join(',') }}", {"f": "upper"})

# --- string methods: exotic -------------------------------------------------------
add("str title numbers end", "{{ 'a1 1b'.title() }}")
add("str isalpha spaces", "{{ 'a b'.isalpha() }}")
add("str strip newlines only", "{{ 'a\\nb'.strip() }}")
add("str split unicode sep", "{{ 'a\\u00e9b'.split('\\u00e9') | join('-') }}")
add("str find case", "{{ 'Abc'.find('B') }}")
add("str count overlap avoid", "{{ 'aaa'.count('aa') }}")
add("str zfill already wide", "{{ 'abc'.zfill(2) }}")
add("str center same width", "{{ 'abc'.center(3) }}|")
add("str rpartition single char", "{{ 'ab'.rpartition('a') | join('|') }}")

# --- loop: round 7 -----------------------------------------------------------------
add("recursive loop over strings", "{% for i in data recursive %}{{ i }}{{ loop(i) if false }}{% endfor %}", {"data": "ab"})
add("loop.changed with missing", "{% for x in [1] %}{{ loop.changed(missing) }}{% endfor %}")
add("for over dict keys sorted by dictsort", "{% for k, v in d | dictsort %}{{ k }}{{ v }}{% endfor %}", {"d": {"b": 2, "a": 1}})
add("nested loop same target name", "{% for i in [1,2] %}{% for i in [3,4] %}{{ i }}{% endfor %}|{% endfor %}")
add("loop.index in recursive after nested", "{% for a in data recursive %}{{ loop.index }}{% for b in a.c | default([]) %}{{ b }}{% endfor %};{% endfor %}",
    {"data": [{"c": ["x"]}, {"c": []}]})

# --- macros: round 6 ------------------------------------------------------------------
add("macro with default using filter", "{% macro m(a) %}{{ a | upper }}{% endmacro %}{{ m('x') }}")
add("macro param named varargs", "{% macro m(varargs) %}{{ varargs }}{% endmacro %}{{ m('v') }}")
add("macro param named kwargs", "{% macro m(kwargs) %}{{ kwargs }}{% endmacro %}{{ m('k') }}")
add("macro called with none", "{% macro m(a) %}{{ a is none }}{% endmacro %}{{ m(none) }}")
add("macro in set block", "{% set x %}{% macro m() %}M{% endmacro %}{{ m() }}{% endset %}{{ x }}")

# --- inheritance: round 12 ----------------------------------------------------------------
add("extends with dynamic name var", "{% extends t %}{% block b %}C{% endblock %}", {"t": "base.html"}, templates={
    "base.html": "{% block b %}B{% endblock %}"})
add("include with variable name", "{% include t %}", {"t": "p.html"}, templates={"p.html": "P"})
add("import with variable name", "{% import t as m %}{{ m.v }}", {"t": "m.html"}, templates={
    "m.html": "{% set v = 'V' %}"})
add("super usage without extends error", "{% block b %}{{ super() }}{% endblock %}")

# --- whitespace: round 13 --------------------------------------------------------------------
add("marker only tag line", "a\n  {%- set x = 1 %}\nb{{ x }}")
add("trim after comment tag", "a\n{# c #}\nb", trim_blocks=False)
add("lstrip var tag no effect", "x\n  {{ 1 }}", lstrip_blocks=True)
add("markers nested for if", "{% for i in [1] -%}\n {%- if true -%}X{%- endif -%}\n{%- endfor %}")

# --- numbers: round 13 --------------------------------------------------------------------------
add("float pow frac base", "{{ 0.5 ** 2 }}")
add("int overflow check add", "{{ 9223372036854775806 + 1 }}")
add("big compare negative", "{{ -9223372036854775807 - 1 < -9223372036854775807 }}")
add("mixed eq bool float", "{{ false == 0.0 }} {{ true == 1.0 }}")
add("div chain negatives", "{{ -8 / 4 / -1 }}")

# --- misc: round 12 -------------------------------------------------------------------------------
add("nested namespaces", "{% set a = namespace(b=namespace(c=1)) %}{{ a.b.c }}")
add("dict key by variable", "{{ d[k] }}", {"d": {"x": 1}, "k": "x"})
add("tuple index negative", "{{ (1,2,3)[-2] }}")
add("markup compare markup", "{{ ('x' | safe) == ('x' | safe) }}", autoescape=False)
add("filter chain order preserved", "{{ ' a ' | trim | upper | length }}")
add("if with parenthesized or", "{% if (true or false) and true %}y{% endif %}")
add("ternary in default arg", "{{ missing | default('a' if true else 'b') }}")
add("deep nested dicts access", "{{ a.b.c.d.e }}", {"a": {"b": {"c": {"d": {"e": "deep"}}}}})
add("tojson with unicode key", "{{ {'k\u00e9': 1} | tojson }}")


# ================= edge-case expansion (round 18) =================

# --- filter value shapes ----------------------------------------------------------
add("sort dict returns keys", "{{ {'b': 1, 'a': 2} | sort | join(',') }}")
add("unique on string", "{{ 'aba' | unique | join(',') }}")
add("reverse on tuple", "{{ (1, 2) | reverse | join(',') }}")
add("first on generator", "{{ [1,2] | map('string') | first }}")
add("last on generator", "{{ [1,2] | map('string') | last }}")
add("min on string chars", "{{ 'cba' | min }} {{ 'cba' | max }}")
add("sum on tuple", "{{ (1, 2.5) | sum }}")
add("length on range", "{{ range(5) | length }}")
add("list on range", "{{ range(3) | join(',') }}")
add("batch on string", "{% for r in 'abcde' | batch(2, '-') %}[{{ r | join }}]{% endfor %}")
add("slice on string", "{% for c in 'abcd' | slice(3) %}[{{ c | join }}]{% endfor %}")
add("select on tuple", "{{ (1,2,3) | select('even') | join(',') }}")

# --- undefined: exhaustive ops ------------------------------------------------------
add("undefined add rev", "{{ 1 + missing }}")
add("undefined mul rev", "{{ 2 * missing }}")
add("undefined pow rev", "{{ 2 ** missing }}")
add("undefined lt rev", "{{ missing < 1 }}")
add("undefined ge rev", "{{ missing >= 1 }}")
add("undefined in operator", "{{ missing in [1] }} {{ 1 in missing }}")

# --- loop: round 8 --------------------------------------------------------------------
add("loop over empty string", "{% for c in '' %}x{% else %}e{% endfor %}")
add("loop over empty tuple", "{% for x in () %}x{% else %}e{% endfor %}")
add("loop index0 in recursion", "{% for i in data recursive %}{{ loop.index0 }}{{ loop(i.c | default([])) }}{% endfor %}",
    {"data": [{"c": [{"c": []}]}]})
add("recursive with include", "{% for i in [1] recursive %}{% include 'p.html' %}{% endfor %}", templates={
    "p.html": "P{{ loop is defined }}"})
add("for unpack tuple values", "{% for a, b in [(1, 2)] %}{{ a }}{{ b }}{% endfor %}")

# --- macros: round 7 ---------------------------------------------------------------------
add("macro kwargs default collision", "{% macro m(a=1, b=2) %}{{ a }}{{ b }}{% endmacro %}{{ m(b=9) }}")
add("macro positional fill skip", "{% macro m(a, b=2, c=3) %}{{ a }}{{ b }}{{ c }}{% endmacro %}{{ m(1, c=9) }}")
add("caller nested macro call", "{% macro outer() %}{{ caller() }}{% endmacro %}{% macro inner() %}{{ caller() }}{% endmacro %}{% call inner() %}X{% endcall %}{% call outer() %}Y{% endcall %}")

# --- inheritance: round 13 -------------------------------------------------------------------
add("extends then include loop var", "{% extends 'base.html' %}{% block b %}{% for i in [1] %}{% include 'p.html' %}{% endfor %}{% endblock %}", templates={
    "base.html": "{% block b %}{% endblock %}",
    "p.html": "P{{ i }}"})
add("block override with nested blocks", "{% extends 'base.html' %}{% block outer %}O{% block inner %}I{% endblock %}{% endblock %}", templates={
    "base.html": "{% block outer %}[{% block inner %}D{% endblock %}]{% endblock %}"})

# --- whitespace: round 14 -----------------------------------------------------------------------
add("marker after tag name", "{% if true %}x{% endif -%}\ny")
add("var marker with newline before", "a\n{{- 'b' }}")
add("comment marker no strip", "a {#- c -#} b")
add("raw marker right only", "{% raw %}x{% endraw -%}\ny")

# --- numbers: round 14 -----------------------------------------------------------------------------
add("pow chain left", "{{ 3 ** 2 ** 1 }}")
add("neg zero pow", "{{ (-0.0) ** 2 }}")
add("big int to float", "{{ 9223372036854775807 + 0.0 }}")
add("float compare int huge", "{{ 1e18 == 1000000000000000000 }}")
add("mod chain float", "{{ 10.5 % 3 % 2 }}")

# --- misc: round 13 ----------------------------------------------------------------------------------
add("join markup items", "{{ ['<a>', 'b'] | join(',') }}", autoescape=True)
add("escape markup via filter chain", "{{ ('<x>' | safe) | trim | escape }}", autoescape=False)
add("tuple attr access via int", "{{ t[1] }}", {"t": [10, 20]})
add("dict access with int via get", "{{ {1: 'a'}.get(1.0) }}")
add("if with is not in", "{% if 1 is not in [2] %}y{% endif %}")
add("nested ternary chain deep", "{{ 'a' if false else 'b' if true else 'c' }}")
add("set conditional tuple", "{% set x = (1, 2) if true else (3,) %}{{ x }}")
add("deep method chain on literal", "{{ 'x-y'.split('-')[1].upper() }}")
add("loop var in included template target", "{% for n in [1,2] %}{% include 'p.html' %}{% endfor %}", templates={
    "p.html": "{{ n }}"})
add("macro call in dict value", "{% macro m() %}v{% endmacro %}{{ {'k': m()} }}", autoescape=False)

with open(__file__.rsplit("/", 1)[0] + "/cases.json", "w") as f:
    json.dump(cases, f, indent=1)
print(f"wrote {len(cases)} cases")
