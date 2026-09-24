module KrikriJinja
  # Truthiness: Python-style (0, "", [], {}, nil are falsy).
  def self.truthy?(value : AnyValue) : Bool
    case v = value.raw
    when Undefined then false
    when Nil then false
    when Bool then v
    when Int64 then v != 0
    when Float64 then v != 0.0
    when String then !v.empty?
    when Array then !v.empty?
    when Hash then !v.empty?
    else true
    end
  end

  # Undefined is represented as nil; strict access raises from Context.
  def self.undefined?(value : AnyValue) : Bool
    value.raw.nil? || value.raw.is_a?(Undefined)
  end

  def self.stringify(value : AnyValue, escape : Bool = false) : String
    s = case v = value.raw
        when Undefined  then ""
        when Nil        then "None"
        when Bool       then v ? "True" : "False"
        when Int64      then v.to_s
        when Float64    then format_float(v)
        when String     then v
        when Array      then "[" + v.map { |x| stringify_repr(x) }.join(", ") + "]"
        when TupleValue
          if v.items.size == 1
            "(" + stringify_repr(v.items[0]) + ",)"
          else
            "(" + v.items.map { |x| stringify_repr(x) }.join(", ") + ")"
          end
        when Hash       then "{" + v.map { |k, x| "#{dict_key_repr(k)}: #{stringify_repr(x)}" }.join(", ") + "}"
        when Callable   then "<callable>"
        when Markup     then v.value
        when LoopObject then "<loop>"
        else v.to_s
        end
    escape ? escape_html(s) : s
  end

  # repr-style for lists/dicts inside stringification.
  def self.stringify_repr(value : AnyValue) : String
    case v = value.raw
    when String then "'#{v}'"
    when Undefined then "Undefined"
    else stringify(value)
    end
  end

  # Dict keys are stored as strings; non-string Python keys get a marker
  # prefix so repr/lookup/json can recover their true type and value.
  KEY_MARKER = "\u0000"

  def self.dict_key(v : AnyValue) : String
    case k = v.raw
    when String then k
    when Bool   then "#{KEY_MARKER}b:#{k ? "true" : "false"}"
    when Int64  then "#{KEY_MARKER}i:#{k}"
    when Float64
      # python: 1.0 == 1 and hashes equal, so canonicalize integral floats
      k == k.trunc ? "#{KEY_MARKER}i:#{k.trunc.to_i64}" : "#{KEY_MARKER}f:#{format_float(k)}"
    when Nil    then "#{KEY_MARKER}n"
    when Undefined then "#{KEY_MARKER}u"
    else "#{KEY_MARKER}s:#{stringify(v)}"
    end
  end

  def self.decode_key(k : String) : AnyValue
    return AnyValue.new(k) unless k.starts_with?(KEY_MARKER)
    body = k[1..]
    kind, _, val = body.partition(":")
    case kind
    when "b" then AnyValue.new(val == "true")
    when "i" then AnyValue.new(val.to_i64)
    when "f" then AnyValue.new(val.to_f64)
    when "n" then AnyValue.new(nil)
    when "u" then AnyValue.new(Undefined.new)
    else AnyValue.new(val)
    end
  end

  def self.dict_key_repr(k : String) : String
    case v = decode_key(k).raw
    when String then "'#{v}'"
    else stringify(AnyValue.new(v))
    end
  end

  def self.format_float(v : Float64) : String
    return "-0.0" if v == 0.0 && (1.0 / v) < 0
    # match Python's repr: integral floats get ".0"; scientific notation
    # thresholds and 2-digit exponents follow Python too.
    if v == v.trunc && v.abs < 1e16
      "#{v.trunc.to_i}.0"
    else
      s = v.to_s
      if (m = s.match(/^(\-?[0-9.]+)e([+-]?\d+)$/))
        mant = m[1]
        mant = mant.sub(/\.0$/, "") if mant.ends_with?(".0")
        mant = mant.sub(/\.$/, "") if mant.ends_with?(".")
        exp = m[2]
        sign = exp.starts_with?('-') ? '-' : '+'
        digits = exp.lstrip("+-").rjust(2, '0')
        "#{mant}e#{sign}#{digits}"
      else
        s
      end
    end
  end

  def self.escape_html(s : String) : String
    s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      .gsub("\"", "&#34;").gsub("'", "&#39;")
  end

  # Python-like equality/comparison across values.
  def self.values_equal(a : AnyValue, b : AnyValue) : Bool
    x = a.raw
    y = b.raw
    if x.is_a?(Undefined) || y.is_a?(Undefined)
      return x.is_a?(Undefined) && y.is_a?(Undefined)
    end
    if x.is_a?(Nil) && y.is_a?(Nil)
      true
    elsif x.is_a?(Bool) && y.is_a?(Bool)
      x == y
    elsif x.is_a?(Int64) && y.is_a?(Int64)
      x == y
    elsif x.is_a?(Float64) && y.is_a?(Float64)
      x == y
    elsif (x.is_a?(Int64) && y.is_a?(Float64)) || (x.is_a?(Float64) && y.is_a?(Int64))
      x.to_f64 == y.to_f64
    elsif x.is_a?(String) && y.is_a?(String)
      x == y
    elsif x.is_a?(Array) && y.is_a?(Array)
      return false unless x.size == y.size
      x.zip(y).all? { |p, q| values_equal(p, q) }
    elsif x.is_a?(Hash) && y.is_a?(Hash)
      return false unless x.size == y.size
      x.all? { |k, v| y.has_key?(k) && values_equal(v, y[k]) }
    elsif (x.is_a?(Bool) && y.is_a?(Int64)) || (x.is_a?(Int64) && y.is_a?(Bool))
      (x.is_a?(Bool) ? (x ? 1 : 0) : x.as(Int64)) == (y.is_a?(Bool) ? (y ? 1 : 0) : y.as(Int64))
    elsif (x.is_a?(Bool) && y.is_a?(Float64))
      (x ? 1.0 : 0.0) == y
    elsif (x.is_a?(Float64) && y.is_a?(Bool))
      x == (y ? 1.0 : 0.0)
    else
      false
    end
  end

  # Ordering: returns -1, 0, 1. Raises on incomparable types (Python-like).
  def self.compare_values(a : AnyValue, b : AnyValue) : Int32
    x = a.raw
    y = b.raw
    if x.is_a?(Int64) && y.is_a?(Int64)
      (x <=> y) || 0
    elsif x.is_a?(Float64) && y.is_a?(Float64)
      (x <=> y) || 0
    elsif x.is_a?(Int64) && y.is_a?(Float64)
      (x.to_f64 <=> y) || 0
    elsif x.is_a?(Float64) && y.is_a?(Int64)
      (x <=> y.to_f64) || 0
    elsif x.is_a?(String) && y.is_a?(String)
      (x <=> y) || 0
    elsif x.is_a?(Bool) && y.is_a?(Bool)
      (x ? 1 : 0) <=> (y ? 1 : 0)
    elsif (x.is_a?(Bool) && y.is_a?(Int64)) || (x.is_a?(Int64) && y.is_a?(Bool))
      ((x.is_a?(Bool) ? (x ? 1 : 0) : x.as(Int64)) <=> (y.is_a?(Bool) ? (y ? 1 : 0) : y.as(Int64))) || 0
    elsif x.is_a?(Bool) && y.is_a?(Float64)
      ((x ? 1.0 : 0.0) <=> y) || 0
    elsif x.is_a?(Float64) && y.is_a?(Bool)
      (x <=> (y ? 1.0 : 0.0)) || 0
    elsif x.is_a?(Array) && y.is_a?(Array)
      i = 0
      while i < x.size && i < y.size
        c = compare_values(x[i], y[i])
        return c if c != 0
        i += 1
      end
      x.size <=> y.size
    else
      raise TemplateError.new("cannot compare #{x.class} and #{y.class}", 0)
    end
  end
  # Containment (`in`).
  def self.contains?(container : AnyValue, item : AnyValue) : Bool
    case c = container.raw
    when String
      i = item.raw
      i.is_a?(String) && c.includes?(i)
    when Array
      c.any? { |x| values_equal(x, item) }
    when Hash
      c.has_key?(dict_key(item))
    when Undefined
      false
    else
      raise TemplateError.new("argument of type #{c.class} is not iterable", 0)
    end
  end
end
