require "../src/krikri_jinja"

root = "/tmp/krikri_bench_inc"
Dir.mkdir(root) unless Dir.exists?(root)
File.write("#{root}/partial.j2", "<x>")

engine = KrikriJinja::Engine.new(KrikriJinja::FileSystemLoader.new(root))
tpl = "{% for i in seq %}{% include 'partial.j2' %}{% endfor %}"
N = 2000

t = Time.monotonic
result = ""
N.times { result = engine.render_string(tpl, KrikriJinja.context({"seq" => [1, 2, 3, 4, 5]})) }
include_ms = (Time.monotonic - t).total_milliseconds

# Direct render_parsed of the already-parsed outer template with the
# cache in place: measures the steady-state include-heavy render path.
parsed = engine.parsed_template(tpl)
t = Time.monotonic
N.times { result = engine.render_parsed(parsed, KrikriJinja.context({"seq" => [1, 2, 3, 4, 5]})) }
cached_ms = (Time.monotonic - t).total_milliseconds

puts "include loop, parse each time (#{N}x): #{include_ms.round(1)} ms  (#{(N / (include_ms / 1000)).round(0)} renders/s)"
puts "include loop, cached parse    (#{N}x): #{cached_ms.round(1)} ms  (#{(N / (cached_ms / 1000)).round(0)} renders/s)"
puts "speedup: #{(include_ms / cached_ms).round(2)}x"
puts result
