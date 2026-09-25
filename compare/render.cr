require "json"
require "../src/krikri_jinja"

# Renders compare/cases.json with krikri-jinja; prints the same JSON lines
# as compare/render.py so the two can be diffed.

cases_path = ARGV[0]? || "compare/cases.json"
cases = Array(JSON::Any).from_json(File.read(cases_path))

cases.each do |case_json|
  name = case_json["name"].as_s
  template = case_json["template"].as_s
  data_json = case_json["data"]

  templates = {} of String => String
  if tpl = case_json["templates"]?
    tpl.as_h.each { |k, v| templates[k] = v.as_s }
  end

  opts = KrikriJinja::LexerOptions.new
  autoescape = false
  strict_undefined = false
  if env = case_json["env"]?
    opts = KrikriJinja::LexerOptions.new(
      trim_blocks: env["trim_blocks"]?.try(&.as_bool?) || false,
      lstrip_blocks: env["lstrip_blocks"]?.try(&.as_bool?) || false,
      keep_trailing_newline: env["keep_trailing_newline"]?.try(&.as_bool?) || false,
    )
    autoescape = env["autoescape"]?.try(&.as_bool?) || false
    strict_undefined = env["undefined"]?.try(&.as_s?) == "strict"
  end

  begin
    loader = KrikriJinja::DictLoader.new(templates)
    engine = KrikriJinja::Engine.new(loader, options: opts, autoescape: autoescape,
                                    undefined: strict_undefined ? KrikriJinja::StrictUndefined.new : KrikriJinja::Undefined.new)
    vars = {} of String => KrikriJinja::AnyValue
    data_json.as_h.each do |k, v|
      vars[k] = KrikriJinja.from_json_any(v)
    end
    output = engine.render_string(template, vars)
    puts({"name": name, "output": output, "error": nil}.to_json)
  rescue e : KrikriJinja::TemplateError
    puts({"name": name, "output": nil, "error": "TemplateError: #{e.message}", "error_kind": e.kind.to_s.downcase, "error_json": e.to_json}.to_json)
  rescue e : Exception
    puts({"name": name, "output": nil, "error": "#{e.class}: #{e.message}", "error_kind": "runtime"}.to_json)
  end
end
