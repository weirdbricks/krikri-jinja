require "../src/krikri_jinja"

floats = [1e20, 1e-5, 3.14159, 123456.789, 9.99e-7, 42.0, 1e100, -2.5e-3]
N = 200000

t = Time.monotonic
result = ""
N.times { floats.each { |f| result = KrikriJinja.format_float(f) } }
fmt_ms = (Time.monotonic - t).total_milliseconds

plain = "The quick brown fox jumps over the lazy dog, entirely safe text with no special characters at all."
dirty = "a & b < c > d \" e ' f" * 4
N2 = 200000

t = Time.monotonic
N2.times { result = KrikriJinja.escape_html(plain) }
clean_ms = (Time.monotonic - t).total_milliseconds

t = Time.monotonic
N2.times { result = KrikriJinja.escape_html(dirty) }
dirty_ms = (Time.monotonic - t).total_milliseconds

puts "format_float 8 values (#{N} rounds): #{fmt_ms.round(1)} ms  (#{(N / (fmt_ms / 1000)).round(0)} rounds/s)"
puts "escape_html clean 100B (#{N2}x): #{clean_ms.round(1)} ms  (#{(N2 / (clean_ms / 1000)).round(0)} escapes/s)"
puts "escape_html dirty 84B (#{N2}x): #{dirty_ms.round(1)} ms  (#{(N2 / (dirty_ms / 1000)).round(0)} escapes/s)"
puts "#{result}"
