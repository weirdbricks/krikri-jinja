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

with open(__file__.rsplit("/", 1)[0] + "/cases.json", "w") as f:
    json.dump(cases, f, indent=1)
print(f"wrote {len(cases)} cases")
