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

with open(__file__.rsplit("/", 1)[0] + "/cases.json", "w") as f:
    json.dump(cases, f, indent=1)
print(f"wrote {len(cases)} cases")
