require "./evaluator"

module KrikriJinja
  # Mutable namespace object for {% set ns.attr = ... %} across scopes.
  class Namespace < Callable
    property data : Hash(String, AnyValue)

    def initialize(@data = {} of String => AnyValue)
    end

    def call(_args, _kwargs, _ctx) : AnyValue
      raise TemplateError.new("namespace object is not callable", 0)
    end
  end

  class SimpleCallable < Callable
    getter name : String

    def initialize(@name : String, &@impl : Proc(Array(AnyValue), Hash(String, AnyValue), Context, AnyValue))
    end

    def call(args : Array(AnyValue), kwargs : Hash(String, AnyValue), ctx : Context) : AnyValue
      @impl.call(args, kwargs, ctx)
    end
  end

  class Cycler < Callable
    @pos = 0

    def initialize(@items : Array(AnyValue))
    end

    def call(args : Array(AnyValue), _kwargs : Hash(String, AnyValue), _ctx : Context) : AnyValue
      method = (args[0]? || AnyValue.new("")).raw.as?(String) || ""
      case method
      when "next"
        item = @items[@pos]
        @pos = (@pos + 1) % @items.size
        item
      when "reset"
        @pos = 0
        AnyValue.new(nil)
      when "current"
        @items[@pos]
      else
        raise TemplateError.new("unknown cycler method #{method.inspect}", 0)
      end
    end
  end

  BUILTIN_GLOBALS = {} of String => AnyValue

  BUILTIN_GLOBALS["range"] = AnyValue.new(SimpleCallable.new("range") do |args, _kwargs, _ctx|
    start, stop, step = if args.size == 1
                          {0i64, args[0].raw.as?(Int64) || 0i64, 1i64}
                        elsif args.size >= 2
                          {args[0].raw.as?(Int64) || 0i64, args[1].raw.as?(Int64) || 0i64,
                           args.size >= 3 ? (args[2].raw.as?(Int64) || 1i64) : 1i64}
                        else
                          raise TemplateError.new("range expects 1-3 arguments", 0)
                        end
    raise TemplateError.new("range step cannot be zero", 0) if step == 0
    result = [] of AnyValue
    if step > 0
      i = start
      while i < stop
        result << AnyValue.new(i)
        i += step
      end
    else
      i = start
      while i > stop
        result << AnyValue.new(i)
        i += step
      end
    end
    AnyValue.new(result)
  end)

  BUILTIN_GLOBALS["dict"] = AnyValue.new(SimpleCallable.new("dict") do |args, kwargs, _ctx|
    h = {} of String => AnyValue
    args.each do |arg|
      case raw = arg.raw
      when Hash then raw.each { |k, v| h[k] = v }
      when Array
        raw.each do |pair|
          if pair.raw.is_a?(Array) && pair.raw.as(Array).size == 2
            arr = pair.raw.as(Array)
            h[KrikriJinja.stringify(arr[0])] = arr[1]
          end
        end
      end
    end
    kwargs.each { |k, v| h[k] = v }
    AnyValue.new(h)
  end)

  BUILTIN_GLOBALS["namespace"] = AnyValue.new(SimpleCallable.new("namespace") do |args, kwargs, _ctx|
    ns = Namespace.new
    args.each do |arg|
      if arg.raw.is_a?(Hash)
        arg.raw.as(Hash).each { |k, v| ns.data[k] = v }
      end
    end
    kwargs.each { |k, v| ns.data[k] = v }
    AnyValue.new(ns)
  end)

  BUILTIN_GLOBALS["lipsum"] = AnyValue.new(SimpleCallable.new("lipsum") do |_args, _kwargs, _ctx|
    AnyValue.new(Markup.new("<p>lorem ipsum dolor sit amet...</p>"))
  end)

  BUILTIN_GLOBALS["cycler"] = AnyValue.new(SimpleCallable.new("cycler") do |args, _kwargs, _ctx|
    AnyValue.new(Cycler.new(args))
  end)

  def self.default_globals : Hash(String, AnyValue)
    BUILTIN_GLOBALS.dup
  end
end
