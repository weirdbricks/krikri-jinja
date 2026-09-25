import json, random, sys

random.seed(int(sys.argv[1]) if len(sys.argv) > 1 else 42)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 2000

INTS = [0, 1, 2, 3, 7, 10, -1, -5, 100, 255, 1000000, 9223372036854775807, 9223372036854775808, 2**62, -2**62]
FLOATS = [0.0, 1.0, -0.0, 1.5, -2.5, 0.1, 0.5, 100.0, 1e15, 1e-5, 1e20, 3.14159]
STRS = ["", "a", "ab", "abc", "hello world", "a,b,c", "  x  ", "a\tb", "héllo", "<x>", "a.b", "ABC", "2nd"]
FILTERS = [
    ("upper", 0), ("lower", 0), ("trim", 0), ("length", 0), ("first", 0), ("last", 0),
    ("abs", 0), ("int", 0), ("float", 0), ("string", 0), ("list", 0), ("reverse", 0),
    ("title", 0), ("capitalize", 0), ("escape", 0), ("striptags", 0), ("urlencode", 0),
    ("round", 0), ("round", 1), ("indent", 0), ("indent", 1), ("indent", 1),
    ("join", 0), ("join", 1), ("sum", 0), ("min", 0), ("max", 0), ("sort", 0),
    ("unique", 0), ("count", 0), ("wordcount", 0), ("filesizeformat", 0),
    ("truncate", 1), ("truncate", 3), ("center", 1), ("replace", 2), ("split", 1),
    ("default", 1), ("tojson", 0), ("safe", 0), ("trim", 1), ("title", 0), ("slice", 1),
]
TESTS = ["odd", "even", "number", "string", "sequence", "iterable", "mapping", "none",
         "defined", "undefined", "callable", "boolean", "integer", "float"]
BINOPS = ["+", "-", "*", "/", "//", "%", "**", "==", "!=", "<", ">", "<=", ">="]

def lit():
    r = random.random()
    if r < 0.3: return repr(random.choice(INTS))
    if r < 0.5: return repr(random.choice(FLOATS))
    if r < 0.7: return repr(random.choice(STRS))
    if r < 0.75: return random.choice(["true", "false", "none", "True", "False", "None"])
    if r < 0.85:
        n = random.randint(0, 3)
        return "[" + ",".join(lit() for _ in range(n)) + "]"
    if r < 0.92:
        return "{" + ",".join(f"'k{i}':{lit()}" for i in range(random.randint(0, 2))) + "}"
    n = random.randint(0, 3)
    return "(" + ",".join(lit() for _ in range(n)) + ("," if n == 1 else "") + ")"

def var():
    return random.choice(["v", "n", "s", "lst", "d", "missing", "t"])

def atom(depth):
    r = random.random()
    if r < 0.4: return lit()
    if r < 0.6: return var()
    if r < 0.7: return "(" + expr(depth + 1) + ")"
    if r < 0.78: return f"{var()}[{lit()}]" if random.random() < 0.5 else f"{var()}.{random.choice(['a', 'b', 'n'])}"
    if r < 0.86:
        f, na = random.choice(FILTERS)
        args = ",".join(lit() for _ in range(na))
        return (atom(depth + 1) if random.random() < 0.4 else var()) + f"|{f}({args})" if args else (atom(depth + 1) if random.random() < 0.4 else var()) + f"|{f}"
    if r < 0.93:
        t = random.choice(TESTS)
        return (atom(depth + 1) if random.random() < 0.4 else var()) + f" is {t}"
    return f"{var()}.{random.choice(['upper', 'lower', 'title', 'strip'])}()"

def expr(depth=0):
    if depth > 3: return lit()
    r = random.random()
    if r < 0.5:
        return f"{atom(depth)} {random.choice(BINOPS)} {atom(depth)}"
    if r < 0.6:
        return f"({expr(depth+1)} if {atom(depth)} else {atom(depth)})"
    if r < 0.68:
        return f"not {atom(depth)}"
    if r < 0.74:
        return f"{atom(depth)} ~ {atom(depth)}"
    if r < 0.8:
        return f"{atom(depth)} {random.choice(['and', 'or'])} {atom(depth)}"
    return atom(depth)

DATA = {"v": 5, "n": 2.5, "s": "aBc", "lst": [1, 2, 3], "d": {"a": 1, "b": "x"}, "t": (1, "a"), "f": True}

cases = []
for i in range(N):
    kind = random.random()
    if kind < 0.75:
        tmpl = "{{ " + expr() + " }}"
    elif kind < 0.85:
        tmpl = "{% if " + expr() + " %}A{% else %}B{% endif %}"
    elif kind < 0.95:
        tmpl = "{% for x in " + random.choice(["lst", "range(3)", "'ab'", "d", "(1, 2)", "[v, n]"]) + " %}{{ x }},{% endfor %}"
    else:
        tmpl = "{% set x = " + expr() + " %}{{ x }}"
    cases.append({"name": f"fuzz{i}", "template": tmpl, "data": DATA})

out = sys.argv[3] if len(sys.argv) > 3 else "/tmp/krikri-fuzz-cases.json"
json.dump(cases, open(out, "w"))
print(f"wrote {N} fuzz cases")
