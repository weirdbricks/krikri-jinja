require "../src/krikri_jinja"

source = "Hello {{ name }}! {% for i in items %}[{{ i }}]{% endfor %} {% if flag %}yes{% else %}no{% endif %}"
N = 20000

t = Time.monotonic
sink = nil
N.times { sink = KrikriJinja::Parser.parse(source) }
parse_ms = (Time.monotonic - t).total_milliseconds

engine = KrikriJinja::Engine.new
t = Time.monotonic
N.times { sink = engine.parsed_template(source) }
cached_ms = (Time.monotonic - t).total_milliseconds

t = Time.monotonic
N.times { sink = engine.parsed_expression("name ~ '|' ~ items | join(',') ~ (flag if flag else 'no')") }
expr_cached_ms = (Time.monotonic - t).total_milliseconds

t = Time.monotonic
N.times { sink = KrikriJinja::Parser.parse_expression("name ~ '|' ~ items | join(',') ~ (flag if flag else 'no')") }
expr_parse_ms = (Time.monotonic - t).total_milliseconds

puts "template parse (#{N}x):   #{parse_ms.round(1)} ms  (#{(N / (parse_ms / 1000)).round(0)} parses/s)"
puts "template cached (#{N}x):  #{cached_ms.round(2)} ms  (#{(N / (cached_ms / 1000)).round(0)} lookups/s)"
puts "expr parse (#{N}x):       #{expr_parse_ms.round(1)} ms  (#{(N / (expr_parse_ms / 1000)).round(0)} parses/s)"
puts "expr cached (#{N}x):      #{expr_cached_ms.round(2)} ms  (#{(N / (expr_cached_ms / 1000)).round(0)} lookups/s)"
puts "speedup: #{(parse_ms / cached_ms).round(1)}x template, #{(expr_parse_ms / expr_cached_ms).round(1)}x expression"
puts sink.to_s
