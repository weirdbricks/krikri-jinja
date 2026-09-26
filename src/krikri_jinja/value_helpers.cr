module KrikriJinja
  # Truthiness: Python-style (0, "", [], {}, nil are falsy).
  def self.truthy?(value : AnyValue) : Bool
    case v = value.raw
    when Undefined
      raise TemplateError.new(KrikriJinja.undefined_message(v), 0, kind: ErrorKind::Undefined) if v.strict?
      false
    when Nil then false
    when Bool then v
    when Int64 then v != 0
    when BigIntValue then !v.zero?
    when Float64 then v != 0.0
    when String then !v.empty?
    when Array then !v.empty?
    when Hash then !v.empty?
    when TupleValue then !v.items.empty?
    when Markup then !v.value.empty?
    when HostObject then v.truthy?
    else true
    end
  end

  # Python's type name for a value, as error messages report it.
  def self.type_label(value : AnyValue) : String
    case value.raw
    when Nil                 then "NoneType"
    when Bool                then "bool"
    when Int64, BigIntValue  then "int"
    when Float64             then "float"
    when String, Markup      then "str"
    when Array               then "list"
    when Hash                then "dict"
    when TupleValue          then "tuple"
    else                          value.raw.class.name.split("::").last
    end
  end

  def self.undefined?(value : AnyValue) : Bool
    value.raw.is_a?(Undefined)
  end

  def self.stringify(value : AnyValue, escape : Bool = false) : String
    s = case v = value.raw
        when Undefined
          raise TemplateError.new(KrikriJinja.undefined_message(v), 0, kind: ErrorKind::Undefined) if v.strict?
          ""
        when Nil        then "None"
        when Bool       then v ? "True" : "False"
        when Int64      then v.to_s
        when BigIntValue
          check_int_str_limit(v.value)
          v.value
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

  # Int64-overflowing decimal strings are the engine's big-int
  # representation; Python reprs them unquoted.
  def self.big_int_string?(s : String) : Bool
    s.matches?(/^-?\d+$/) && s.to_i64?.nil?
  end

  # CPython 3.11+ refuses int->str beyond 4300 digits.
  def self.check_int_str_limit(s : String)
    raise TemplateError.new("Exceeds the limit (4300 digits) for integer string conversion", 0) if s.size > 4300
  end

  # CPython str repr: single quotes preferred, double when the value
  # contains ' but not ", backslash/quote/control chars escaped.
  def self.py_repr_string(s : String) : String
    quote = s.includes?('\'') && !s.includes?('"') ? '"' : '\''
    String.build do |io|
      io << quote
      s.each_char do |c|
        case c
        when '\\'      then io << "\\\\"
        when '\n'      then io << "\\n"
        when '\r'      then io << "\\r"
        when '\t'      then io << "\\t"
        when quote     then io << "\\#{quote}"
        when '\u007f'  then io << "\\x7f"
        else
          if c.ord < 0x20
            io << "\\x#{c.ord.to_s(16).rjust(2, '0')}"
          else
            io << c
          end
        end
      end
      io << quote
    end
  end

  # repr-style for lists/dicts inside stringification.
  def self.stringify_repr(value : AnyValue) : String
    case v = value.raw
    when String then py_repr_string(v)
    when Undefined
      raise TemplateError.new(KrikriJinja.undefined_message(v), 0, kind: ErrorKind::Undefined) if v.strict?
      "Undefined"
    when Markup then "Markup(#{py_repr_string(v.value)})"
    when HostObject then v.repr
    else stringify(value)
    end
  end

  # Dict keys are stored as strings; non-string Python keys get a marker
  # prefix so repr/lookup/json can recover their true type and value.
  KEY_MARKER = "\u0000"

  def self.dict_key(v : AnyValue) : String
    case k = v.raw
    when String then k
    when BigIntValue then "#{KEY_MARKER}i:#{k.value}"
    when Bool   then "#{KEY_MARKER}b:#{k ? "true" : "false"}"
    when Int64  then "#{KEY_MARKER}i:#{k}"
    when Float64
      # python: 1.0 == 1 and hashes equal, so canonicalize integral floats
      if k == k.trunc && k.abs <= 9223372036854775807.0
        "#{KEY_MARKER}i:#{k.trunc.to_i64}"
      else
        "#{KEY_MARKER}f:#{format_float(k)}"
      end
    when Nil    then "#{KEY_MARKER}n"
    when Undefined then "#{KEY_MARKER}u"
    when TupleValue
      "#{KEY_MARKER}t:" + k.items.map { |i| dict_key(i) }.join("\u0001")
    else "#{KEY_MARKER}s:#{stringify(v)}"
    end
  end

  # Alternate encoding for python's 1 == True key equivalence, or nil.
  def self.dict_key_alt(v : AnyValue) : String?
    case k = v.raw
    when Bool   then "#{KEY_MARKER}i:#{k ? 1 : 0}"
    when Int64  then (k == 1 || k == 0) ? "#{KEY_MARKER}b:#{k == 1}" : nil
    when BigIntValue then (k.value == "1" || k.zero?) ? "#{KEY_MARKER}b:#{k.value == "1"}" : nil
    else nil
    end
  end

  def self.decode_key(k : String) : AnyValue
    return AnyValue.new(k) unless k.starts_with?(KEY_MARKER)
    body = k[1..]
    kind, _, val = body.partition(":")
    case kind
    when "b" then AnyValue.new(val == "true")
    when "i" then AnyValue.new(BigIntValue.parse(val))
    when "f" then AnyValue.new(val.to_f64)
    when "n" then AnyValue.new(nil)
    when "u" then AnyValue.new(Undefined.new)
    when "t"
      items = body[2..].split("\u0001").map { |k| decode_key(k) }
      AnyValue.new(TupleValue.new(items))
    else AnyValue.new(val)
    end
  end

  def self.dict_key_repr(k : String) : String
    v = decode_key(k).raw
    case v
    when String then py_repr_string(v)
    else stringify(AnyValue.new(v))
    end
  end

  def self.format_float(v : Float64) : String
    return "inf" if v.infinite? == 1
    return "-inf" if v.infinite? == -1
    return "nan" if v.nan?
    return "-0.0" if v == 0.0 && (1.0 / v) < 0
    # match Python's repr: integral floats get ".0"; scientific notation
    # thresholds and 2-digit exponents follow Python too.
    if v == v.trunc && v.abs < 1e16
      "#{v.trunc.to_i64}.0"
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
    return s unless s.matches?(/[&<>"']/)
    String.build do |io|
      s.each_char do |char|
        case char
        when '&'  then io << "&amp;"
        when '<'  then io << "&lt;"
        when '>'  then io << "&gt;"
        when '"'  then io << "&#34;"
        when '\'' then io << "&#39;"
        else io << char
        end
      end
    end
  end

  # Python-like equality/comparison across values.
  def self.values_equal(a : AnyValue, b : AnyValue) : Bool
    x = a.raw
    y = b.raw
    if x.is_a?(HostObject) || y.is_a?(HostObject)
      order = x.is_a?(HostObject) ? x.compare(b) : y.as(HostObject).compare(a).try(&.-)
      return order == 0
    end
    if x.is_a?(Undefined) || y.is_a?(Undefined)
      if (x.is_a?(Undefined) && x.strict?) || (y.is_a?(Undefined) && y.strict?)
        offending = x.is_a?(Undefined) ? x.as(Undefined) : y.as(Undefined)
        raise TemplateError.new(KrikriJinja.undefined_message(offending), 0, kind: ErrorKind::Undefined)
      end
      return x.is_a?(Undefined) && y.is_a?(Undefined)
    end
    if x.is_a?(Nil) && y.is_a?(Nil)
      true
    elsif x.is_a?(BigIntValue) && y.is_a?(BigIntValue)
      x.value == y.value
    elsif x.is_a?(BigIntValue) && y.is_a?(Int64)
      big_string_int_cmp(x.value, y) == 0
    elsif x.is_a?(Int64) && y.is_a?(BigIntValue)
      big_string_int_cmp(y.value, x) == 0
    elsif x.is_a?(BigIntValue) && y.is_a?(Float64)
      x.to_f64 == y
    elsif x.is_a?(Float64) && y.is_a?(BigIntValue)
      x == y.to_f64
    elsif x.is_a?(BigIntValue) && y.is_a?(Bool)
      (y ? 1 : 0) == 1 && x.value == "1" || !y && x.zero?
    elsif x.is_a?(Bool) && y.is_a?(BigIntValue)
      (x ? 1 : 0) == 1 && y.value == "1" || !x && y.zero?
    elsif x.is_a?(Bool) && y.is_a?(Bool)
      x == y
    elsif x.is_a?(Int64) && y.is_a?(Int64)
      x == y
    elsif x.is_a?(Float64) && y.is_a?(Float64)
      x == y
    elsif (x.is_a?(Int64) && y.is_a?(Float64)) || (x.is_a?(Float64) && y.is_a?(Int64))
      if x.is_a?(Int64)
        xf, yf = x, y.as(Float64)
      else
        xf, yf = y.as(Int64), x.as(Float64)
      end
      # python int/float equality is exact; large integral floats are not
      # exactly representable, so compare through the float's exact value
      if yf == yf.trunc && yf.abs >= 9007199254740992.0
        xf == yf.to_i64 rescue false
      else
        xf.to_f64 == yf
      end
    elsif x.is_a?(String) && y.is_a?(String)
      x == y
    elsif x.is_a?(Array) && y.is_a?(Array)
      return false unless x.size == y.size
      x.zip(y).all? { |p, q| values_equal(p, q) }
    elsif x.is_a?(Hash) && y.is_a?(Hash)
      return false unless x.size == y.size
      x.all? { |k, v| y.has_key?(k) && values_equal(v, y[k]) }
    elsif x.is_a?(TupleValue) && y.is_a?(TupleValue)
      return false unless x.items.size == y.items.size
      x.items.zip(y.items).all? { |p, q| values_equal(p, q) }
    elsif (x.is_a?(Bool) && y.is_a?(Int64)) || (x.is_a?(Int64) && y.is_a?(Bool))
      (x.is_a?(Bool) ? (x ? 1 : 0) : x.as(Int64)) == (y.is_a?(Bool) ? (y ? 1 : 0) : y.as(Int64))
    elsif (x.is_a?(Markup) && y.is_a?(String))
      x.value == y
    elsif (x.is_a?(Markup) && y.is_a?(Markup))
      x.value == y.value
    elsif (x.is_a?(String) && y.is_a?(Markup))
      x == y.value
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
    if x.is_a?(HostObject) || y.is_a?(HostObject)
      order = x.is_a?(HostObject) ? x.compare(b) : y.as(HostObject).compare(a).try(&.-)
      return order if order
      raise TemplateError.new("'<' not supported between these operand types", 0)
    end
    if (x.is_a?(Undefined) && x.strict?) || (y.is_a?(Undefined) && y.strict?)
      offending = x.is_a?(Undefined) ? x.as(Undefined) : y.as(Undefined)
      raise TemplateError.new(KrikriJinja.undefined_message(offending), 0, kind: ErrorKind::Undefined)
    end
    if x.is_a?(BigIntValue) && y.is_a?(BigIntValue)
      big_string_cmp(x.value, y.value)
    elsif x.is_a?(BigIntValue) && y.is_a?(Int64)
      big_string_int_cmp(x.value, y)
    elsif x.is_a?(Int64) && y.is_a?(BigIntValue)
      -big_string_int_cmp(y.value, x)
    elsif x.is_a?(BigIntValue) && y.is_a?(Float64)
      (x.to_f64 <=> y) || 0
    elsif x.is_a?(Float64) && y.is_a?(BigIntValue)
      (x <=> y.to_f64) || 0
    elsif x.is_a?(BigIntValue) && y.is_a?(Bool)
      big_string_int_cmp(x.value, y ? 1i64 : 0i64)
    elsif x.is_a?(Bool) && y.is_a?(BigIntValue)
      -big_string_int_cmp(y.value, x ? 1i64 : 0i64)
    elsif x.is_a?(Int64) && y.is_a?(Int64)
      (x <=> y) || 0
    elsif x.is_a?(Float64) && y.is_a?(Float64)
      (x <=> y) || 0
    elsif x.is_a?(Int64) && y.is_a?(Float64)
      (x.to_f64 <=> y) || 0
    elsif x.is_a?(Float64) && y.is_a?(Int64)
      (x <=> y.to_f64) || 0
    elsif x.is_a?(String) && y.is_a?(String)
      (x <=> y) || 0
    elsif x.is_a?(Markup) && y.is_a?(String)
      (x.value <=> y) || 0
    elsif x.is_a?(String) && y.is_a?(Markup)
      (x <=> y.value) || 0
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
    elsif x.is_a?(TupleValue) && y.is_a?(TupleValue)
      i = 0
      while i < x.items.size && i < y.items.size
        c = compare_values(x.items[i], y.items[i])
        return c if c != 0
        i += 1
      end
      x.items.size <=> y.items.size
    else
      raise TemplateError.new("cannot compare #{x.class} and #{y.class}", 0)
    end
  end
  def self.big_string_cmp(a : String, b : String) : Int32
    aneg = a.starts_with?('-')
    bneg = b.starts_with?('-')
    return aneg ? -1 : 1 if aneg != bneg
    cmp = big_cmp(a.lstrip('-'), b.lstrip('-'))
    aneg ? -cmp : cmp
  end

  # Exact comparison of a decimal-string integer against an Int64.
  def self.big_string_int_cmp(s : String, i : Int64) : Int32
    sneg = s.starts_with?('-')
    ineg = i < 0
    return sneg ? -1 : 1 if sneg != ineg
    mag = KrikriJinja.big_cmp(s.lstrip('-'), (i >= 0 ? i : -i).to_s)
    sneg ? -mag : mag
  end

  # Containment (`in`).
  def self.contains?(container : AnyValue, item : AnyValue) : Bool
    case c = container.raw
    when Markup
      i = item.raw
      i.is_a?(String) ? c.value.includes?(i) : false
    when String
      i = item.raw
      i.is_a?(String) && c.includes?(i)
    when Array
      c.any? { |x| values_equal(x, item) }
    when TupleValue
      c.items.any? { |x| values_equal(x, item) }
    when Hash
      c.has_key?(dict_key(item))
    when Undefined
      raise TemplateError.new(KrikriJinja.undefined_message(c), 0, kind: ErrorKind::Undefined) if c.strict?
      false
    else
      raise TemplateError.new("argument of type #{c.class} is not iterable", 0)
    end
  end
end
