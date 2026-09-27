require "../spec_helper"
require "../../src/krikri_jinja"

describe "Markup to_json_any" do
  it "converts a top-level Markup result to its underlying string" do
    assert_equal(%("x"), KrikriJinja.evaluate_expression("'x' | safe").to_json)
  end

  it "converts an escaped Markup result to its escaped string" do
    assert_equal(%("&lt;b&gt;"), KrikriJinja.evaluate_expression("'<b>' | escape").to_json)
  end

  it "converts a bare Markup value" do
    assert_equal(%("raw <b>"), KrikriJinja.to_json_any(KrikriJinja::AnyValue.new(KrikriJinja::Markup.new("raw <b>")))
      .to_json)
  end

  it "converts Markup nested inside containers" do
    assert_equal(%(["a",{"k":"b"}]), KrikriJinja.evaluate_expression("['a' | safe, {'k': 'b' | safe}]").to_json)
  end
end
