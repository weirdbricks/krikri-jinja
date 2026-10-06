require "../spec_helper"
require "../../src/krikri_jinja"

# A FLOAT-indexed dict lookup must find the key the JSON round trip stored
# as a plain string: a host's YAML `5.7:` key arrives at the engine as the
# string "5.7" (JSON object keys are always strings), while the subscript
# carries the real float - real Jinja2/Python matches float dict keys by
# value (d[5.7] hits a 5.7 key, d[8] hits an 8.0 key; verified against
# ansible-core 2.19.11 via Oefenweb.percona_server's
# `percona_server_libmysqlclient_map[percona_server_version]`, where the
# old truncation-only fallback rendered the whole lookup as undefined).
describe KrikriJinja do
  describe "float dict keys" do
    it "finds a non-integral float key by its string form" do
      assert_equal("lib20", KrikriJinja.render("{{ m[5.7] }}", {"m" => {"5.7" => "lib20"}}))
    end

    it "finds an integral float key by its string form" do
      assert_equal("lib21", KrikriJinja.render("{{ m[8.0] }}", {"m" => {"8.0" => "lib21"}}))
    end

    it "finds a float key indexed by a float variable" do
      assert_equal("lib20", KrikriJinja.render("{{ m[v] }}", {"m" => {"5.7" => "lib20"}, "v" => 5.7}))
    end

    it "still misses a dict that has no matching numeric key" do
      assert_equal("", KrikriJinja.render("{{ m[9.9] }}", {"m" => {"5.7" => "lib20"}}))
    end

    # Documented deviation, same class as the pre-existing int-vs-string key
    # one: an INT index against an integral FLOAT YAML key ("8.0" stored as
    # a string) would need a numeric scan of the stored keys - real Python's
    # d[8] hits an 8.0 key, krikri answers "" there. The by-value float
    # match above covers the shape real roles actually use
    # (map[float_default_version]).
  end
end
