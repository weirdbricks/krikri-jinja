require "../src/krikri_jinja"

query = "search?q=jinja2 template engine&lang=en&tags=crystal+web+framework&page=12&sort=relevance desc"
long = query * 20
N = 5000

t = Time.monotonic
result = ""
N.times { result = KrikriJinja.percent_encode(long, "/") }
ms = (Time.monotonic - t).total_milliseconds
puts "percent_encode #{long.bytesize}B (#{N}x): #{ms.round(1)} ms  (#{(N / (ms / 1000)).round(0)} encodes/s)"
puts KrikriJinja.percent_encode("a b/c+d~e%f", "/")
