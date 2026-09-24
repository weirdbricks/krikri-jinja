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
  VERSION = "0.1.0"

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
