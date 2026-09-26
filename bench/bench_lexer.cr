require "../src/krikri_jinja"

body = String.build do |s|
  50.times do |i|
    s << "Some text block #{i} with words and more words.\n"
    s << "{% for item in items %}{{ item.name | upper }}-{{ loop.index }} {% endfor %}\n"
    s << "{% if flag %}yes {{ x + 1 }}{% else %}no{% endif %} {# a comment #}\n"
  end
end

N = 300
opts = KrikriJinja::LexerOptions.new

t = Time.monotonic
count = 0
N.times { count += KrikriJinja::Lexer.new(body, opts).tokens.size }
ms = (Time.monotonic - t).total_milliseconds
puts "lexing #{body.bytesize}B template (#{N}x): #{ms.round(1)} ms  (#{(N / (ms / 1000)).round(0)} lexes/s)"
puts count
