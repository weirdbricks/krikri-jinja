require "../spec_helper"
require "../../src/krikri_jinja"

# Real Jinja2's generated code binds `cond_expr_undefined = Undefined` in
# every template module: an else-less inline conditional
# (`{{ 'a' if false }}`) yields the BASE Undefined class, deliberately
# bypassing the environment's (possibly Strict) undefined class. It
# renders as "", is `is defined` -> False, feeds `| default(...)` and is
# falsy - it does NOT raise the way a failed variable lookup does.
# Found via rolehippie.prometheus's default.j2 (round 5460382), where a
# lazy conditional guards an invalid `+` operand on the untaken branch.
describe KrikriJinja do
  describe "an else-less inline conditional under strict undefined" do
    it "renders as empty instead of raising" do
      engine = KrikriJinja::Engine.new(nil, undefined: KrikriJinja::StrictUndefined.new)
      assert_equal("--x--y", engine.render_string("--x{{ 'A' if false }}--y"))
      assert_equal("--xB--y", engine.render_string("--x{{ 'B' if true }}--y"))
    end

    it "is falsy and not defined" do
      engine = KrikriJinja::Engine.new(nil, undefined: KrikriJinja::StrictUndefined.new)
      assert_equal("FalseN", engine.render_string("{{ ('A' if false) is defined }}{% if ('A' if false) %}Y{% else %}N{% endif %}"))
    end

    it "feeds the default filter" do
      engine = KrikriJinja::Engine.new(nil, undefined: KrikriJinja::StrictUndefined.new)
      assert_equal("fallback", engine.render_string("{{ ('A' if false) | default('fallback') }}"))
    end

    it "raises on attribute access like Jinja2's base Undefined" do
      engine = KrikriJinja::Engine.new(nil, undefined: KrikriJinja::StrictUndefined.new)
      assert_raises(KrikriJinja::TemplateError) { engine.render_string("{{ ('A' if false).foo }}") }
    end
  end
end
