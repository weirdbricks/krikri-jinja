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
  register_test("even") { |v, _a, _k, _c| int_of(v) % 2 == 0 }
  register_test("odd") { |v, _a, _k, _c| int_of(v) % 2 == 1 }
  register_test("divisibleby") { |v, args, _k, _c| int_of(v) % int_of(args[0]) == 0 }
  register_test("string") { |v, _a, _k, _c| v.raw.is_a?(String) }
  register_test("number") { |v, _a, _k, _c| v.raw.is_a?(Int64) || v.raw.is_a?(Float64) || v.raw.is_a?(Bool) }
  register_test("integer") { |v, _a, _k, _c| v.raw.is_a?(Int64) }
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
    when {String, String} then a.same?(b) || a == b
    else false
    end
  end

  private def self.int_of(v : AnyValue) : Int64
    case raw = v.raw
    when Int64 then raw
    when Float64 then raw.to_i64
    when Bool then raw ? 1i64 : 0i64
    when String then raw.to_i64? || 0i64
    else 0i64
    end
  end
end
