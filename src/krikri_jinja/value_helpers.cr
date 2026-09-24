module KrikriJinja
  # Truthiness: Python-style (0, "", [], {}, nil are falsy).
  def self.truthy?(value : AnyValue) : Bool
    case v = value.raw
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
    value.raw.nil?
  end

  def self.stringify(value : AnyValue, escape : Bool = false) : String
    s = case v = value.raw
        when Nil        then "None"
        when Bool       then v ? "True" : "False"
        when Int64      then v.to_s
        when Float64    then format_float(v)
        when String     then v
        when Array      then "[" + v.map { |x| stringify_repr(x) }.join(", ") + "]"
        when Hash       then "{" + v.map { |k, x| "'#{k}': #{stringify_repr(x)}" }.join(", ") + "}"
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
    else stringify(value)
    end
  end
  def self.format_float(v : Float64) : String
    # match Python's repr for common cases: integral floats get ".0"
    if v == v.trunc && v.abs < 1e16
      "#{v.trunc.to_i}.0"
    else
      v.to_s
    end
  end

  def self.escape_html(s : String) : String
    s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      .gsub("\"", "&quot;").gsub("'", "&#39;")
  end

  # Python-like equality/comparison across values.
  def self.values_equal(a : AnyValue, b : AnyValue) : Bool
    x = a.raw
    y = b.raw
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
      (x ? 1 : 0) == (y ? 1 : 0)
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
      item.raw.is_a?(String) && c.has_key?(item.raw.as(String))
    else
      raise TemplateError.new("argument of type #{c.class} is not iterable", 0)
    end
  end
end
