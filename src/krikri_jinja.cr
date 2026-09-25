require "./krikri_jinja/lexer"
require "./krikri_jinja/bigmath"
require "./krikri_jinja/nodes"
require "./krikri_jinja/parser"
require "./krikri_jinja/context"
require "./krikri_jinja/value_helpers"
require "./krikri_jinja/filters"
require "./krikri_jinja/tests"
require "./krikri_jinja/evaluator"
require "./krikri_jinja/globals"

module KrikriJinja
  VERSION = "0.4.0"

  # Percent-encoding matching urllib.parse.quote (space becomes %20).
  def self.percent_encode(s : String, extra_safe : String = "") : String
    safe = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~" + extra_safe
    String.build do |io|
      s.each_byte do |b|
        c = b.chr
        if safe.includes?(c)
          io << c
        else
          io << "%" << b.to_s(16).upcase.rjust(2, '0')
        end
      end
    end
  end

  # Percent-encoding matching urllib.parse.quote_plus (space becomes +).
  def self.quote_plus(s : String) : String
    percent_encode(s).gsub("%20", "+")
  end

  def self.filesizeformat(bytes : AnyV, base : Int64, prefixes : Array(String), binary : Bool) : String
    byte_string = case value = bytes
                  when Int64      then value.to_s
                  when BigIntValue then value.value
                  when String     then value
                  else raise TemplateError.new("filesizeformat expects a number", 0)
                  end
    return "0 Bytes" if byte_string == "0"
    units = ["Bytes"] + prefixes
    i = 0
    value = bytes.to_f64
    while value.abs >= base && i < units.size - 1
      value /= base
      i += 1
    end
    if i == 0
      byte_string == "1" ? "1 Byte" : "#{byte_string} Bytes"
    else
      "#{value.round(1)} #{units[i]}"
    end
  end

  # Python %-style formatting (the `format` filter). `tuple_arg` marks a
  # parenthesized right operand; CPython only errors on leftover args for
  # tuples and scalars, never for lists/dicts/undefined.
  def self.py_format(fmt : String, args : Array(AnyValue), tuple_arg : Bool = true) : String
    idx = 0
    conversions = 0
    fmt.scan(/%([-+ #0]*)(\*|\d+)?(?:\.(\*|\d+))?([sdixXoeEfFgGr%])/) { |m| conversions += 1 unless m[4] == "%" }
    fmt.scan(/%[-+ #0]*(?:\*|\d+)?(?:\.(?:\*|\d+))?([^%])/) do |m|
      char = m[1]
      unless "sdixXoeEfFgGr".includes?(char)
        raise TemplateError.new("unsupported format character '#{char}'", 0)
      end
    end
    if conversions == 0 && !tuple_arg && args.size == 1
      a = args[0].raw
      return fmt if a.is_a?(Array) || a.is_a?(Hash) || a.is_a?(Undefined) || a.is_a?(GeneratorValue)
      raise TemplateError.new("not all arguments converted during string formatting", 0)
    end
    out = String.build do |io|
      pos = 0
      fmt.scan(/%([-+ #0]*)(\*|\d+)?(?:\.(\*|\d+))?([sdixXoeEfFgGr%])/) do |m|
        io << fmt[pos...m.begin(0)]
        pos = m.end(0)
        md = m
        flags = md[1]? || ""
        width_spec = md[2]?
        prec_spec = md[3]?
        conv = md[4]?.try(&.[-1]) || "s"
        if conv == '%'
          io << "%"
          next
        end
        width : Int64? = nil
        prec : Int64? = nil
        if width_spec == "*"
          w = args[idx]? || raise TemplateError.new("not enough arguments for format string", 0)
          idx += 1
          width = w.raw.as?(Int64)
        elsif width_spec
          width = width_spec.try(&.to_i?).try(&.to_i64)
        end
        if prec_spec == "*"
          pv = args[idx]? || raise TemplateError.new("not enough arguments for format string", 0)
          idx += 1
          prec = pv.raw.as?(Int64)
        elsif prec_spec
          prec = prec_spec.try(&.to_i?).try(&.to_i64)
        end
        arg = args[idx]? || raise TemplateError.new("not enough arguments for format string", 0)
        idx += 1
        cfmt = "%#{flags}#{width ? width.to_s : ""}#{prec ? ".#{prec}" : ""}#{conv}"
        case conv
        when 's'
          body = stringify(arg)
          io << (width && body.size < width ? (flags.includes?('-') ? body.ljust(width) : body.rjust(width)) : body)
        when 'r'
          body = arg.raw.is_a?(String) ? py_repr_string(arg.raw.as(String)) : stringify(arg)
          io << (width && body.size < width ? (flags.includes?('-') ? body.ljust(width) : body.rjust(width)) : body)
        when 'd', 'i', 'u'
          n = arg.raw.as?(Int64) || arg.raw.as?(Float64).try(&.to_i64) ||
              (arg.raw.is_a?(Bool) ? (arg.raw ? 1i64 : 0i64) : nil) ||
              raise TemplateError.new("%d format: a number is required", 0)
          io << ::sprintf(cfmt, n)
        when 'x', 'X', 'o'
          n = arg.raw.as?(Int64) || raise TemplateError.new("an integer is required", 0)
          io << ::sprintf(cfmt, n)
        when 'e', 'E', 'f', 'F', 'g', 'G'
          f = arg.raw.as?(Float64) || arg.raw.as?(Int64).try(&.to_f64) ||
              (arg.raw.is_a?(Bool) ? (arg.raw ? 1.0 : 0.0) : nil) ||
              raise TemplateError.new("a float is required", 0)
          io << ::sprintf(cfmt, f)
        else
          io << stringify(arg)
        end
      end
      io << fmt[pos..]
    end
    if idx < args.size
      raise TemplateError.new("not all arguments converted during string formatting", 0)
    end
    out
  end

  # str.format: positional ({} and {N}) replacement with {{ }} escapes.
  def self.str_format(fmt : String, args : Array(AnyValue)) : String
    auto_idx = 0
    out = String.build do |io|
      i = 0
      while i < fmt.size
        c = fmt[i]
        if c == '{' && i + 1 < fmt.size
          if fmt[i + 1] == '{'
            io << '{'
            i += 2
          else
            j = i + 1
            while j < fmt.size && fmt[j].ascii_number?
              j += 1
            end
            if j < fmt.size && fmt[j] == '}'
              spec = fmt[(i + 1)...j]
              idx = spec.empty? ? auto_idx : spec.to_i
              auto_idx += 1 if spec.empty?
              arg = args[idx]? || raise TemplateError.new("format string index out of range", 0)
              io << stringify(arg)
              i = j + 1
            else
              io << c
              i += 1
            end
          end
        elsif c == '}' && i + 1 < fmt.size && fmt[i + 1] == '}'
          io << '}'
          i += 2
        else
          io << c
          i += 1
        end
      end
    end
    out
  end

  # Deep-converts plain Crystal values (nested hashes/arrays of mixed types)
  # into boxed template values.
  def self.wrap_value(x) : AnyValue
    case v = x
    when AnyValue then v
    when Array    then AnyValue.new(v.map { |e| wrap_value(e) })
    when Hash
      h = {} of String => AnyValue
      v.each { |k, e| h[k.to_s] = wrap_value(e) }
      AnyValue.new(h)
    when Nil, Bool, Int64, Float64, String then AnyValue.new(v)
    when Int32                             then AnyValue.new(v.to_i64)
    else
      raise TemplateError.new("value of type #{v.class} is not JSON-compatible", 0, kind: ErrorKind::Conversion)
    end
  end

  # Converts a JSON::Any value into a boxed template value.
  def self.to_json_any(value : AnyValue) : JSON::Any
    case raw = value.raw
    when Undefined
      raise TemplateError.new("'missing' is undefined", 0, kind: ErrorKind::Undefined) if raw.strict?
      JSON::Any.new(nil)
    when TupleValue then JSON::Any.new(raw.items.map { |item| to_json_any(item) })
    when GeneratorValue then JSON::Any.new(raw.materialize.map { |item| to_json_any(item) })
    when Array then JSON::Any.new(raw.map { |item| to_json_any(item) })
    when Hash
      object = {} of String => JSON::Any
      raw.each { |key, item| object[key] = to_json_any(item) }
      JSON::Any.new(object)
    when BigIntValue then JSON::Any.new(raw.value)
    when Nil, Bool, Int64, Float64, String then JSON::Any.new(raw)
    else
      raise TemplateError.new("value of type #{raw.class} is not JSON-compatible", 0, kind: ErrorKind::Conversion)
    end
  end

  def self.from_json_any(x : JSON::Any) : AnyValue
    raw = x.raw
    case raw
    when Nil then AnyValue.new(nil)
    when Bool, Int64, Float64, String then AnyValue.new(raw)
    when Array then AnyValue.new(raw.map { |e| from_json_any(e) })
    when Hash
      h = {} of String => AnyValue
      raw.each { |k, e| h[k] = from_json_any(e) }
      AnyValue.new(h)
    else
      raise TemplateError.new("JSON value of type #{raw.class} is unsupported", 0, kind: ErrorKind::Conversion)
    end
  end

  # Builds a boxed context hash from plain Crystal values.
  def self.context(h : Hash(String, V)) : Hash(String, AnyValue) forall V
    result = {} of String => AnyValue
    h.each { |k, v| result[k] = wrap_value(v) }
    result
  end

  def self.parse_expression(source : String, options : LexerOptions = LexerOptions.new) : Nodes::ExprNode
    Parser.parse_expression(source, options)
  end

  def self.evaluate_expression(source : String, variables : Hash(String, JSON::Any) = {} of String => JSON::Any,
                               strict : Bool = false, loader : Loader? = nil) : JSON::Any?
    Engine.new(loader, undefined: strict ? StrictUndefined.new : Undefined.new).evaluate_json(source, variables)
  end

  def self.evaluate_expression_value(source : String, variables : Hash(String, JSON::Any) = {} of String => JSON::Any,
                                     strict : Bool = false, loader : Loader? = nil) : AnyValue
    Engine.new(loader, undefined: strict ? StrictUndefined.new : Undefined.new).evaluate_expression(
      source, variables.transform_values { |item| from_json_any(item) }
    )
  end

  def self.render(source : String, variables : Hash(String, V) = {} of String => String,
                  loader : Loader? = nil) : String forall V
    Engine.new(loader).render_string(source, context(variables))
  end

  def self.render(source : String, variables : Hash(String, AnyValue),
                  loader : Loader? = nil) : String
    Engine.new(loader).render_string(source, variables)
  end
end
