require "../spec_helper"
require "../../src/krikri_jinja"

describe KrikriJinja::Engine do
  it "does not leak **kwargs into the parsed node across renders" do
    engine = KrikriJinja::Engine.new
    engine.register_function("keys") { |_args, kwargs, _ctx| KrikriJinja::AnyValue.new(kwargs.keys.sort.join(",")) }

    node = KrikriJinja::Parser.parse("{{ keys(**d) }}", engine.options)
    vars = KrikriJinja.context({"d" => {"a" => 1}})

    engine.render_parsed(node, vars).should eq("a")
    engine.render_parsed(node, KrikriJinja.context({"d" => {"b" => 2}})).should eq("b")
    engine.render_parsed(node, vars).should eq("a")
  end

  it "does not leak **kwargs when the same dict keys render repeatedly" do
    engine = KrikriJinja::Engine.new
    engine.register_function("kwn") { |_args, kwargs, _ctx| KrikriJinja::AnyValue.new(kwargs.size.to_i64) }

    node = KrikriJinja::Parser.parse("{{ kwn(**d) }}", engine.options)
    vars = KrikriJinja.context({"d" => {"x" => 1, "y" => 2}})

    3.times { engine.render_parsed(node, vars).should eq("2") }
    engine.render_parsed(node, KrikriJinja.context({"d" => {"z" => 3}})).should eq("1")
  end

  it "still applies explicit kwargs alongside **dict unpacking" do
    engine = KrikriJinja::Engine.new
    engine.register_function("pick") do |_args, kwargs, _ctx|
      a = kwargs["a"]?.try(&.raw.to_s)
      b = kwargs["b"]?.try(&.raw.to_s)
      KrikriJinja::AnyValue.new("#{a}/#{b}")
    end

    node = KrikriJinja::Parser.parse("{{ pick(b=2, **d) }}", engine.options)
    engine.render_parsed(node, KrikriJinja.context({"d" => {"a" => 1, "b" => 9}})).should eq("1/9")
    engine.render_parsed(node, KrikriJinja.context({"d" => {"a" => 5, "b" => 9}})).should eq("5/9")
  end
end
