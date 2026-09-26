require "../src/krikri_jinja"

items = ([] of KrikriJinja::AnyValue)
2000.times do |i|
  h = {} of String => KrikriJinja::AnyValue
  h["g"] = KrikriJinja::AnyValue.new("group#{i % 50}")
  h["n"] = KrikriJinja::AnyValue.new(i.to_i64)
  items << KrikriJinja::AnyValue.new(h)
end
engine = KrikriJinja::Engine.new
N = 200

t = Time.monotonic
result = ""
N.times { result = engine.render_string("{% for g in items | groupby('g') %}{{ g.grouper }}:{{ g.list | length }};{% endfor %}", KrikriJinja.context({"items" => items})) }
ms = (Time.monotonic - t).total_milliseconds
puts "groupby 2000 items / 50 groups (#{N}x): #{ms.round(1)} ms  (#{(N / (ms / 1000)).round(1)} renders/s)"
puts result.size
