require "../spec_helper"
require "../../src/krikri_jinja"

# Python list methods exposed through Jinja attribute access - real
# ansible-core 2.19.11 wording probed 2026-10-10 (bilalcaliksan.zookeeper's
# zoo.cfg.j2 `groups['zookeepers'].index(inventory_hostname)`, round 5410000).
describe KrikriJinja do
  describe "list methods through attribute access" do
    it "index returns the first position" do
      assert_equal("1", KrikriJinja.render("{{ lst.index('b') }}", {"lst" => ["a", "b", "c"]}))
    end

    it "index on a missing value fails with Python's ValueError text" do
      assert_raises(KrikriJinja::TemplateError, "'z' is not in list") do
        KrikriJinja.render("{{ lst.index('z') }}", {"lst" => ["a", "b", "c"]})
      end
    end

    it "index honors start/end slice bounds" do
      assert_equal("3", KrikriJinja.render("{{ lst.index('b', 2) }}", {"lst" => ["a", "b", "a", "b"]}))
    end

    it "count counts value-equal entries" do
      assert_equal("2", KrikriJinja.render("{{ lst.count('a') }}", {"lst" => ["a", 1, "a"]}))
    end

    it "extend mutates in place and returns none" do
      assert_equal("9", KrikriJinja.render("{% do lst.extend([9]) %}{{ lst | last }}", {"lst" => [1, 2]}))
    end

    it "pop removes and returns the item" do
      assert_equal("2", KrikriJinja.render("{% do lst.pop() %}{{ lst | last }}", {"lst" => [1, 2, 3]}))
    end

    it "reverse mutates in place" do
      assert_equal("2,1", KrikriJinja.render("{% do lst.reverse() %}{{ lst | join(',') }}", {"lst" => [1, 2]}))
    end
  end
end
