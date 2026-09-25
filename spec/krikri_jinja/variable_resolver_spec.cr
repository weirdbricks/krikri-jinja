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
