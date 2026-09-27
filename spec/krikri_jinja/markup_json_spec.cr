require "../spec_helper"
require "../../src/krikri_jinja"

describe "Markup to_json_any" do
  it "converts a top-level Markup result to its underlying string" do
    KrikriJinja.evaluate_expression("'x' | safe").to_json.should eq(%("x"))
  end

  it "converts an escaped Markup result to its escaped string" do
    KrikriJinja.evaluate_expression("'<b>' | escape").to_json.should eq(%("&lt;b&gt;"))
  end

  it "converts a bare Markup value" do
    KrikriJinja.to_json_any(KrikriJinja::AnyValue.new(KrikriJinja::Markup.new("raw <b>")))
      .to_json.should eq(%("raw <b>"))
  end

  it "converts Markup nested inside containers" do
    KrikriJinja.evaluate_expression("['a' | safe, {'k': 'b' | safe}]").to_json
      .should eq(%(["a",{"k":"b"}]))
  end
end
