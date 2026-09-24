require "./krikri_jinja/lexer"
require "./krikri_jinja/nodes"
require "./krikri_jinja/parser"
require "./krikri_jinja/context"
require "./krikri_jinja/value_helpers"
require "./krikri_jinja/filters"
require "./krikri_jinja/tests"
require "./krikri_jinja/evaluator"
require "./krikri_jinja/globals"

module KrikriJinja
  VERSION = "0.2.0"

  def self.filesizeformat(bytes : Int64, base : Int64, prefixes : Array(String), binary : Bool) : String
    return "0 Bytes" if bytes == 0
    units = ["Bytes"] + prefixes
    i = 0
    value = bytes.to_f64
    while value.abs >= base && i < units.size - 1
      value /= base
      i += 1
    end
    if i == 0
      bytes == 1 ? "1 Byte" : "#{bytes} Bytes"
    else
      "#{value.round(1)} #{units[i]}"
    end
  end

  # Python %-style formatting (the `format` filter).
  def self.py_format(fmt : String, args : Array(AnyValue)) : String
    idx = 0
    fmt.gsub(/%[-+ #0]*\d*(?:\.\d+)?[sdixXoeEfFgGr%]/) do |m|
      if m == "%%"
        "%"
      else
        arg = args[idx]? || AnyValue.new(nil)
        idx += 1
        conv = m[-1]
        flags = m[1...m.size - 1]
        body = case conv
               when 's', 'r'
                 s = stringify(arg)
                 conv == 'r' ? "'#{s}'" : s
               when 'd', 'i', 'u'
                 n = arg.raw.as?(Int64) || arg.raw.as?(Float64).try(&.to_i64) || 0i64
                 n.to_s
               when 'x' then (arg.raw.as?(Int64) || 0i64).to_s(16)
               when 'X' then (arg.raw.as?(Int64) || 0i64).to_s(16).upcase
               when 'o' then (arg.raw.as?(Int64) || 0i64).to_s(8)
               when 'e', 'E', 'f', 'F', 'g', 'G'
                 f = arg.raw.as?(Float64) || arg.raw.as?(Int64).try(&.to_f64) || 0.0
                 prec_match = flags.match(/\.(\d+)/)
                 prec = (prec_match.try(&.[1].to_i) || 6)
                 case conv
                 when 'f', 'F' then f.round(prec).to_s
                 else f.to_s
                 end
               else stringify(arg)
               end
        if width_match = flags.match(/(\d+)$/)
          width = width_match[1].to_i
          if flags.includes?('0') && {'d', 'i', 'u', 'x', 'X', 'o', 'f', 'F'}.includes?(conv)
            sign = body.starts_with?("-") ? "-" : ""
            digits = body.lstrip('-')
            body = sign + digits.rjust(width - sign.size, '0')
          elsif body.size < width
            body = flags.includes?('-') ? body.ljust(width) : body.rjust(width)
          end
        end
        body
      end
    end
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
    else AnyValue.new(v.to_s)
    end
  end

  # Builds a boxed context hash from plain Crystal values.
  def self.context(h : Hash(String, V)) : Hash(String, AnyValue) forall V
    result = {} of String => AnyValue
    h.each { |k, v| result[k] = wrap_value(v) }
    result
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
