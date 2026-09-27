require "../spec_helper"
require "../../src/krikri_jinja"

describe KrikriJinja::Engine do
  it "does not leak **kwargs into the parsed node across renders" do
    engine = KrikriJinja::Engine.new
    engine.register_function("keys") { |_args, kwargs, _ctx| KrikriJinja::AnyValue.new(kwargs.keys.sort.join(",")) }

    node = KrikriJinja::Parser.parse("{{ keys(**d) }}", engine.options)
    vars = KrikriJinja.context({"d" => {"a" => 1}})

    assert_equal("a", engine.render_parsed(node, vars))
    assert_equal("b", engine.render_parsed(node, KrikriJinja.context({"d" => {"b" => 2}})))
    assert_equal("a", engine.render_parsed(node, vars))
  end

  it "does not leak **kwargs when the same dict keys render repeatedly" do
    engine = KrikriJinja::Engine.new
    engine.register_function("kwn") { |_args, kwargs, _ctx| KrikriJinja::AnyValue.new(kwargs.size.to_i64) }

    node = KrikriJinja::Parser.parse("{{ kwn(**d) }}", engine.options)
    vars = KrikriJinja.context({"d" => {"x" => 1, "y" => 2}})

    3.times { assert_equal("2", engine.render_parsed(node, vars)) }
    assert_equal("1", engine.render_parsed(node, KrikriJinja.context({"d" => {"z" => 3}})))
  end

  it "still applies explicit kwargs alongside **dict unpacking" do
    engine = KrikriJinja::Engine.new
    engine.register_function("pick") do |_args, kwargs, _ctx|
      a = kwargs["a"]?.try(&.raw.to_s)
      b = kwargs["b"]?.try(&.raw.to_s)
      KrikriJinja::AnyValue.new("#{a}/#{b}")
    end

    node = KrikriJinja::Parser.parse("{{ pick(b=2, **d) }}", engine.options)
    assert_equal("1/9", engine.render_parsed(node, KrikriJinja.context({"d" => {"a" => 1, "b" => 9}})))
    assert_equal("5/9", engine.render_parsed(node, KrikriJinja.context({"d" => {"a" => 5, "b" => 9}})))
  end
end

describe KrikriJinja::Engine do
  it "reuses cached parsed templates and expressions for identical source" do
    engine = KrikriJinja::Engine.new
    a = engine.parsed_template("{{ 1 + 2 }}")
    b = engine.parsed_template("{{ 1 + 2 }}")
    assert_same(b, a)

    x = engine.parsed_expression("1 + 2")
    y = engine.parsed_expression("1 + 2")
    assert_same(y, x)
  end

  it "keeps distinct cache entries for different sources and options" do
    engine = KrikriJinja::Engine.new
    a = engine.parsed_template("{{ 1 }}")
    b = engine.parsed_template("{{ 2 }}")
    refute_same(b, a)

    other = KrikriJinja::Engine.new(options: KrikriJinja::LexerOptions.new(trim_blocks: true))
    refute_same(a, other.parsed_template("{{ 1 }}"))
  end
end
