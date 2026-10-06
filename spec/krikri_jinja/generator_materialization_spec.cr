require "../spec_helper"
require "../../src/krikri_jinja"

# ansible-core 2.19 consumes the iterator/generator result of every filter
# call at the call boundary (_wrap_plugin_output in
# ansible/_internal/_templating/_jinja_bits.py + _jinja_plugins.py:
# "ensure that iterators/generators returned from plugins are consumed"),
# so `x | select(...)` reaches `| length`, `+`, `{% set %}` as a real list.
# Expected outputs below are live-verified real ansible-playbook results
# (ansible-core 2.19.11): B1 [1, 3, 9]; E1 "2 3"; zip/batch/groupby
# materialize the same way; jinja-core builtin GLOBALS (range/dict/lipsum/
# cycler) are NOT wrapped - `{% set r = range(3) %}{{ r + [9] }}` fails in
# real with "unsupported operand type(s) for +: 'range' and 'list'". (The
# engine has no `zip` filter yet, so zip is not pinned here.)
describe KrikriJinja do
  describe "generator materialization at the filter call boundary" do
    it "materializes select for length, + and set" do
      assert_equal("2 3", KrikriJinja.render(
        "{% set k = lst | select('odd') %}{{ k | length }} {{ (k + [9]) | length }}",
        {"lst" => [1, 2, 3, 4]}))
      assert_equal("[1, 3, 9]", KrikriJinja.render("{{ (lst | select('odd')) + [9] }}", {"lst" => [1, 2, 3, 4]}))
    end

    it "materializes map and reject chains" do
      assert_equal("4", KrikriJinja.render("{{ lst | map('upper') | length }}", {"lst" => ["a", "b", "c", "d"]}))
      assert_equal("2", KrikriJinja.render("{{ lst | reject('odd') | list | length }}", {"lst" => [1, 2, 3, 4]}))
      assert_equal("4", KrikriJinja.render(
        "{% set k = lst | map('upper') %}{{ k | length }}", {"lst" => ["a", "b", "c", "d"]}))
    end

    it "materializes jinja builtin filters: batch, groupby" do
      assert_equal("2", KrikriJinja.render("{{ lst | batch(2) | length }}", {"lst" => [1, 2, 3, 4]}))
      assert_equal("3", KrikriJinja.render("{{ ((lst | batch(2)) + [(9, 9)]) | length }}", {"lst" => [1, 2, 3, 4]}))
      assert_equal("2 3", KrikriJinja.render(
        "{% set g = dicts | groupby('k') %}{{ g | length }} {{ (g + [('zz', [])]) | length }}",
        {"dicts" => [{"k" => "a"}, {"k" => "b"}, {"k" => "a"}]}))
    end

    it "raises slice(0) at the boundary even when only assigned" do
      ex = assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{{ lst | slice(0) }}", {"lst" => [1, 2, 3, 4]})
      end
      assert(ex.message.not_nil!.includes?("integer division or modulo by zero"))
      ex = assert_raises(KrikriJinja::TemplateError) do
        KrikriJinja.render("{% set s = lst | slice(0) %}x", {"lst" => [1, 2, 3, 4]})
      end
      assert(ex.message.not_nil!.includes?("integer division or modulo by zero"))
    end

    it "does not wrap jinja builtin globals (range, dict)" do
      assert_equal("3", KrikriJinja.render("{{ range(3) | length }}"))
      assert_equal("3", KrikriJinja.render("{% set r = range(3) %}{{ r | length }}"))
      assert_equal("1", KrikriJinja.render("{% set d = dict(a=1) %}{{ d | length }}"))
    end

    it "materializes non-builtin global function results like real wraps plugin outputs" do
      opts = KrikriJinja::LexerOptions.new
      engine = KrikriJinja::Engine.new(nil, {} of String => KrikriJinja::AnyV, opts, false)
      engine.register_function("gen_plugin") do |_args, _kwargs, _ctx|
        KrikriJinja::AnyValue.new(KrikriJinja::GeneratorValue.new([KrikriJinja::AnyValue.new(1i64), KrikriJinja::AnyValue.new(3i64)]))
      end
      engine.register_function("lazy_builtin") do |_args, _kwargs, _ctx|
        KrikriJinja::AnyValue.new(KrikriJinja::GeneratorValue.new([KrikriJinja::AnyValue.new(1i64)]))
      end
      # Reach in and mark the second global as a jinja builtin: builtins stay
      # unwrapped, exactly like real leaves range() unmaterialized.
      globals = engine.globals
      globals["lazy_builtin"].raw.as(KrikriJinja::Callable).jinja_builtin = true

      assert_equal("2 3", engine.render_string(
        "{% set k = gen_plugin() %}{{ k | length }} {{ (k + [9]) | length }}",
        KrikriJinja.context({} of String => String)))
      ex = assert_raises(KrikriJinja::TemplateError) do
        engine.render_string("{% set k = lazy_builtin() %}{{ k | length }}",
          KrikriJinja.context({} of String => String))
      end
      assert(ex.message.not_nil!.includes?("GeneratorValue has no length"))
    end
  end
end
