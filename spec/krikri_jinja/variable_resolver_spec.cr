require "../spec_helper"
require "../../src/krikri_jinja"

private class CountingResolver < KrikriJinja::VariableResolver
  getter requested = [] of String

  def initialize(@values : Hash(String, KrikriJinja::AnyValue))
  end

  def resolve(name : String) : KrikriJinja::AnyValue?
    @requested << name
    @values[name]?
  end
end

describe KrikriJinja::VariableResolver do
  it "supplies only the variables an expression reads" do
    resolver = CountingResolver.new({
      "a"      => KrikriJinja::AnyValue.new(2_i64),
      "unused" => KrikriJinja::AnyValue.new(9_i64),
    })
    engine = KrikriJinja::Engine.new
    node = KrikriJinja.parse_expression("a * 3")

    assert_equal(6_i64, engine.evaluate_parsed(node, resolver: resolver).raw)
    assert_equal(["a"], resolver.requested)
  end

  it "lets explicit variables and template assignments shadow the resolver" do
    resolver = CountingResolver.new({"x" => KrikriJinja::AnyValue.new("resolved")})
    engine = KrikriJinja::Engine.new
    node = KrikriJinja::Parser.parse("{{ x }}|{% set x = 'local' %}{{ x }}|{{ y }}", engine.options)
    variables = {"y" => KrikriJinja::AnyValue.new("given")}

    assert_equal("resolved|local|given", engine.render_parsed(node, variables, resolver))
  end

  it "falls back to globals and then undefined when the resolver has no value" do
    resolver = CountingResolver.new({} of String => KrikriJinja::AnyValue)
    engine = KrikriJinja::Engine.new

    assert_equal(2, engine.evaluate_parsed(KrikriJinja.parse_expression("range(2) | list"), resolver: resolver).raw
      .as(Array).size)
    assert_equal(false, engine.evaluate_parsed(KrikriJinja.parse_expression("missing is defined"), resolver: resolver).raw)
  end
end

describe "KrikriJinja verbatim expression strings" do
  it "keeps backslashes in {{ }} literals but decodes {% %} literals" do
    options = KrikriJinja::LexerOptions.new(verbatim_expression_strings: true)
    engine = KrikriJinja::Engine.new(options: options)
    assert_equal(%q(V\1-\2|4|a\'b|3), engine.render_string(%q({{ 'V\1-\2' }}|{{ 'a\nb' | length }}|{{ 'a\'b' }}|{% set z = 'a\nb' %}{{ z | length }})))
  end

  it "overrides undefined handling per call" do
    engine = KrikriJinja::Engine.new
    node = KrikriJinja.parse_expression("missing")
    err = assert_raises(KrikriJinja::TemplateError) do
      KrikriJinja.to_json_any(engine.evaluate_parsed(node, undefined: KrikriJinja::StrictUndefined.new))
    end

    assert(err.message.not_nil!.includes?("'missing' is undefined"))
  end
end

describe "KrikriJinja fully-qualified feature names" do
  it "resolves a collection-qualified filter or test by its trailing name" do
    assert_equal("ABC True", KrikriJinja.render("{{ 'abc' | ansible.builtin.upper }} {{ 3 is ansible.builtin.odd }}"))
  end
end

describe "KrikriJinja single-dot filter names" do
  it "keeps a single-dot filter name unknown" do
    err = assert_raises(KrikriJinja::TemplateError) do
      KrikriJinja.render("{{ [1] | first.last }}")
    end

    assert(err.message.not_nil!.includes?("unknown filter"))
  end
end

