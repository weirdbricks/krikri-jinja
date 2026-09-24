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

    def next_item : AnyValue
      item = @items[@pos]
      @pos = (@pos + 1) % @items.size
      item
    end

    def reset : AnyValue
      @pos = 0
      AnyValue.new(nil)
    end

    def current_value : AnyValue
      @items[@pos]
    end

    def call(args : Array(AnyValue), _kwargs : Hash(String, AnyValue), _ctx : Context) : AnyValue
      method = (args[0]? || AnyValue.new("")).raw.as?(String) || ""
      case method
      when "next" then next_item
      when "reset" then reset
      when "current" then current_value
      else
        raise TemplateError.new("unknown cycler method #{method.inspect}", 0)
      end
    end
  end

  # Emits its separator on the first call and empty strings afterwards.
  class Joiner < Callable
    def initialize(@sep : String)
      @first = true
    end

    def call(_args : Array(AnyValue), _kwargs : Hash(String, AnyValue), _ctx : Context) : AnyValue
      if @first
        @first = false
        AnyValue.new("")
      else
        AnyValue.new(@sep)
      end
    end
  end

  BUILTIN_GLOBALS = {} of String => AnyValue

  BUILTIN_GLOBALS["range"] = AnyValue.new(SimpleCallable.new("range") do |args, _kwargs, _ctx|
    coerced = args.map { |arg| arg.raw.is_a?(Bool) ? AnyValue.new(arg.raw.as(Bool) ? 1i64 : 0i64) : arg }
    start, stop, step = if coerced.size == 1
                          {0i64, coerced[0].raw.as?(Int64) || 0i64, 1i64}
                        elsif coerced.size >= 2
                          {coerced[0].raw.as?(Int64) || 0i64, coerced[1].raw.as?(Int64) || 0i64,
                           coerced.size >= 3 ? (coerced[2].raw.as?(Int64) || 1i64) : 1i64}
                        else
                          raise TemplateError.new("range expects 1-3 arguments", 0)
                        end
    raise TemplateError.new("'float' object cannot be interpreted as an integer", 0) if args.any?(&.raw.is_a?(Float64))
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
          ppair = pair.raw.as?(Array) || pair.raw.as?(TupleValue).try(&.items)
          if ppair && ppair.size == 2
            h[KrikriJinja.stringify(ppair[0])] = ppair[1]
          end
        end
      when TupleValue
        raw.items.each do |pair|
          ppair = pair.raw.as?(Array) || pair.raw.as?(TupleValue).try(&.items)
          if ppair && ppair.size == 2
            h[KrikriJinja.stringify(ppair[0])] = ppair[1]
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

  BUILTIN_GLOBALS["joiner"] = AnyValue.new(SimpleCallable.new("joiner") do |args, _kwargs, _ctx|
    sep = args[0]?.try(&.raw.as?(String)) || ", "
    AnyValue.new(Joiner.new(sep))
  end)

  def self.default_globals : Hash(String, AnyValue)
    BUILTIN_GLOBALS.dup
  end
end
