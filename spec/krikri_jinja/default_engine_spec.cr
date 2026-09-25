require "../spec_helper"
require "../../src/krikri_jinja"

describe "KrikriJinja default engine" do
  it "registers filters, tests, functions, and globals for module-level rendering" do
    KrikriJinja.reset_default_engine
    KrikriJinja.register_default_json_filter("exclaim") do |value, _args, _kwargs|
      JSON::Any.new("#{value.as_s}!")
    end
    KrikriJinja.register_default_json_test("text") do |value, _args, _kwargs|
      value.raw.is_a?(String)
    end
    KrikriJinja.register_default_json_function("identity") do |args, _kwargs|
      args[0]
    end
    KrikriJinja.register_default_global("answer", JSON::Any.new(42))

    rendered = KrikriJinja.render("{{ 'hello' | exclaim }} {{ 'hello' is text }} {{ identity([1, true]) | tojson }} {{ answer }}")
    rendered.should eq("hello! True [1, true] 42")
  ensure
    KrikriJinja.reset_default_engine
  end

  it "exposes registered feature names for compile-time checks" do
    KrikriJinja.reset_default_engine
    KrikriJinja.register_default_json_filter("shout") { |value, _args, _kwargs| JSON::Any.new(value.as_s.upcase) }
    KrikriJinja.register_default_json_test("small") { |value, _args, _kwargs| value.as_i < 10 }

    KrikriJinja.default_known_filter?("shout").should be_true
    KrikriJinja.default_known_test?("small").should be_true
    KrikriJinja.default_known_filter?("missing_filter").should be_false
  ensure
    KrikriJinja.reset_default_engine
  end
end

describe "KrikriJinja.evaluate_expression_result" do
  it "distinguishes an undefined result from a JSON null result" do
    undefined_result = KrikriJinja.evaluate_expression_result("missing")
    undefined_result.undefined?.should be_true
    undefined_result.value.should be_nil

    null_result = KrikriJinja.evaluate_expression_result("none")
    null_result.undefined?.should be_false
    null_result.value.not_nil!.raw.should be_nil
  end

  it "returns typed values for defined expressions" do
    result = KrikriJinja.evaluate_expression_result("items | map(attribute='name')", {
      "items" => JSON.parse(%([{"name": "a"}, {"name": "b"}])),
    })
    result.undefined?.should be_false
    result.value.not_nil!.to_json.should eq(%(["a","b"]))
  end
end

class SpecHostContext < KrikriJinja::HostContext
  getter prefix : String

  def initialize(@prefix : String)
  end
end

describe "KrikriJinja host context" do
  it "hands the caller context to registered functions" do
    KrikriJinja.reset_default_engine
    KrikriJinja.register_default_function("greet") do |args, _kwargs, ctx|
      host = ctx.host_context
      KrikriJinja.from_json_any(JSON::Any.new("#{host.not_nil!.as(SpecHostContext).prefix}#{KrikriJinja.stringify(args[0].not_nil!)}"))
    end

    KrikriJinja.render("{{ greet('world') }}", host_context: SpecHostContext.new("hello ")).should eq("hello world")
    KrikriJinja.evaluate_expression("greet('world')", host_context: SpecHostContext.new("hi "))
      .not_nil!.as_s.should eq("hi world")
  ensure
    KrikriJinja.reset_default_engine
  end
end
