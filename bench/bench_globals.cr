require "../src/krikri_jinja"

engine = KrikriJinja::Engine.new
1000.times { |i| engine.register_function("f#{i}") { |_a, _k, _c| KrikriJinja::AnyValue.new(i.to_i64) } }
N = 20000

t = Time.monotonic
result = ""
N.times { result = engine.render_string("{{ f500 }} {{ x }}", KrikriJinja.context({"x" => 1})) }
ms = (Time.monotonic - t).total_milliseconds
puts "render with 1000 globals (#{N}x): #{ms.round(1)} ms  (#{(N / (ms / 1000)).round(0)} renders/s)"
puts result
