require "../spec_helper"
require "../../src/krikri_jinja"

# Real Jinja2 3.x do_groupby yields _GroupTuple namedtuples: json.dumps
# (ansible debug:/tojson) serializes each group as a [grouper, list]
# ARRAY, not a {grouper, list} object.
describe "groupby pair shape" do
  it "renders groups as [grouper, list] pairs" do
    rendered = KrikriJinja.render("{{ items | groupby('color') | tojson }}", {"items" => JSON.parse("[{\"color\": \"red\", \"n\": 1}, {\"color\": \"blue\", \"n\": 2}, {\"color\": \"red\", \"n\": 3}]")})
    assert_equal("[[\"blue\",[{\"color\":\"blue\",\"n\":2}]],[\"red\",[{\"color\":\"red\",\"n\":1},{\"color\":\"red\",\"n\":3}]]]", rendered.gsub(/\s+/, ""))
  end
end
