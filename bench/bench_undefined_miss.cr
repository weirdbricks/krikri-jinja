require "../src/krikri_jinja"

engine = KrikriJinja::Engine.new
tpl = "{% for i in outer %}{{ missing_a | default('-') }}{{ missing_b | default('-') }}{{ outer[99] | default('-') }}{% endfor %}"
N = 20000

t = Time.monotonic
result = ""
N.times { result = engine.render_string(tpl, KrikriJinja.context({"outer" => [1, 2, 3, 4, 5]})) }
ms = (Time.monotonic - t).total_milliseconds
puts "miss-heavy render (#{N}x): #{ms.round(1)} ms  (#{(N / (ms / 1000)).round(0)} renders/s)"
puts result.size
