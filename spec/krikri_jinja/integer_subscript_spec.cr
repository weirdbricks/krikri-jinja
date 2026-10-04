require "../spec_helper"
require "../../src/krikri_jinja"

# `a.0` is a subscript, not an attribute lookup: Jinja2 parses a number
# after `.` as an integer subscript, so `a.0` is exactly `a[0]`. (Real
# Jinja2 also then misses a dict keyed by the *string* "0"; this engine
# still finds it, a pre-existing int-vs-string key coercion that applies
# equally to `a[0]` and is tracked separately.)
#
# Supporting it needs two lexer/parser rules that are easy to get wrong:
# the literal after `.` must be an integer (never a float, even
# `a.0.0`), and Jinja2's integer grammar rejects a leading zero (`01`)
# while still allowing it in the float forms (`01.5`, `01e2`).
describe KrikriJinja do
  describe "integer subscripts (a.0)" do
    it "subscripts a list" do
      assert_equal("x", KrikriJinja.render("{{ a.0 }}", {"a" => ["x", "y"]}))
    end

    it "is identical to the bracket form" do
      assert_equal("True", KrikriJinja.render("{{ a.0 == a[0] }}", {"a" => ["x", "y"]}))
    end

    it "chains into a further integer subscript" do
      assert_equal("n", KrikriJinja.render("{{ a.0.0 }}", {"a" => [["n"]]}))
    end

    it "chains into an attribute after a subscript" do
      assert_equal("deep", KrikriJinja.render("{{ a.0.x }}", {"a" => [{"x" => "deep"}]}))
    end

    it "subscripts into a nested structure" do
      ctx = {"item" => [{"name" => "n0"}, {"name" => "n1"}]}
      assert_equal("n0", KrikriJinja.render("{{ item.0.name }}", ctx))
    end

    it "misses a dict that has no matching key" do
      assert_equal("", KrikriJinja.render("{{ a.0 }}", {"a" => {"k" => "x"}}))
    end

    it "accepts an underscore-separated index" do
      assert_equal("10", KrikriJinja.render("{{ a.1_0 }}", {"a" => (0..10).to_a}))
    end

    it "accepts a hex index" do
      ctx = {"a" => (0..31).to_a}
      assert_equal("31", KrikriJinja.render("{{ a.0x1f }}", ctx))
    end

    it "still subscripts past a name" do
      assert_equal("q", KrikriJinja.render("{{ a.b.1 }}", {"a" => {"b" => ["p", "q"]}}))
    end

    it "rejects a leading-zero index" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja::Parser.parse("{{ a.01 }}")
      end
    end

    it "rejects a negative index" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja::Parser.parse("{{ a.-1 }}")
      end
    end
  end

  describe "integer literal grammar" do
    it "rejects a leading zero" do
      assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja::Parser.parse("{{ 01 }}")
      end
    end

    it "accepts zeros and underscore-separated zeros" do
      assert_equal("0 0 0 0", KrikriJinja.render("{{ 0 }} {{ 00 }} {{ 0_0 }} {{ 0_00 }}"))
    end

    it "accepts a leading zero in the float forms" do
      assert_equal("1.5 0.5 0.5", KrikriJinja.render("{{ 01.5 }} {{ 0.5 }} {{ 00.5 }}"))
      assert_equal("100.0", KrikriJinja.render("{{ 01e2 }}"))
    end

    it "accepts hex, octal, binary and underscore integers" do
      assert_equal("31 15 5 1000",
        KrikriJinja.render("{{ 0x1f }} {{ 0o17 }} {{ 0b101 }} {{ 1_000 }}"))
    end

    it "does not treat a number after a dot as a float" do
      assert_equal("1 0", KrikriJinja.render("{{ 1 }} {{ a.0 }}", {"a" => [0]}))
    end
  end
end