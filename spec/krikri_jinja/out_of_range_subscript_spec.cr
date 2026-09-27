require "../spec_helper"
require "../../src/krikri_jinja"

# Out-of-range list/tuple subscripts produce a STRICT undefined with real
# Jinja2 3.1.6's own message ("list object has no element 9", verified
# against jinja2 3.1.6 with StrictUndefined): rendering it raises the way
# ansible-core's StrictUndefined fails the task, while a consuming
# `| default(...)` still catches it (real renders the fallback). A missing
# dict KEY stays the lenient undefined.
describe KrikriJinja do
  describe "out-of-range subscripts" do
    it "raises on rendering an out-of-range list index" do
      ctx = KrikriJinja.context({"items" => [1, 2, 3]})
      expect_raises(KrikriJinja::TemplateError, "list object has no element 9") do
        KrikriJinja.render("{{ items[9] }}", ctx)
      end
    end

    it "raises on a negative out-of-range list index" do
      ctx = KrikriJinja.context({"items" => [1, 2, 3]})
      expect_raises(KrikriJinja::TemplateError, "list object has no element -9") do
        KrikriJinja.render("{{ items[-9] }}", ctx)
      end
    end

    it "raises on an out-of-range tuple index" do
      engine = KrikriJinja.default_engine
      node = KrikriJinja.parse_expression("pair[5]")
      expect_raises(KrikriJinja::TemplateError, "tuple object has no element 5") do
        engine.evaluate_parsed(node, {"pair" => KrikriJinja::AnyValue.new(KrikriJinja::TupleValue.new([KrikriJinja::AnyValue.new(1_i64), KrikriJinja::AnyValue.new(2_i64)]))})
      end
    end

    it "still lets a default filter consume the out-of-range undefined" do
      ctx = KrikriJinja.context({"items" => [1, 2, 3]})
      KrikriJinja.render("{{ items[99] | default('x') }}", ctx).should eq("x")
    end

    it "raises when evaluate_parsed's top-level result is the out-of-range undefined" do
      engine = KrikriJinja.default_engine
      node = KrikriJinja.parse_expression("items[9]")
      expect_raises(KrikriJinja::TemplateError, "list object has no element 9") do
        engine.evaluate_parsed(node, {"items" => KrikriJinja.wrap_value([1, 2, 3])})
      end
    end

    it "keeps a missing dict key lenient" do
      ctx = KrikriJinja.context({"d" => {"a" => 1}})
      KrikriJinja.render("{{ d['missing'] }}", ctx).should eq("")
    end

    it "keeps in-range negative indexes working" do
      ctx = KrikriJinja.context({"items" => [1, 2, 3]})
      KrikriJinja.render("{{ items[-1] }}", ctx).should eq("3")
    end
  end
end
