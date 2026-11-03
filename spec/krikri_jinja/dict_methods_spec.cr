require "../spec_helper"
require "../../src/krikri_jinja"

# Python dict methods exposed through Jinja attribute access - real
# ansible-core 2.19.11 + Jinja2 3.1.6 wording probed 2026-11-03
# (mila.syslog_ng's sources.conf.j2 calls dic.pop('comment'),
# krikri issue #791).
describe KrikriJinja do
  describe "dict methods through attribute access" do
    it "pop removes and returns the value" do
      assert_equal("1", KrikriJinja.render("{{ d.pop('a') }}", {"d" => {"a" => 1, "b" => 2}}))
    end

    it "pop mutates the dict in place" do
      assert_equal("b", KrikriJinja.render("{% do d.pop('a') %}{{ d.keys() | join(',') }}", {"d" => {"a" => 1, "b" => 2}}))
    end

    it "pop returns the default for a missing key" do
      assert_equal("7", KrikriJinja.render("{{ d.pop('missing', 7) }}", {"d" => {"a" => 1}}))
    end

    it "pop of a missing key with no default fails with Python's KeyError text" do
      assert_raises(KrikriJinja::TemplateError, "'missing'") do
        KrikriJinja.render("{{ d.pop('missing') }}", {"d" => {"a" => 1}})
      end
    end

    it "pop with no arguments fails with Python's TypeError text" do
      assert_raises(KrikriJinja::TemplateError, "pop expected at least 1 argument, got 0") do
        KrikriJinja.render("{{ d.pop() }}", {"d" => {"a" => 1}})
      end
    end

    it "pop with more than two arguments fails with Python's TypeError text" do
      assert_raises(KrikriJinja::TemplateError, "pop expected at most 2 arguments, got 3") do
        KrikriJinja.render("{{ d.pop('a', 'x', 'y') }}", {"d" => {"a" => 1}})
      end
    end
  end
end
