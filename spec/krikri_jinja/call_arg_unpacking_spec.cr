require "../spec_helper"
require "../../src/krikri_jinja"

# Jinja2 treats a `|` filter and a `{% set x | filter(...) %}` body filter
# as calls, so `*seq` / `**mapping` unpack into them exactly like a bare
# function call - expected outputs below are live-captured from
# ansible-core 2.21.6 + Jinja2 3.1.6.
describe KrikriJinja do
  describe "call-argument unpacking" do
    it "unpacks a starred sequence into filter arguments" do
      assert_equal("xbc", KrikriJinja.render("{{ 'abc' | replace(*['a', 'x']) }}"))
      assert_equal("a-b", KrikriJinja.render("{{ ['a', 'b'] | join(*['-']) }}"))
    end

    it "unpacks a regex-sourced sequence into filter arguments" do
      assert_equal("x-a-b", KrikriJinja.render("{{ ['a', 'b'] | join(*['-']) | replace(*['a-b', 'x-a-b']) }}"))
    end

    it "unpacks an empty starred sequence into no argument" do
      assert_equal("ab", KrikriJinja.render("{{ ['a', 'b'] | join(*[]) }}"))
    end

    it "unpacks a starred sequence in a set body filter" do
      assert_equal("xbc", KrikriJinja.render("{% set x | replace(*['a', 'x']) %}abc{% endset %}{{ x }}"))
    end

    it "unpacks a double-starred mapping into filter keyword arguments" do
      engine = KrikriJinja::Engine.new
      engine.register_filter("kwprobe") do |_v, _args, kwargs, _ctx|
        KrikriJinja::AnyValue.new(KrikriJinja.stringify(kwargs["sep"]? || KrikriJinja::AnyValue.new("unset")))
      end
      assert_equal("-", engine.render_string("{{ 'x' | kwprobe(**{'sep': '-'}) }}"))
    end
  end
end
