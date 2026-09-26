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

    engine.evaluate_parsed(node, resolver: resolver).raw.should eq(6_i64)
    resolver.requested.should eq(["a"])
  end

  it "lets explicit variables and template assignments shadow the resolver" do
    resolver = CountingResolver.new({"x" => KrikriJinja::AnyValue.new("resolved")})
    engine = KrikriJinja::Engine.new
    node = KrikriJinja::Parser.parse("{{ x }}|{% set x = 'local' %}{{ x }}|{{ y }}", engine.options)
    variables = {"y" => KrikriJinja::AnyValue.new("given")}

    engine.render_parsed(node, variables, resolver).should eq("resolved|local|given")
  end

  it "falls back to globals and then undefined when the resolver has no value" do
    resolver = CountingResolver.new({} of String => KrikriJinja::AnyValue)
    engine = KrikriJinja::Engine.new

    engine.evaluate_parsed(KrikriJinja.parse_expression("range(2) | list"), resolver: resolver).raw
      .as(Array).size.should eq(2)
    engine.evaluate_parsed(KrikriJinja.parse_expression("missing is defined"), resolver: resolver).raw
      .should be_false
  end
end

describe "KrikriJinja verbatim expression strings" do
  it "keeps backslashes in {{ }} literals but decodes {% %} literals" do
    options = KrikriJinja::LexerOptions.new(verbatim_expression_strings: true)
    engine = KrikriJinja::Engine.new(options: options)
    engine.render_string(%q({{ 'V\1-\2' }}|{{ 'a\nb' | length }}|{{ 'a\'b' }}|{% set z = 'a\nb' %}{{ z | length }}))
      .should eq(%q(V\1-\2|4|a\'b|3))
  end

  it "overrides undefined handling per call" do
    engine = KrikriJinja::Engine.new
    node = KrikriJinja.parse_expression("missing")
    expect_raises(KrikriJinja::TemplateError, "'missing' is undefined") do
      KrikriJinja.to_json_any(engine.evaluate_parsed(node, undefined: KrikriJinja::StrictUndefined.new))
    end
  end
end

describe "KrikriJinja fully-qualified feature names" do
  it "resolves a collection-qualified filter or test by its trailing name" do
    KrikriJinja.render("{{ 'abc' | ansible.builtin.upper }} {{ 3 is ansible.builtin.odd }}").should eq("ABC True")
  end
end

describe "KrikriJinja single-dot filter names" do
  it "keeps a single-dot filter name unknown" do
    expect_raises(KrikriJinja::TemplateError, "unknown filter") do
      KrikriJinja.render("{{ [1] | first.last }}")
    end
  end
end

describe "KrikriJinja dict methods and finalize" do
  it "copies and updates dicts like Python" do
    KrikriJinja.render("{% set m = b.copy() %}{% set _ = m.update(o) %}{{ m }} {{ b }}",
      {"b" => {"a" => 1, "b" => 2}, "o" => {"b" => 99}}).should eq("{'a': 1, 'b': 99} {'a': 1, 'b': 2}")
  end

  it "applies finalize to output only" do
    engine = KrikriJinja::Engine.new
    engine.finalize = ->(value : KrikriJinja::AnyValue) { value.raw.nil? ? KrikriJinja::AnyValue.new("") : value }
    node = KrikriJinja::Parser.parse("a{{ none }}b{{ [none] }}", engine.options)
    engine.render_parsed(node).should eq("ab[None]")
  end
end

describe "KrikriJinja dict pair unpacking" do
  it "iterates a dict's pairs for two loop targets only when enabled" do
    engine = KrikriJinja::Engine.new
    node = KrikriJinja::Parser.parse("{% for k, v in d %}{{ k }}={{ v }};{% endfor %}", engine.options)
    variables = {"d" => KrikriJinja.wrap_value({"a" => 1, "b" => 2})}
    expect_raises(KrikriJinja::TemplateError) { engine.render_parsed(node, variables) }
    engine.dict_pair_unpacking = true
    engine.render_parsed(node, variables).should eq("a=1;b=2;")
    engine.render_parsed(KrikriJinja::Parser.parse("{% for k in d %}{{ k }}{% endfor %}", engine.options), variables).should eq("ab")
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
    KrikriJinja.render("{{ a + b }} {{ 2 * a }} {{ [a] }} {{ a.value }} {{ a < b }} {{ a == a }} {{ [b, a] | sort | first }} {{ a | tojson }}",
      variables).should eq("5m 4m [Meters(2)] 2 True True 2m 2")
    expect_raises(KrikriJinja::TemplateError, "unsupported operand types for -") do
      KrikriJinja.render("{{ a - 1 }}", variables)
    end
  end
end
