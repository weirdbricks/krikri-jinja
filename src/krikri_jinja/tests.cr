module KrikriJinja
  # Built-in tests (the `is` operator). All values are boxed AnyValue.
  alias TestFn = Proc(AnyValue, Array(AnyValue), Hash(String, AnyValue), Context, Bool)

  BUILTIN_TESTS = {} of String => TestFn

  private def self.register_test(name : String, &block : TestFn)
    BUILTIN_TESTS[name] = block
  end

  register_test("defined") { |v, _a, _k, _c| !v.raw.is_a?(Undefined) }
  register_test("undefined") { |v, _a, _k, _c| v.raw.is_a?(Undefined) }
  register_test("none") { |v, _a, _k, _c| v.raw.nil? }
  register_test("even") { |v, _a, _k, _c| mod_2(v) == 0 }
  register_test("odd") { |v, _a, _k, _c| mod_2(v) == 1 }
  register_test("divisibleby") { |v, args, _k, _c| num_mod(v, args[0]) == 0 }
  register_test("string") { |v, _a, _k, _c| v.raw.is_a?(String) }
  register_test("number") { |v, _a, _k, _c| v.raw.is_a?(Int64) || v.raw.is_a?(BigIntValue) || v.raw.is_a?(Float64) || v.raw.is_a?(Bool) }
  register_test("integer") { |v, _a, _k, _c| v.raw.is_a?(Int64) || v.raw.is_a?(BigIntValue) }
  register_test("float") { |v, _a, _k, _c| v.raw.is_a?(Float64) }
  register_test("boolean") { |v, _a, _k, _c| v.raw.is_a?(Bool) }
  register_test("mapping") { |v, _a, _k, _c| v.raw.is_a?(Hash) }
  register_test("sequence") { |v, _a, _k, _c| v.raw.is_a?(Array) || v.raw.is_a?(String) || v.raw.is_a?(Hash) || v.raw.is_a?(TupleValue) || v.raw.is_a?(Undefined) }
  register_test("iterable") { |v, _a, _k, _c| v.raw.is_a?(Array) || v.raw.is_a?(String) || v.raw.is_a?(Hash) || v.raw.is_a?(TupleValue) || v.raw.is_a?(GeneratorValue) || v.raw.is_a?(Undefined) }
  register_test("callable") { |v, _a, _k, _c| v.raw.is_a?(Callable) || v.raw.is_a?(Undefined) }
  register_test("sameas") { |v, args, _k, _c| same_as?(v.raw, args[0].raw) }
  register_test("true") { |v, _a, _k, _c| v.raw == true }
  register_test("false") { |v, _a, _k, _c| v.raw == false }
  register_test("eq") { |v, args, _k, _c| values_equal(v, args[0]) }
  register_test("equalto") { |v, args, _k, _c| values_equal(v, args[0]) }
  register_test("==") { |v, args, _k, _c| values_equal(v, args[0]) }
  register_test("ne") { |v, args, _k, _c| !values_equal(v, args[0]) }
  register_test("!=") { |v, args, _k, _c| !values_equal(v, args[0]) }
  register_test("lt") { |v, args, _k, _c| compare_values(v, args[0]) < 0 }
  register_test("lessthan") { |v, args, _k, _c| compare_values(v, args[0]) < 0 }
  register_test("<") { |v, args, _k, _c| compare_values(v, args[0]) < 0 }
  register_test("le") { |v, args, _k, _c| compare_values(v, args[0]) <= 0 }
  register_test("<=") { |v, args, _k, _c| compare_values(v, args[0]) <= 0 }
  register_test("gt") { |v, args, _k, _c| compare_values(v, args[0]) > 0 }
  register_test("greaterthan") { |v, args, _k, _c| compare_values(v, args[0]) > 0 }
  register_test(">") { |v, args, _k, _c| compare_values(v, args[0]) > 0 }
  register_test("ge") { |v, args, _k, _c| compare_values(v, args[0]) >= 0 }
  register_test(">=") { |v, args, _k, _c| compare_values(v, args[0]) >= 0 }
  register_test("in") { |v, args, _k, _c| contains?(args[0], v) }
  register_test("lower") { |v, _a, _k, _c| v.raw.is_a?(String) && v.raw.as(String) == v.raw.as(String).downcase }
  register_test("upper") { |v, _a, _k, _c| v.raw.is_a?(String) && v.raw.as(String) == v.raw.as(String).upcase }
  register_test("escaped") { |v, _a, _k, _c| v.raw.is_a?(Markup) }
  register_test("filter") { |v, _a, _k, _c| v.raw.is_a?(String) && !!BUILTIN_FILTERS[v.raw.as(String)]? }
  register_test("test") { |v, _a, _k, _c| v.raw.is_a?(String) && !!BUILTIN_TESTS[v.raw.as(String)]? }

  private def self.same_as?(a : AnyV, b : AnyV) : Bool
    case {a, b}
    when {Nil, Nil} then true
    when {Bool, Bool} then a == b
    when {Markup, Markup} then a.same?(b)
    when {Callable, Callable} then a.same?(b)
    when {Int64, Int64} then a == b
    when {BigIntValue, BigIntValue} then a.value == b.value
    when {String, String} then a.same?(b) || a == b
    else false
    end
  end

  # python tests use the raw value modulo, so floats keep their fraction
  @[Link("m")]
  lib PyLibM
    fun fmod(x : Float64, y : Float64) : Float64
  end

  private def self.num_mod(v : AnyValue, other : AnyValue) : Float64 | Int64
    if (xs = decimal_arg(v)) && (ys = decimal_arg(other))
      raise TemplateError.new("integer modulo by zero", 0) if ys == "0" || ys == "-0"
      _, r = KrikriJinja.big_divmod(xs, ys)
      if (ri = r.to_i64?)
        return ri
      end
      return r == "0" ? 0i64 : 1i64
    end
    x = v.raw.as?(Int64) || v.raw.as?(Float64) || (v.raw.is_a?(Bool) ? (v.raw.as(Bool) ? 1i64 : 0i64) : nil) ||
        raise TemplateError.new("unsupported operand type(s) for %", 0)
    y = other.raw.as?(Int64) || other.raw.as?(Float64) || (other.raw.is_a?(Bool) ? (other.raw.as(Bool) ? 1i64 : 0i64) : nil) ||
        raise TemplateError.new("unsupported operand type(s) for %", 0)
    if x.is_a?(Int64) && y.is_a?(Int64)
      r = x % y
      r = r + y.abs if r != 0 && (r < 0) != (y < 0)
      r
    else
      xf = x.to_f64
      yf = y.to_f64
      raise TemplateError.new("float modulo by zero", 0) if yf == 0.0
      r = PyLibM.fmod(xf, yf)
      r = r + yf.abs if r != 0 && (r < 0) != (yf < 0)
      r
    end
  end

  private def self.decimal_arg(v : AnyValue) : String?
    v.raw.as?(Int64).try(&.to_s) || v.raw.as?(BigIntValue).try(&.value) ||
      (s = v.raw.as?(String); s if s && KrikriJinja.big_int_string?(s))
  end

  private def self.mod_2(v : AnyValue)
    if s = v.raw.as?(String)
      return (s.lstrip('-')[-1] - '0') % 2 if KrikriJinja.big_int_string?(s)
    elsif s = v.raw.as?(BigIntValue)
      return (s.digits[-1] - '0') % 2
    end
    num_mod(v, AnyValue.new(2i64))
  end

  private def self.int_of(v : AnyValue) : Int64 | BigIntValue
    case raw = v.raw
    when Int64 then raw
    when BigIntValue then raw
    when Float64 then raw.to_i64
    when Bool then raw ? 1i64 : 0i64
    when String then raw.to_i64? || 0i64
    else 0i64
    end
  end
end