describe "KrikriJinja dict methods and finalize" do
  it "copies and updates dicts like Python" do
    assert_equal("{'a': 1, 'b': 99} {'a': 1, 'b': 2}", KrikriJinja.render("{% set m = b.copy() %}{% set _ = m.update(o) %}{{ m }} {{ b }}",
      {"b" => {"a" => 1, "b" => 2}, "o" => {"b" => 99}}))
  end

  it "applies finalize to output only" do
    engine = KrikriJinja::Engine.new
    engine.finalize = ->(value : KrikriJinja::AnyValue) { value.raw.nil? ? KrikriJinja::AnyValue.new("") : value }
    node = KrikriJinja::Parser.parse("a{{ none }}b{{ [none] }}", engine.options)
    assert_equal("ab[None]", engine.render_parsed(node))
  end
end

describe "KrikriJinja dict pair unpacking" do
  it "iterates a dict's pairs for two loop targets only when enabled" do
    engine = KrikriJinja::Engine.new
    node = KrikriJinja::Parser.parse("{% for k, v in d %}{{ k }}={{ v }};{% endfor %}", engine.options)
    variables = {"d" => KrikriJinja.wrap_value({"a" => 1, "b" => 2})}
    assert_raises(KrikriJinja::TemplateError) { engine.render_parsed(node, variables) }
    engine.dict_pair_unpacking = true
    assert_equal("a=1;b=2;", engine.render_parsed(node, variables))
    assert_equal("ab", engine.render_parsed(KrikriJinja::Parser.parse("{% for k in d %}{{ k }}{% endfor %}", engine.options), variables))
  end
end

private class Meters < KrikriJinja::HostObject
  getter value : Int64

  def initialize(@value : Int64)
  end

  def to_s(io : IO) : Nil
    io << @value << "m"
  end

  def repr : String
    "Meters(#{@value})"
  end

  def get_attr(name : String) : KrikriJinja::AnyValue?
    KrikriJinja::AnyValue.new(@value) if name == "value"
  end

  def binary_op(op : String, other : KrikriJinja::AnyValue, reflected : Bool) : KrikriJinja::AnyValue?
    case {op, other.raw}
    when {"+", Meters} then KrikriJinja::AnyValue.new(Meters.new(@value + other.raw.as(Meters).value))
    when {"*", Int64}  then KrikriJinja::AnyValue.new(Meters.new(@value * other.raw.as(Int64)))
    end
  end

  def compare(other : KrikriJinja::AnyValue) : Int32?
    other.raw.as?(Meters).try { |meters| @value <=> meters.value }
  end

  def to_json_any : JSON::Any
    JSON::Any.new(@value)
  end
end

describe KrikriJinja::HostObject do
  it "takes part in rendering, attributes, arithmetic, comparison, and JSON" do
    variables = {"a" => KrikriJinja::AnyValue.new(Meters.new(2)), "b" => KrikriJinja::AnyValue.new(Meters.new(3))}
    assert_equal("5m 4m [Meters(2)] 2 True True 2m 2", KrikriJinja.render("{{ a + b }} {{ 2 * a }} {{ [a] }} {{ a.value }} {{ a < b }} {{ a == a }} {{ [b, a] | sort | first }} {{ a | tojson }}",
      variables))
    err = assert_raises(KrikriJinja::TemplateError) do
      KrikriJinja.render("{{ a - 1 }}", variables)
    end

    assert(err.message.not_nil!.includes?("unsupported operand types for -"))
  end
end

describe "KrikriJinja missing attribute messages" do
  it "names the object type and attribute, as Jinja does" do
    engine = KrikriJinja::Engine.new(undefined: KrikriJinja.ansible_strict_undefined)
    variables = {"d" => KrikriJinja.wrap_value({"a" => 1})}
    {"{{ d.nope }}", "{{ d['nope'] }}", "{{ d.nope.deeper }}"}.each do |source|
      err = assert_raises(KrikriJinja::TemplateError) do
        engine.render_parsed(KrikriJinja::Parser.parse(source, engine.options), variables)
      end

      assert(err.message.not_nil!.includes?("'dict object' has no attribute 'nope'"))
    end
    assert_equal("xFalse", engine.render_parsed(KrikriJinja::Parser.parse("{{ d.nope | default('x') }}{{ d.nope is defined }}", engine.options), variables))
  end
end
