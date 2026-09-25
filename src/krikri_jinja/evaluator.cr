module KrikriJinja
  alias FunctionFn = Proc(Array(AnyValue), Hash(String, AnyValue), Context, AnyValue)
  alias JsonFunctionFn = Proc(Array(JSON::Any), Hash(String, JSON::Any), JSON::Any)

  class LoopObject
    getter items : Array(AnyValue)
    property index : Int32
    getter depth : Int32
    property parent : LoopObject?
    property last_changed : AnyValue?
    property undefined : Undefined

    def initialize(@items, @index, @parent = nil, @depth = 1, @undefined : Undefined = Undefined.new)
    end

    def length : Int64
      @items.size.to_i64
    end

    def get(name : String) : AnyValue?
      case name
      when "index"     then AnyValue.new((@index + 1).to_i64)
      when "index0"    then AnyValue.new(@index.to_i64)
      when "revindex"  then AnyValue.new((@items.size - @index).to_i64)
      when "revindex0" then AnyValue.new((@items.size - @index - 1).to_i64)
      when "first"     then AnyValue.new(@index == 0)
      when "last"      then AnyValue.new(@index == @items.size - 1)
      when "length"    then AnyValue.new(length)
      when "depth"     then AnyValue.new(@depth.to_i64)
      when "depth0"    then AnyValue.new((@depth - 1).to_i64)
      when "previtem"  then @index > 0 ? @items[@index - 1] : AnyValue.new(@undefined)
      when "nextitem"  then @index < @items.size - 1 ? @items[@index + 1] : AnyValue.new(@undefined)
      end
    end

    def to_ctx_hash : Hash(String, AnyValue)
      h = {
        "index"     => AnyValue.new((@index + 1).to_i64),
        "index0"    => AnyValue.new(@index.to_i64),
        "revindex"  => AnyValue.new((@items.size - @index).to_i64),
        "revindex0" => AnyValue.new((@items.size - @index - 1).to_i64),
        "first"     => AnyValue.new(@index == 0),
        "last"      => AnyValue.new(@index == @items.size - 1),
        "length"    => AnyValue.new(length),
        "depth"     => AnyValue.new(@depth.to_i64),
        "depth0"    => AnyValue.new((@depth - 1).to_i64),
      } of String => AnyValue
      h["previtem"] = @index > 0 ? @items[@index - 1] : AnyValue.new(@undefined)
      h["nextitem"] = @index < @items.size - 1 ? @items[@index + 1] : AnyValue.new(@undefined)
      h
    end
  end

  # Callable `loop` for recursive for-loops: {{ loop(item.children) }}
  class LoopCallable < Callable
    getter items : Array(AnyValue)
    getter depth : Int32
    property parent : LoopCallable?
    property index : Int32 = 0
    property last_changed : AnyValue?
    property sink : ::IO
    property undefined : Undefined

    def initialize(@items, @body : Array(Nodes::Node), @ctx : Context, @engine : Engine,
                   @targets : Array(TargetSpec), @parent = nil, @depth = 1, @sink : IO = IO::Memory.new,
                   @undefined : Undefined = Undefined.new)
    end

    def length : Int64
      @items.size.to_i64
    end

    def get(name : String) : AnyValue?
      case name
      when "index"     then AnyValue.new((@index + 1).to_i64)
      when "index0"    then AnyValue.new(@index.to_i64)
      when "revindex"  then AnyValue.new((@items.size - @index).to_i64)
      when "revindex0" then AnyValue.new((@items.size - @index - 1).to_i64)
      when "first"     then AnyValue.new(@index == 0)
      when "last"      then AnyValue.new(@index == @items.size - 1)
      when "length"    then AnyValue.new(length)
      when "depth"     then AnyValue.new(@depth.to_i64)
      when "depth0"    then AnyValue.new((@depth - 1).to_i64)
      when "previtem"  then @index > 0 ? @items[@index - 1] : AnyValue.new(@undefined)
      when "nextitem"  then @index < @items.size - 1 ? @items[@index + 1] : AnyValue.new(@undefined)
      end
    end

    def to_ctx_hash : Hash(String, AnyValue)
      h = {
        "index"     => AnyValue.new((@index + 1).to_i64),
        "index0"    => AnyValue.new(@index.to_i64),
        "revindex"  => AnyValue.new((@items.size - @index).to_i64),
        "revindex0" => AnyValue.new((@items.size - @index - 1).to_i64),
        "first"     => AnyValue.new(@index == 0),
        "last"      => AnyValue.new(@index == @items.size - 1),
        "length"    => AnyValue.new(length),
        "depth"     => AnyValue.new(@depth.to_i64),
        "depth0"    => AnyValue.new((@depth - 1).to_i64),
      } of String => AnyValue
      h["previtem"] = @index > 0 ? @items[@index - 1] : AnyValue.new(@undefined)
      h["nextitem"] = @index < @items.size - 1 ? @items[@index + 1] : AnyValue.new(@undefined)
      h
    end

    def call(args : Array(AnyValue), _kwargs : Hash(String, AnyValue), ctx : Context) : AnyValue
      first = args[0]?
      sub_items : Array(AnyValue) = if first.nil? || first.raw.is_a?(Undefined) || first.raw.is_a?(Nil)
                                      raise TemplateError.new("loop() argument is not iterable", 0)
                                    elsif first.raw.is_a?(Array)
                                      first.raw.as(Array)
                                    elsif first.raw.is_a?(String)
                                      first.raw.as(String).chars.map { |c| AnyValue.new(c.to_s) }
                                    else
                                      args
                                    end
      sub = LoopCallable.new(sub_items,
                             @body, ctx, @engine, @targets, self, @depth + 1, @sink, ctx.undefined)
      old_loop = ctx["loop"]?
      sub_value = AnyValue.new(sub)
      sub_evaluator = Evaluator.new(ctx, @engine, @sink)
      ctx.push_scope
      begin
        sub.items.each_with_index do |item, i|
          sub.index = i
          KrikriJinja.assign_targets(ctx, @targets, item)
          ctx["loop"] = sub_value
          sub_evaluator.render_nodes(@body)
        end
      ensure
        ctx.pop_scope
        if old_loop
          ctx.scopes[0]["loop"] = old_loop
        end
      end
      AnyValue.new(Markup.new(""))
    end
  end

  # A string produced by a macro call or `|safe`, exempt from escaping.
  class Markup
    getter value : String

    def initialize(@value)
    end
  end

  class MacroCallable < Callable
    getter name : String
    getter params : Array(Tuple(String, ExprNode?))
    getter body : Array(Nodes::Node)
    getter closure : Context

    def initialize(@name, @params, @body, @closure)
    end

    def references_special?(body : Array(Nodes::Node), name : String) : Bool
      body.any? { |n| node_references?(n, name) }
    end

    private def node_references?(n : Nodes::Node, name : String) : Bool
      case n
      when Nodes::OutputNode
        expr_references?(n.as(Nodes::OutputNode).expr, name)
      when Nodes::SetNode
        n.as(Nodes::SetNode).targets.includes?(name)
      when Nodes::IfNode
        n.as(Nodes::IfNode).branches.any? do |_, b|
          b.any? { |x| node_references?(x, name) }
        end || (n.as(Nodes::IfNode).orelse || [] of Nodes::Node).any? { |x| node_references?(x, name) }
      when Nodes::ForNode
        n = n.as(Nodes::ForNode)
        n.body.any? { |x| node_references?(x, name) } ||
          (n.orelse || [] of Nodes::Node).any? { |x| node_references?(x, name) } ||
          expr_references?(n.iter, name) || (n.test.try { |t| expr_references?(t, name) } || false)
      else
        false
      end
    end

    private def expr_references?(e : Nodes::ExprNode, name : String) : Bool
      case e
      when Nodes::NameNode
        e.as(Nodes::NameNode).name == name
      when Nodes::BinOpNode
        n = e.as(Nodes::BinOpNode)
        expr_references?(n.left, name) || expr_references?(n.right, name)
      when Nodes::UnaryOpNode
        expr_references?(e.as(Nodes::UnaryOpNode).operand, name)
      when Nodes::FilterNode
        n = e.as(Nodes::FilterNode)
        expr_references?(n.target, name) || n.args.any? { |a| expr_references?(a, name) } ||
          n.kwargs.any? { |_, v| expr_references?(v, name) }
      when Nodes::TestNode
        n = e.as(Nodes::TestNode)
        expr_references?(n.target, name) || n.args.any? { |a| expr_references?(a, name) }
      when Nodes::CallExprNode
        n = e.as(Nodes::CallExprNode)
        expr_references?(n.func, name) || n.args.any? { |a| expr_references?(a, name) }
      when Nodes::GetattrNode
        expr_references?(e.as(Nodes::GetattrNode).obj, name)
      when Nodes::GetitemNode
        n = e.as(Nodes::GetitemNode)
        expr_references?(n.obj, name) || (n.key.try { |k| expr_references?(k, name) } || false)
      when Nodes::SliceNode
        n = e.as(Nodes::SliceNode)
        expr_references?(n.obj, name)
      when Nodes::TupleExprNode
        e.as(Nodes::TupleExprNode).items.any? { |i| expr_references?(i, name) }
      when Nodes::ListExprNode
        e.as(Nodes::ListExprNode).items.any? { |i| expr_references?(i, name) }
      when Nodes::DictExprNode
        n = e.as(Nodes::DictExprNode)
        n.keys.any? { |k| expr_references?(k, name) } || n.values.any? { |v| expr_references?(v, name) }
      when Nodes::ConcatNode
        e.as(Nodes::ConcatNode).parts.any? { |p| expr_references?(p, name) }
      when Nodes::CompareNode
        n = e.as(Nodes::CompareNode)
        expr_references?(n.left, name) || n.comparators.any? { |cm| expr_references?(cm, name) }
      when Nodes::CondExprNode
        n = e.as(Nodes::CondExprNode)
        expr_references?(n.truthy, name) || (n.falsy.try { |f| expr_references?(f, name) } || false) ||
          expr_references?(n.test, name)
      else
        false
      end
    end

    def call(args : Array(AnyValue), kwargs : Hash(String, AnyValue), ctx : Context) : AnyValue
      work = @closure
      uses_kwargs = references_special?(@body, "kwargs")
      uses_varargs = references_special?(@body, "varargs")
      if args.size > @params.size && !uses_varargs
        raise TemplateError.new("macro #{@name} takes not more than #{@params.size} argument(s)", 0)
      end
      work.push_scope
      begin
        remaining_args = args.size > @params.size ? args[@params.size..] : [] of AnyValue
        work["varargs"] = AnyValue.new(remaining_args)
        remaining_kwargs = kwargs.dup
        @params.each { |(pname, _)| remaining_kwargs.delete(pname) }
        if !remaining_kwargs.empty? && !uses_kwargs
          raise TemplateError.new("macro #{@name} takes no keyword argument '#{remaining_kwargs.first_key}'", 0)
        end
        work["kwargs"] = AnyValue.new(remaining_kwargs)
        @params.each_with_index do |(pname, default), i|
          if i < args.size && kwargs.has_key?(pname)
            raise TemplateError.new("macro #{@name} takes no keyword argument '#{pname}'", 0)
          end
          value = if i < args.size
                    args[i]
                  elsif kwargs.has_key?(pname)
                    kwargs[pname]
                  elsif default
                    Evaluator.new(@closure).eval(default.not_nil!)
                  else
                    AnyValue.new(nil)
                  end
          work[pname] = value
        end
        if (caller_val = ctx["__caller__"]?) && !work.has_key?("caller")
          work["caller"] = caller_val
        end
        rendered = Evaluator.new(work).render_nodes_to_string(@body)
        work.autoescape ? AnyValue.new(Markup.new(rendered)) : AnyValue.new(rendered)
      ensure
        work.pop_scope
      end
    end
  end

  # Caller body passed to macros via {% call %}.
  class CallerCallable < Callable
    def initialize(@body : Array(Nodes::Node), @ctx : Context, @params : Array(String) = [] of String)
    end

    def call(args : Array(AnyValue), _kwargs : Hash(String, AnyValue), ctx : Context) : AnyValue
      if args.size != @params.size
        raise TemplateError.new("macro takes not more than #{@params.size} argument(s)", 0)
      end
      ctx.push_scope
      begin
        ctx["caller"] = AnyValue.new(self)
        @params.each_with_index do |pname, i|
          ctx[pname] = args[i]? || AnyValue.new(nil)
        end
        r = Evaluator.new(ctx).render_nodes_to_string(@body)
        ctx.autoescape ? AnyValue.new(Markup.new(r)) : AnyValue.new(r)
      ensure
        ctx.pop_scope
      end
    end
  end

  def self.assign_targets(ctx : Context, targets : Array(TargetSpec), value : AnyValue)
    if targets.size == 1 && targets[0].children.nil?
      ctx[targets[0].name] = value
    else
      assign_one(ctx, targets.size == 1 ? targets[0] : TargetSpec.new("", targets), value)
    end
  end

  def self.assign_one(ctx : Context, target : TargetSpec, value : AnyValue)
    if target.children.nil?
      ctx[target.name] = value
      return
    end
    unpacked : Array(AnyValue) = case raw = value.raw
                                 when Array then raw
                                 when TupleValue then raw.items
                                 when String then raw.chars.map { |c| AnyValue.new(c.to_s) }
                                 else raise TemplateError.new("cannot unpack #{raw.class}", 0)
                                 end
    kids = target.children.not_nil!
    raise TemplateError.new("too many values to unpack", 0) if unpacked.size != kids.size
    kids.each_with_index { |t, i| assign_one(ctx, t, unpacked[i]) }
  end

  class Engine
    getter loader : Loader?
    getter globals : Hash(String, AnyValue)
    getter options : LexerOptions
    getter autoescape : Bool
    getter undefined : Undefined
    property host_context : HostContext?
    getter filters : Hash(String, FilterFn)
    getter tests : Hash(String, TestFn)

    def initialize(@loader : Loader? = nil, user_globals : Hash(String, AnyV) = {} of String => AnyV,
                   @options : LexerOptions = LexerOptions.new, @autoescape : Bool = false,
                   @undefined : Undefined = Undefined.new, @host_context = nil.as(HostContext?))
      globals = KrikriJinja.default_globals
      user_globals.each { |k, v| globals[k] = KrikriJinja.wrap_value(v) }
      @globals = globals
      @filters = BUILTIN_FILTERS.dup
      @tests = BUILTIN_TESTS.dup
    end

    def with_undefined(undefined : Undefined) : Engine
      copy = Engine.new(@loader, {} of String => AnyV, @options, @autoescape, undefined, @host_context)
      @globals.each { |key, value| copy.globals[key] = value }
      @filters.each { |key, value| copy.filters[key] = value }
      @tests.each { |key, value| copy.tests[key] = value }
      copy
    end

    # Derives an engine that hands `context` to every registered filter,
    # test, and function invoked while rendering or evaluating.
    def with_host_context(context : HostContext) : Engine
      copy = with_undefined(@undefined)
      copy.host_context = context
      copy
    end

    def register_filter(name : String, &block : FilterFn) : self
      @filters[name.downcase] = block
      self
    end

    def register_test(name : String, &block : TestFn) : self
      @tests[name.downcase] = block
      self
    end

    def register_global(name : String, value) : self
      @globals[name] = KrikriJinja.wrap_value(value)
      self
    end

    def register_function(name : String, &block : FunctionFn) : self
      register_global(name, AnyValue.new(SimpleCallable.new(name, &block)))
    end

    def register_json_filter(name : String, &block : JsonFilterFn) : self
      register_filter(name) do |value, args, kwargs, _ctx|
        result = block.call(
          KrikriJinja.to_json_any(value),
          args.map { |arg| KrikriJinja.to_json_any(arg) },
          kwargs.transform_values { |arg| KrikriJinja.to_json_any(arg) }
        )
        KrikriJinja.from_json_any(result)
      end
    end

    def register_json_test(name : String, &block : JsonTestFn) : self
      register_test(name) do |value, args, kwargs, _ctx|
        block.call(
          KrikriJinja.to_json_any(value),
          args.map { |arg| KrikriJinja.to_json_any(arg) },
          kwargs.transform_values { |arg| KrikriJinja.to_json_any(arg) }
        )
      end
    end

    def register_json_function(name : String, &block : JsonFunctionFn) : self
      register_function(name) do |args, kwargs, _ctx|
        result = block.call(
          args.map { |arg| KrikriJinja.to_json_any(arg) },
          kwargs.transform_values { |arg| KrikriJinja.to_json_any(arg) }
        )
        KrikriJinja.from_json_any(result)
      end
    end

    def register_loader_function(name : String, template_name : String) : self
      register_function(name) do |args, kwargs, _ctx|
        variables = {} of String => AnyValue
        kwargs.each { |key, value| variables[key] = value }
        args.each_with_index { |value, index| variables[index.to_s] = value }
        AnyValue.new(render_string(load_source(template_name), variables))
      end
    end

    def known_filter?(name : String) : Bool
      @filters.has_key?(name.downcase)
    end

    def known_test?(name : String) : Bool
      @tests.has_key?(name.downcase)
    end

    def evaluate_expression(source : String, variables : Hash(String, AnyV) = {} of String => AnyV) : AnyValue
      evaluate_expression_value(source, variables)
    end

    def evaluate_expression(source : String, variables : Hash(String, AnyValue)) : AnyValue
      evaluate_expression_value(source, variables)
    end

    def evaluate_json(source : String, variables : Hash(String, JSON::Any) = {} of String => JSON::Any) : JSON::Any?
      value = evaluate_expression_value(source, variables.transform_values { |item| KrikriJinja.from_json_any(item) })
      return nil if value.raw.is_a?(Undefined) && !@undefined.strict?
      KrikriJinja.to_json_any(value)
    end

    private def evaluate_expression_value(source : String, variables) : AnyValue
      ctx = Context.new(@globals.dup, @loader, @autoescape, @undefined, @filters, @tests)
      ctx.host_context = @host_context
      variables.each { |key, value| ctx[key] = KrikriJinja.wrap_value(value) }
      expression = Parser.parse_expression(source, @options)
      Evaluator.new(ctx, self).eval(expression)
    rescue error : TemplateError
      raise error
    rescue error
      raise TemplateError.new(error.message || "expression evaluation failed", 0, kind: ErrorKind::Runtime, operation: "evaluate")
    end

    def render_string(source : String, variables : Hash(String, AnyV) = {} of String => AnyV) : String
      render_variables(source, variables)
    end

    # Evaluates an already-parsed expression. `resolver` supplies any
    # variable that `variables` does not define, on first use. `undefined`
    # and `host_context` override the engine's own for this call only, so
    # one engine (and its registered features) serves every caller.
    def evaluate_parsed(expression : Nodes::ExprNode, variables : Hash(String, AnyValue) = {} of String => AnyValue,
                        resolver : VariableResolver? = nil,
                        undefined : Undefined = @undefined, host_context : HostContext? = @host_context) : AnyValue
      ctx = Context.new(@globals.dup, @loader, @autoescape, undefined, @filters, @tests)
      ctx.host_context = host_context
      ctx.resolver = resolver
      variables.each { |key, value| ctx[key] = value }
      Evaluator.new(ctx, self).eval(expression)
    rescue error : TemplateError
      raise error
    rescue error
      raise TemplateError.new(error.message || "expression evaluation failed", 0, kind: ErrorKind::Runtime, operation: "evaluate")
    end

    # Renders an already-parsed template. `resolver` supplies any variable
    # that `variables` does not define, on first use.
    def render_parsed(node : Nodes::TemplateNode, variables : Hash(String, AnyValue) = {} of String => AnyValue,
                      resolver : VariableResolver? = nil,
                      undefined : Undefined = @undefined, host_context : HostContext? = @host_context) : String
      ctx = Context.new(@globals.dup, @loader, @autoescape, undefined, @filters, @tests)
      ctx.host_context = host_context
      ctx.resolver = resolver
      variables.each { |key, value| ctx[key] = value }
      Evaluator.new(ctx, self).render_template(node)
    end

    def render_string(source : String, variables : Hash(String, AnyValue)) : String
      render_variables(source, variables)
    end

    # Loads a template by name from the loader and renders it.
    def render(name : String, variables : Hash(String, AnyV) = {} of String => AnyV) : String
      render_string(load_source(name), variables)
    end

    def load_source(name : String) : String
      source = @loader.try(&.get_source(name))
      raise TemplateError.new("template #{name.inspect} not found", 0, kind: ErrorKind::Loader, template_name: name) unless source
      source
    end

    private def render_variables(source : String, variables)
      ctx = Context.new(@globals.dup, @loader, @autoescape, @undefined, @filters, @tests)
      ctx.host_context = @host_context
      ctx.autoescape = @autoescape
      variables.each { |k, v| ctx[k] = KrikriJinja.wrap_value(v) }
      node = Parser.parse(source, @options)
      Evaluator.new(ctx, self).render_template(node)
    end

    def load(name : String) : Nodes::TemplateNode
      Parser.parse(load_source(name), @options)
    end
  end

  @[Link("m")]
  lib PyLibM
    fun fmod(x : Float64, y : Float64) : Float64
  end

  class Evaluator
    @ctx : Context
    @engine : Engine
    @out : ::IO
    @macro_frames : Array(Hash(String, AnyValue)) = [] of Hash(String, AnyValue)

    def initialize(@ctx, engine : Engine? = nil, buf : ::IO? = nil)
      @engine = engine || Engine.new
      @out = buf.is_a?(::IO) ? buf : IO::Memory.new
    end

    def output : ::IO
      @out
    end

    private def stringify(v : AnyValue, escape : Bool = false) : String
      KrikriJinja.stringify(v, escape)
    end

    private def truthy?(v : AnyValue) : Bool
      KrikriJinja.truthy?(v)
    end

    private def values_equal(a : AnyValue, b : AnyValue) : Bool
      KrikriJinja.values_equal(a, b)
    end

    private def compare_values(a : AnyValue, b : AnyValue) : Int32
      KrikriJinja.compare_values(a, b)
    end

    private def contains?(a : AnyValue, b : AnyValue) : Bool
      KrikriJinja.contains?(a, b)
    end

    private def get_attr(obj : AnyValue, name : String?) : AnyValue?
      KrikriJinja.get_attr(obj, name)
    end

    # --- template-level rendering -----------------------------------------------

    def render_template(node : Nodes::TemplateNode) : String
      collect_blocks(node.body)
      has_extends = node.body.any? { |n| n.is_a?(Nodes::ExtendsNode) }
      if has_extends
        # follow the inheritance chain to the root parent
        chain_bodies = [node.body]
        current_body = node.body
        while true
          parent_idx = current_body.index { |n| n.is_a?(Nodes::ExtendsNode) }.not_nil!
          extends_node = current_body[parent_idx].as(Nodes::ExtendsNode)
          parent_name = eval(extends_node.template).raw.as?(String) ||
                        raise TemplateError.new("extends expects a template name", extends_node.line)
          parent = @engine.load(parent_name)
          collect_blocks(parent.body)
          break unless parent.body.any? { |n| n.is_a?(Nodes::ExtendsNode) }
          current_body = parent.body
          chain_bodies << current_body
        end
        # Child/ancestor module-level statements (sets, macros, imports) run
        # even though only the root parent's markup renders.
        chain_bodies.each do |b|
          # top-level statements execute anywhere, but visible content only
          # before the extends tag renders (jinja drops the rest)
          limit = b.index { |n| n.is_a?(Nodes::ExtendsNode) } || b.size
          b.each_with_index do |n, i|
            case n
            when Nodes::SetNode, Nodes::MacroNode, Nodes::ImportNode, Nodes::DoNode
              render_node(n)
            when Nodes::TextNode, Nodes::OutputNode
              render_node(n) if i < limit
            end
          end
        end
        render_nodes(parent.body)
      else
        render_nodes(node.body)
      end
      @out.to_s
    end

    private def collect_blocks(body : Array(Nodes::Node), seen : Set(String)? = nil)
      names = seen || Set(String).new
      body.each do |n|
        case n
        when Nodes::BlockNode
          raise TemplateError.new("block '#{n.name}' defined twice", n.line) unless names.add?(n.name)
          @ctx.register_block(n.name, n)
          collect_blocks(n.body, names)
        when Nodes::IfNode
          n.branches.each { |_, b| collect_blocks(b) }
          collect_blocks(n.orelse || [] of Nodes::Node)
        when Nodes::ForNode
          collect_blocks(n.body)
          collect_blocks(n.orelse || [] of Nodes::Node)
        end
      end
    end

    def render_nodes_to_string(body : Array(Nodes::Node)) : String
      buf = IO::Memory.new
      old = @out
      @out = buf
      begin
        render_nodes(body)
      ensure
        @out = old
      end
      buf.to_s
    end

    def render_nodes(body : Array(Nodes::Node))
      body.each { |n| render_node(n) }
    end

    def render_node(node : Nodes::Node)
      case node
      when Nodes::TextNode
        @out << node.text
      when Nodes::OutputNode
        render_output(node)
      when Nodes::IfNode
        node.branches.each do |(cond, body)|
          if truthy?(eval(cond))
            @macro_frames.push({} of String => AnyValue)
            begin
              render_nodes(body)
            ensure
              @macro_frames.pop
            end
            return
          end
        end
        @macro_frames.push({} of String => AnyValue)
        begin
          render_nodes(node.orelse || [] of Nodes::Node)
        ensure
          @macro_frames.pop
        end
      when Nodes::ForNode
        render_for(node)
      when Nodes::SetNode
        render_set(node)
      when Nodes::BlockNode
        blocks = @ctx.blocks[node.name]?
        chain = blocks && !blocks.empty? ? blocks : [node]
        render_block_chain(chain, 0)
      when Nodes::MacroNode
        if @macro_frames.empty?
          @ctx[node.name] = AnyValue.new(MacroCallable.new(node.name, node.params, node.body, @ctx))
        else
          @macro_frames.last[node.name] = AnyValue.new(MacroCallable.new(node.name, node.params, node.body, @ctx))
        end
      when Nodes::CallNode
        render_call(node)
      when Nodes::FilterBlockNode
        render_filter_block(node)
      when Nodes::WithNode
        @ctx.push_scope
        node.bindings.each { |name, expr| @ctx[name] = eval(expr) }
        begin
          render_nodes(node.body)
        ensure
          @ctx.pop_scope
        end
      when Nodes::IncludeNode
        render_include(node)
      when Nodes::ExtendsNode
        # handled by render_template
      when Nodes::ImportNode
        render_import(node)
      when Nodes::DoNode
        eval(node.expr)
      when Nodes::AutoescapeNode
        old = @ctx.autoescape
        @ctx.autoescape = node.enabled
        begin
          render_nodes(node.body)
        ensure
          @ctx.autoescape = old
        end
      else
        raise TemplateError.new("cannot render #{node.class}", node.line)
      end
    end

    private def render_block_chain(chain : Array(Nodes::BlockNode), i : Int32)
      @ctx.push_scope
      old_hide = @ctx.hide_locals
      old_from = @ctx.hide_from
      @ctx.hide_locals = true
      @ctx.hide_from = old_hide ? old_from : @ctx.scopes.size - 1
      if i + 1 < chain.size
        @ctx["super"] = AnyValue.new(KrikriJinja::SimpleCallable.new("super") do |args, _k, _c|
          raise TemplateError.new("super() takes no arguments", 0) unless args.empty?
          render_block_chain(chain, i + 1)
          AnyValue.new(Markup.new(""))
        end)
      end
      begin
        render_nodes(chain[i].body)
      ensure
        @ctx.hide_locals = old_hide
        @ctx.hide_from = old_from
        @ctx.pop_scope
      end
    end

    private def render_output(node : Nodes::OutputNode)
      value = eval(node.expr)
      s = if value.raw.is_a?(Markup)
            value.raw.as(Markup).value
          else
            escape = @ctx.autoescape && !node.expr.is_a?(Nodes::ConstNode)
            stringify(value, escape)
          end
      @out << s
    end

    private def render_for(node : Nodes::ForNode)
      iterable = eval(node.iter)
      items : Array(AnyValue) = case raw = iterable.raw
                                when Array  then raw.dup
                                when String then raw.chars.map { |c| AnyValue.new(c.to_s) }
                                when Hash   then raw.keys.map { |k| AnyValue.new(k) }
                                when TupleValue then raw.items
                                when Undefined
                                  raise TemplateError.new(KrikriJinja.undefined_message(raw.as(Undefined)), node.line, kind: ErrorKind::Undefined) if raw.is_a?(Undefined) && raw.as(Undefined).strict?
                                  [] of AnyValue
                                when GeneratorValue then raw.materialize
                                else raise TemplateError.new("#{raw.class} is not iterable", node.line)
                                end

      if node.test
        items = items.select do |item|
          @ctx.push_scope
          begin
            assign_targets(node.targets, item)
            truthy?(eval(node.test.not_nil!))
          ensure
            @ctx.pop_scope
          end
        end
      end

      if items.empty?
        render_nodes(node.orelse || [] of Nodes::Node)
        return
      end

      if node.recursive
        parent_loop = @ctx["loop"]?.try(&.raw.as?(LoopCallable))
        loop_obj = LoopCallable.new(items, node.body, @ctx, @engine, node.targets, parent_loop, (parent_loop.try(&.depth) || 0) + 1, @out, @ctx.undefined)
        loop_value = AnyValue.new(loop_obj)
        old_lil = @ctx.loop_is_local
        @ctx.loop_is_local = false
        @ctx.push_scope(false)
        begin
          items.each_with_index do |item, i|
            loop_obj.index = i
            assign_targets(node.targets, item)
            @ctx["loop"] = loop_value
            render_nodes(node.body)
          end
        ensure
          @ctx.pop_scope
          @ctx.loop_is_local = old_lil
          if parent_loop.nil?
            @ctx.delete("loop")
          else
            @ctx.scopes[0]["loop"] = AnyValue.new(parent_loop.not_nil!)
          end
        end
        return
      end

      parent_loop = @ctx["loop"]?.try(&.raw.as?(LoopObject))
      loop_obj = LoopObject.new(items, 0, parent: nil, depth: 1, undefined: @ctx.undefined)
      loop_value = AnyValue.new(loop_obj)
      old_lil = @ctx.loop_is_local
      @ctx.loop_is_local = true
      @ctx.push_scope(true)
      begin
        items.each_with_index do |item, i|
          assign_targets(node.targets, item)
          @ctx["loop"] = loop_value
          @macro_frames.push({} of String => AnyValue)
          begin
            render_nodes(node.body)
          ensure
            @macro_frames.pop
          end
          loop_obj.index = i + 1
        end
      ensure
        @ctx.pop_scope
        @ctx.loop_is_local = old_lil
        if parent_loop.nil?
          @ctx.delete("loop")
        else
          @ctx.scopes[0]["loop"] = AnyValue.new(parent_loop.not_nil!)
        end
      end
    end

    private def assign_targets(targets : Array(TargetSpec), value : AnyValue)
      KrikriJinja.assign_targets(@ctx, targets, value)
    end

    private def render_set(node : Nodes::SetNode)
      if body = node.body
        rendered = render_nodes_to_string(body)
        if fname = node.filter_name
          f = @ctx.filter(fname) ||
              raise TemplateError.new("unknown filter #{fname.inspect}", node.line)
          args = node.filter_args.map { |a| eval(a) }
          kwargs = {} of String => AnyValue
          node.filter_kwargs.each { |k, e| kwargs[k] = eval(e) }
          rendered = stringify(f.call(AnyValue.new(Markup.new(rendered)), args, kwargs, @ctx))
        end
        @ctx[node.targets.first] = @ctx.autoescape ? AnyValue.new(Markup.new(rendered)) : AnyValue.new(rendered)
        return
      end
      value = eval(node.expr)
      if target = node.attr_target
        case target
        when Nodes::GetattrNode
          obj = eval(target.obj)
          if obj.raw.is_a?(Namespace)
            obj.raw.as(Namespace).data[target.attr] = value
          else
            raise TemplateError.new("cannot assign attribute on non-namespace object", node.line)
          end
        when Nodes::GetitemNode
          obj = eval(target.obj)
          key = eval(target.key)
          if obj.raw.is_a?(Hash)
            obj.raw.as(Hash)[stringify(key)] = value
          elsif obj.raw.is_a?(Array) && key.raw.is_a?(Int64)
            obj.raw.as(Array)[key.raw.as(Int64)] = value
          else
            raise TemplateError.new("cannot set item on #{obj.raw.class}", node.line)
          end
        else
          raise TemplateError.new("invalid set target", node.line)
        end
      else
        if node.targets.size == 1
          @ctx[node.targets[0]] = value
        else
          items = value.raw.as?(Array) || (value.raw.as?(TupleValue).try(&.items)) ||
                  raise TemplateError.new("cannot unpack set target", node.line)
          node.targets.each_with_index { |t, i| @ctx[t] = items[i]? || AnyValue.new(nil) }
        end
      end
    end

    private def render_call(node : Nodes::CallNode)
      if body = node.body
        @ctx.push_scope
        @ctx["__caller__"] = AnyValue.new(CallerCallable.new(body, @ctx, node.call_params))
        begin
          result = eval(Nodes::CallExprNode.new(node.macro_expr, node.args, node.kwargs, node.line))
          @out << stringify(result)
        ensure
          @ctx.pop_scope
        end
      else
        result = eval(Nodes::CallExprNode.new(node.macro_expr, node.args, node.kwargs, node.line))
        @out << stringify(result)
      end
    end

    private def render_filter_block(node : Nodes::FilterBlockNode)
      rendered = render_nodes_to_string(node.body)
      @ctx.push_scope
      @ctx["__filter_block__"] = AnyValue.new(Markup.new(rendered))
      begin
        @out << stringify(eval(node.filter))
      ensure
        @ctx.pop_scope
      end
    end

    private def render_include(node : Nodes::IncludeNode)
      chosen = eval(node.template)
      names : Array(String) = case raw = chosen.raw
                              when String then [raw]
                              when Array  then raw.compact_map { |n| n.raw.as?(String) }
                              else raise TemplateError.new("include expects a template name", node.line)
                              end
      source : String? = nil
      name = ""
      names.each do |candidate|
        name = candidate
        source = @ctx.loader.try(&.get_source(candidate))
        break if source || names.size == 1
      end
      if source.nil?
        return if node.ignore_missing
        raise TemplateError.new("template #{name.inspect} not found", node.line, kind: ErrorKind::Loader, template_name: name)
      end
      sub_node = Parser.parse(source, @engine.options)
      if node.with_context
        # Rendered with the surrounding context minus loop locals; sets and
        # macro definitions stay private to the included template.
        @ctx.push_scope
        old_noloop = @ctx.hide_loop_var
        old_nosuper = @ctx.hide_super
        old_blocks = @ctx.blocks
        @ctx.hide_loop_var = @ctx.loop_is_local
        @ctx.hide_super = true
        @ctx.blocks = {} of String => Array(Nodes::BlockNode)
        begin
          sub_eval = Evaluator.new(@ctx, @engine)
          sub_eval.render_template(sub_node)
          @out << sub_eval.output.to_s
        ensure
          @ctx.hide_loop_var = old_noloop
          @ctx.hide_super = old_nosuper
          @ctx.blocks = old_blocks
          @ctx.pop_scope
        end
      else
        sub_ctx = Context.new(@ctx.globals, @ctx.loader, @ctx.autoescape, @ctx.undefined, @ctx.filters, @ctx.tests)
        sub_ctx.host_context = @ctx.host_context
        sub_eval = Evaluator.new(sub_ctx, @engine)
        sub_eval.render_template(sub_node)
        @out << sub_eval.output.to_s
      end
    end

    private def render_import(node : Nodes::ImportNode)
      name = eval(node.template).raw.as?(String) ||
             raise TemplateError.new("import expects a template name", node.line)
      source = @ctx.loader.try(&.get_source(name))
      raise TemplateError.new("template #{name.inspect} not found", node.line, kind: ErrorKind::Loader, template_name: name) unless source
      sub_ctx = Context.new(@ctx.globals, @ctx.loader, @ctx.autoescape, @ctx.undefined, @ctx.filters, @ctx.tests)
      sub_ctx.host_context = @ctx.host_context
      if node.context
        sub_ctx.resolver = @ctx.resolver
        # {% import ... with context %}: the imported module resolves names
        # against the importing template's visible (non-loop) variables.
        @ctx.scopes.reverse_each do |scope|
          scope.each { |k, v| sub_ctx.scopes[0][k] = v unless sub_ctx.scopes[0].has_key?(k) }
        end
      end
      sub_node = Parser.parse(source, @engine.options)
      collect_module_exports(sub_node.body, sub_ctx)
      mod = sub_ctx.scopes[0].dup
      if node.from_import
        node.names.each { |(src, alias_name)| @ctx[alias_name] = mod[src]? || AnyValue.new(nil) }
      else
        node.names.each { |(_src, alias_name)| @ctx[alias_name] = AnyValue.new(mod) }
      end
    end

    private def collect_module_exports(body : Array(Nodes::Node), ctx : Context)
      body.each do |n|
        case n
        when Nodes::MacroNode
          ctx[n.name] = AnyValue.new(MacroCallable.new(n.name, n.params, n.body, ctx))
        when Nodes::SetNode
          if n.targets.size == 1
            ctx[n.targets.first] = Evaluator.new(ctx, @engine).eval(n.expr)
          end
        end
      end
    end

    # --- expression evaluation ----------------------------------------------------

    def eval(expr : Nodes::ExprNode) : AnyValue
      case expr
      when Nodes::ConstNode
        AnyValue.new(expr.value)
      when Nodes::NameNode
        @macro_frames.reverse_each do |frame|
          if frame.has_key?(expr.name)
            return frame[expr.name]
          end
        end
        @ctx[expr.name]
      when Nodes::ListExprNode
        AnyValue.new(expr.items.map { |i| eval(i) })
      when Nodes::TupleExprNode
        AnyValue.new(TupleValue.new(expr.items.map { |i| eval(i) }))
      when Nodes::DictExprNode
        h = {} of String => AnyValue
        expr.keys.each_with_index do |k, i|
          key_v = eval(k)
          enc = KrikriJinja.dict_key(key_v)
          alt = KrikriJinja.dict_key_alt(key_v)
          # python: 1 and True are the same dict key; first key form wins
          if alt && h.has_key?(alt)
            h[alt] = eval(expr.values[i])
          else
            h[enc] = eval(expr.values[i])
          end
        end
        AnyValue.new(h)
      when Nodes::BinOpNode
        eval_binop(expr)
      when Nodes::UnaryOpNode
        case expr.op
        when "not" then AnyValue.new(!truthy?(eval(expr.operand)))
        when "-" then AnyValue.new(negate(eval(expr.operand).raw))
        when "+"
          raw = eval(expr.operand).raw
          case raw
          when Int64, Float64, Bool then AnyValue.new(raw)
          else raise TemplateError.new("bad operand type for unary +: #{raw.class}", expr.line)
          end
        else eval(expr.operand)
        end
      when Nodes::CompareNode
        AnyValue.new(eval_compare(expr))
      when Nodes::ConcatNode
        AnyValue.new(expr.parts.map { |p| stringify(eval(p)) }.join)
      when Nodes::CondExprNode
        if truthy?(eval(expr.test))
          eval(expr.truthy)
        else
          expr.falsy ? eval(expr.falsy.not_nil!) : AnyValue.new(@ctx.undefined)
        end
      when Nodes::FilterNode
        eval_filter(expr)
      when Nodes::TestNode
        AnyValue.new(eval_test(expr))
      when Nodes::GetattrNode
        eval_getattr(expr)
      when Nodes::GetitemNode
        eval_getitem(expr)
      when Nodes::SliceNode
        eval_slice(expr)
      when Nodes::CallExprNode
        eval_call(expr)
      else
        raise TemplateError.new("cannot evaluate #{expr.class}", expr.line)
      end
    end

    private def eval_binop(expr : Nodes::BinOpNode) : AnyValue
      case expr.op
      when "and"
        left = eval(expr.left)
        return left unless truthy?(left)
        eval(expr.right)
      when "or"
        left = eval(expr.left)
        return left if truthy?(left)
        eval(expr.right)
      else
        left = eval(expr.left).raw
        right = eval(expr.right).raw
        # python bools are ints in arithmetic
        left = as_int(left) if left.is_a?(Bool)
        right = as_int(right) if right.is_a?(Bool)
        # String % value is %-formatting in python; big-int decimal strings
        # are numeric and use numeric modulo instead; Markup formats too
        fmt_left : String? = case left
                            when Markup then left.as(Markup).value
                            when String then left.as(String)
                            else nil
                            end
        if expr.op == "%" && (f = fmt_left)
          tuple_arg = right.is_a?(TupleValue)
          fmt_args = tuple_arg ? right.as(TupleValue).items : [AnyValue.new(right)]
          formatted = KrikriJinja.py_format(f, fmt_args, tuple_arg)
          return AnyValue.new(left.is_a?(Markup) ? Markup.new(formatted) : formatted)
        end
        result = case expr.op
                 when "+" then add(left, right)
                 when "-" then subtract(left, right)
                 when "*" then multiply(left, right)
                 when "/" then divide(left, right)
                 when "//" then floor_divide(left, right)
                 when "%" then modulo(left, right)
                 when "**" then power(left, right)
                 else raise TemplateError.new("unknown operator #{expr.op}", expr.line)
                 end
        AnyValue.wrap(result)
      end
    end

    private def as_int(v : AnyV) : Int64?
      case v
      when Int64 then v
      when Bool then v ? 1i64 : 0i64
      else nil
      end
    end

    # Decimal string for int-valued operands: Int64s and BigIntValues.
    private def big_dec_str(v : AnyV) : String?
      v.as?(Int64).try(&.to_s) || v.as?(BigIntValue).try(&.value)
    end

    private def add(a : AnyV, b : AnyV) : AnyV
      case {a, b}
      when {Float64, Float64} then a + b
      when {Int64, Float64} then a.to_f64 + b
      when {Float64, Int64} then a + b.to_f64
      when {Markup, String} then a.value + b
      when {String, Markup} then a + b.value
      when {Markup, Markup} then a.value + b.value
      when {String, String} then a + b
      when {BigIntValue, Int64} then KrikriJinja.norm_decimal(KrikriJinja.big_add(a.value, b.to_s))
      when {Int64, BigIntValue} then KrikriJinja.norm_decimal(KrikriJinja.big_add(a.to_s, b.value))
      when {BigIntValue, BigIntValue} then KrikriJinja.norm_decimal(KrikriJinja.big_add(a.value, b.value))
      when {BigIntValue, Float64} then a.to_f64 + b
      when {Float64, BigIntValue} then a + b.to_f64
      when {Array, Array} then a + b
      else
        x = as_int(a)
        y = as_int(b)
        if x && y
          if (x > 0 && y > 0 && x > Int64::MAX - y) || (x < 0 && y < 0 && x < Int64::MIN - y)
            KrikriJinja.norm_decimal(KrikriJinja.big_add(x.to_s, y.to_s))
          else
            x + y
          end
        elsif (x || a.is_a?(Float64)) && (y || b.is_a?(Float64))
          (x ? x.to_f64 : a.as(Float64)) + (y ? y.to_f64 : b.as(Float64))
        elsif (s1 = big_dec_str(a)) && (s2 = big_dec_str(b))
          KrikriJinja.norm_decimal(KrikriJinja.big_add(s1, s2))
        elsif (s1 = big_dec_str(a)) && (b.is_a?(Float64) || y)
          s1.to_f64 + (b.as?(Float64) || y.not_nil!.to_f64)
        elsif (s2 = big_dec_str(b)) && (a.is_a?(Float64) || x)
          s2.to_f64 + (a.as?(Float64) || x.not_nil!.to_f64)
        else
          raise TemplateError.new("unsupported operands for +: #{a.class} and #{b.class}", 0)
        end
      end
    end

    private def subtract(a : AnyV, b : AnyV) : AnyV
      x = as_int(a)
      y = as_int(b)
      if x && y
        begin
          x - y
        rescue OverflowError
          ny = y >= 0 ? -y : (y == Int64::MIN ? 9223372036854775808i128 : -y)
          KrikriJinja.norm_decimal(KrikriJinja.big_add(x.to_s, ny.to_s))
        end
      elsif (x || a.is_a?(Float64)) && (y || b.is_a?(Float64))
        (x ? x.to_f64 : a.as(Float64)) - (y ? y.to_f64 : b.as(Float64))
      elsif (s1 = big_dec_str(a)) && (s2 = big_dec_str(b))
        neg_s = s2.starts_with?('-') ? s2[1..] : "-#{s2}"
        KrikriJinja.norm_decimal(KrikriJinja.big_add(s1, neg_s))
      elsif (s1 = big_dec_str(a)) && (b.is_a?(Float64) || y)
        s1.to_f64 - (b.as?(Float64) || y.not_nil!.to_f64)
      elsif (s2 = big_dec_str(b)) && (a.is_a?(Float64) || x)
        (a.as?(Float64) || x.not_nil!.to_f64) - s2.to_f64
      else
        raise TemplateError.new("unsupported operands for -: #{a.class} and #{b.class}", 0)
      end
    end

    private def multiply(a : AnyV, b : AnyV) : AnyV
      # big-int decimal strings are numbers, not strings: check before the
      # sequence-repeat cases so 9223372036854775808 * 2 multiplies
      if (sa = a.as?(BigIntValue))
        if (yb = as_int(b))
          return KrikriJinja.norm_decimal(KrikriJinja.big_mul(sa.value, yb.to_s))
        end
        if (sb = b.as?(BigIntValue))
          return KrikriJinja.norm_decimal(KrikriJinja.big_mul(sa.value, sb.value))
        end
        if (fb = b.as?(Float64))
          return sa.to_f64 * fb
        end
      end
      if (sb = b.as?(BigIntValue))
        if (xa = as_int(a))
          return KrikriJinja.norm_decimal(KrikriJinja.big_mul(xa.to_s, sb.value))
        end
        if (fa = a.as?(Float64))
          return fa * sb.to_f64
        end
      end
      case {a, b}
      when {String, Int64}
        raise TemplateError.new("memory error", 0) if b > 0 && a.bytesize > 0 && b > (2_000_000_000 // a.bytesize)
        b <= 0 ? "" : a * b
      when {Int64, String}
        raise TemplateError.new("memory error", 0) if a > 0 && b.bytesize > 0 && a > (2_000_000_000 // b.bytesize)
        a <= 0 ? "" : b * a
      when {Markup, Int64} then b <= 0 ? "" : a.value * b
      when {Int64, Markup} then a <= 0 ? "" : b.value * a
      when {Array, Int64}
        return [] of AnyValue if a.empty?
        raise TemplateError.new("memory error", 0) if b > 0 && b > (50_000_000 // Math.max(1, a.size))
        out_arr = [] of AnyValue
        (b > 0 ? b : 0).times { out_arr.concat(a) }
        out_arr
      when {Int64, Array}
        raise TemplateError.new("memory error", 0) if a > 0 && a > (50_000_000 // Math.max(1, b.size))
        out_arr = [] of AnyValue
        (a > 0 ? a : 0).times { out_arr.concat(b) }
        out_arr
      when {TupleValue, Int64}
        raise TemplateError.new("memory error", 0) if b > 0 && b > (50_000_000 // Math.max(1, a.items.size))
        out_items = [] of AnyValue
        (b > 0 ? b : 0).times { out_items.concat(a.items) }
        TupleValue.new(out_items)
      when {Int64, TupleValue}
        raise TemplateError.new("memory error", 0) if a > 0 && a > (50_000_000 // Math.max(1, b.items.size))
        out_items = [] of AnyValue
        (a > 0 ? a : 0).times { out_items.concat(b.items) }
        TupleValue.new(out_items)
      else
        x = as_int(a)
        y = as_int(b)
        if x && y
          begin
            x * y
          rescue OverflowError
            KrikriJinja.norm_decimal(KrikriJinja.big_mul(x.to_s, y.to_s))
          end
        elsif a.is_a?(BigIntValue) && (y || b.is_a?(BigIntValue))
          KrikriJinja.norm_decimal(KrikriJinja.big_mul(a.value, y ? y.to_s : b.as(BigIntValue).value))
        elsif b.is_a?(BigIntValue) && x
          KrikriJinja.norm_decimal(KrikriJinja.big_mul(x.to_s, b.value))
        elsif (x || a.is_a?(Float64) || a.is_a?(BigIntValue)) &&
              (y || b.is_a?(Float64) || b.is_a?(BigIntValue))
          (x || (a.is_a?(Float64) ? a.as(Float64) : a.as(BigIntValue).to_f64)) *
            (y || (b.is_a?(Float64) ? b.as(Float64) : b.as(BigIntValue).to_f64))
        else
          raise TemplateError.new("unsupported operands for *: #{a.class} and #{b.class}", 0)
        end
      end
    end

    private def numish(v : AnyV) : Float64?
      v.as?(Float64) || as_int(v).try(&.to_f64) || v.as?(BigIntValue).try(&.to_f64)
    end

    private def divide(a : AnyV, b : AnyV) : AnyV
      x = numish(a)
      y = numish(b)
      raise TemplateError.new("unsupported operand for /", 0) unless x && y
      raise TemplateError.new("division by zero", 0) if y == 0.0
      x / y
    end

    private def floor_divide(a : AnyV, b : AnyV) : AnyV
      if (x = as_int(a)) && (y = as_int(b))
        raise TemplateError.new("integer division or modulo by zero", 0) if y == 0
        x // y
      elsif (s1 = big_dec_str(a)) && (s2 = big_dec_str(b))
        raise TemplateError.new("integer division or modulo by zero", 0) if s2 == "0" || s2 == "-0"
        q, _ = KrikriJinja.big_divmod(s1, s2)
        KrikriJinja.norm_decimal(q)
      else
        x = numish(a) || raise TemplateError.new("unsupported operand", 0)
        y = numish(b) || raise TemplateError.new("unsupported operand", 0)
        raise TemplateError.new("division by zero", 0) if y == 0.0
        r = PyLibM.fmod(x, y)
        q = ((x - r) / y).floor
        q -= 1.0 if r != 0.0 && (r < 0.0) != (y < 0.0)
        q = -0.0 if q == 0.0 && (1.0 / (x / y)) < 0.0
        q
      end
    end

    private def modulo(a : AnyV, b : AnyV) : AnyV
      if (x = as_int(a)) && (y = as_int(b))
        raise TemplateError.new("integer division or modulo by zero", 0) if y == 0
        r = x % y
        r = r + y.abs if r != 0 && (r < 0) != (y < 0)
        r
      elsif (s1 = big_dec_str(a)) && (s2 = big_dec_str(b))
        raise TemplateError.new("integer division or modulo by zero", 0) if s2 == "0" || s2 == "-0"
        _, r = KrikriJinja.big_divmod(s1, s2)
        KrikriJinja.norm_decimal(r)
      else
        x = numish(a) || raise TemplateError.new("unsupported operand", 0)
        y = numish(b) || raise TemplateError.new("unsupported operand", 0)
        raise TemplateError.new("division by zero", 0) if y == 0.0
        r = PyLibM.fmod(x, y)
        r = r + y if r != 0 && (r < 0) != (y < 0)
        r = 0.0 if r == 0
        r
      end
    end

    private def power(a : AnyV, b : AnyV) : AnyV
      if (x = as_int(a)) && (y = as_int(b))
        if y >= 0
          raise TemplateError.new("integer power result too large", 0) if y > 1 && x.to_s.size * y > 40_000
          begin
            return x ** y
          rescue OverflowError
            return KrikriJinja.norm_decimal(KrikriJinja.big_pow(x, y))
          end
        else
          raise TemplateError.new("0.0 cannot be raised to a negative power", 0) if x == 0
          return x.to_f64 ** y
        end
      end
      if (s1 = big_dec_str(a)) && (yb = as_int(b)) && yb >= 0
        raise TemplateError.new("integer power result too large", 0) if yb > 1 && s1.lstrip('-').size * yb > 40_000
        return KrikriJinja.norm_decimal(KrikriJinja.big_pow_str(s1, yb))
      end
      if (x = as_int(a)) && (big_exp = b.as?(BigIntValue))
        raise TemplateError.new("0.0 cannot be raised to a negative power", 0) if x == 0 && big_exp.negative?
        return x if x == 0 || x == 1
        return (big_exp.digits[-1] - '0') % 2 == 0 ? 1i64 : -1i64 if x == -1
      end
      af = numish(a) || raise TemplateError.new("unsupported operand", 0)
      bf = numish(b) || raise TemplateError.new("unsupported operand", 0)
      raise TemplateError.new("0.0 cannot be raised to a negative power", 0) if af == 0.0 && bf < 0
      r = af ** bf
      raise TemplateError.new("numerical result out of range", 0) if r.infinite? && !af.infinite? && !bf.infinite?
      r
    end


    private def negate(v : AnyV) : AnyV
      case v
      when Int64 then -v
      when Float64 then -v
      when Bool then v ? -1i64 : 0i64
      when BigIntValue then v.negated
      else raise TemplateError.new("cannot negate #{v.class}", 0)
      end
    end

    private def eval_compare(expr : Nodes::CompareNode) : Bool
      left = eval(expr.left)
      expr.ops.each_with_index do |op, i|
        right = eval(expr.comparators[i])
        ok = case op
             when "==" then values_equal(left, right)
             when "!=" then !values_equal(left, right)
             when "<" then compare_values(left, right) < 0
             when ">" then compare_values(left, right) > 0
             when "<=" then compare_values(left, right) <= 0
             when ">=" then compare_values(left, right) >= 0
             # Python's `x in list` never raises for an undefined LEFT
             # operand: membership simply reports False, which is what real
             # Ansible's own `{{ undefined_var in some_list }}` does. A
             # STRING container is the exception - Python raises there.
             when "in"
               if left.raw.is_a?(Undefined)
                 if right.raw.is_a?(String)
                   raise TemplateError.new("'in <string>' requires string as left operand, not UndefinedMarker", expr.line)
                 end
                 false
               else
                 contains?(right, left)
               end
             when "not in"
               if left.raw.is_a?(Undefined)
                 if right.raw.is_a?(String)
                   raise TemplateError.new("'in <string>' requires string as left operand, not UndefinedMarker", expr.line)
                 end
                 true
               else
                 !contains?(right, left)
               end
             else raise TemplateError.new("unknown comparison #{op}", expr.line)
             end
        return false unless ok
        left = right
      end
      true
    end

    private def eval_filter(expr : Nodes::FilterNode) : AnyValue
      value = eval(expr.target)
      f = @ctx.filter(expr.name) ||
          raise TemplateError.new("unknown filter #{expr.name.inspect}", expr.line)
      args = expr.args.map { |a| eval(a) }
      kwargs = eval_kwargs(expr.kwargs)
      f.call(value, args, kwargs, @ctx)
    end

    private def eval_test(expr : Nodes::TestNode) : Bool
      value = eval(expr.target)
      t = @ctx.test(expr.name) ||
          raise TemplateError.new("unknown test #{expr.name.inspect}", expr.line)
      args = expr.args.flat_map do |a|
        v = eval(a)
        v.raw.is_a?(TupleValue) ? v.raw.as(TupleValue).items : [v]
      end
      kwargs = eval_kwargs(expr.kwargs)
      result = t.call(value, args, kwargs, @ctx)
      expr.negated ? !result : result
    end

    # Ansible's own Undefined is CHAINABLE: reaching an attribute of an
    # undefined value yields another undefined rather than raising on the
    # spot, so a fallback like `x | default(other.thing.y)` stays lazy when
    # `x` is defined. Using the chain (stringify/compare/iterate) is what
    # raises, naming the variable the chain started from.
    private def eval_getattr(expr : Nodes::GetattrNode) : AnyValue
      obj = eval(expr.obj)
      if obj.raw.is_a?(Undefined)
        undefined = obj.raw.as(Undefined)
        return @ctx.undefined_named(undefined.name || expr.attr || "value") if undefined.chainable
        raise TemplateError.new(KrikriJinja.undefined_message(undefined), expr.line, kind: ErrorKind::Undefined)
      end
      get_attr(obj, expr.attr) || AnyValue.new(@ctx.undefined)
    end

    private def eval_getitem(expr : Nodes::GetitemNode) : AnyValue
      obj = eval(expr.obj)
      if obj.raw.is_a?(Undefined)
        undefined = obj.raw.as(Undefined)
        return @ctx.undefined_named(undefined.name || "value") if undefined.chainable
        raise TemplateError.new(KrikriJinja.undefined_message(undefined), expr.line, kind: ErrorKind::Undefined)
      end
      key = eval(expr.key)
      result = case raw = obj.raw
               when Hash
                 encoded = KrikriJinja.dict_key(key)
                 found = raw[encoded]?
                 unless found
                   alternate = KrikriJinja.dict_key_alt(key)
                   found = raw[alternate]? if alternate
                 end
                 found
               when Array
                 k = key.raw.as?(Int64) || as_int(key.raw) || nil
                 return AnyValue.new(@ctx.undefined) unless k.is_a?(Int64)
                 idx = k
                 return AnyValue.new(@ctx.undefined) if idx < -raw.size.to_i64
                 pos = (idx < 0 ? raw.size.to_i64 + idx : idx)
                 (0 <= pos < raw.size) ? raw[pos.to_i32] : nil
               when String
                 k = key.raw.as?(Int64) || as_int(key.raw) || nil
                 return AnyValue.new(@ctx.undefined) unless k.is_a?(Int64)
                 idx = k
                 return AnyValue.new(@ctx.undefined) if idx < -raw.size.to_i64
                 pos = (idx < 0 ? raw.size.to_i64 + idx : idx)
                 (0 <= pos < raw.size) ? AnyValue.new(raw[pos.to_i32].to_s) : nil
               when TupleValue
                 k = key.raw.as?(Int64) || as_int(key.raw) || nil
                 return AnyValue.new(@ctx.undefined) unless k.is_a?(Int64)
                 idx = k
                 return AnyValue.new(@ctx.undefined) if idx < -raw.items.size.to_i64
                 pos = (idx < 0 ? raw.items.size.to_i64 + idx : idx)
                 (0 <= pos < raw.items.size) ? raw.items[pos] : nil
               when Nil
                 AnyValue.new(@ctx.undefined)
               else
                 get_attr(obj, key.raw.as?(String) || stringify(key)) || AnyValue.new(@ctx.undefined)
               end
      result || AnyValue.new(@ctx.undefined)
    end

    private def eval_slice(expr : Nodes::SliceNode) : AnyValue
      obj = eval(expr.obj)
      raw_step = expr.step ? eval(expr.step.not_nil!).raw : nil
      if expr.step && !raw_step.is_a?(Int64)
        # python raises on non-integer slice steps; jinja surfaces empty
        return obj.raw.is_a?(String) ? AnyValue.new("") : AnyValue.new([] of AnyValue)
      end
      step = expr.step ? (raw_step.as(Int64)) : 1i64
      size_hint = (obj.raw.is_a?(String) ? obj.raw.as(String).size : obj.raw.as?(Array).try(&.size)) || 0
      default_start = step < 0 ? (size_hint - 1).to_i64 : 0i64
      raise TemplateError.new("slice step cannot be zero", expr.line) if step == 0
      start = expr.start ? (eval(expr.start.not_nil!).raw.as?(Int64) || default_start) : default_start
      stop = expr.stop ? eval(expr.stop.not_nil!).raw.as?(Int64) : nil

      case raw = obj.raw
      when String
        idxs = slice_indices(raw.size, start, stop, step)
        AnyValue.new(idxs.map { |i| raw[i].to_s }.join)
      when Array
        idxs = slice_indices(raw.size, start, stop, step)
        AnyValue.new(idxs.map { |i| raw[i] })
      when TupleValue
        idxs = slice_indices(raw.items.size, start, stop, step)
        AnyValue.new(TupleValue.new(idxs.map { |i| raw.items[i] }))
      else
        raise TemplateError.new("cannot slice #{raw.class}", expr.line)
      end
    end

    private def slice_indices(size : Int32, start : Int64, stop : Int64?, step : Int64) : Array(Int32)
      s = start < 0 ? size + start : start
      e = stop.nil? ? (step > 0 ? size.to_i64 : -1i64) : (stop.not_nil! < 0 ? size + stop.not_nil! : stop.not_nil!)
      s = 0 if step > 0 && s < 0
      idxs = [] of Int32
      if step > 0
        i = s
        while i < e && i < size
          idxs << i.to_i32 if i >= 0
          i += step
        end
      else
        i = s >= size ? size - 1 : s
        while i > e && i >= 0
          idxs << i.to_i32 if i < size
          i += step
        end
      end
      idxs
    end

    private def eval_call(expr : Nodes::CallExprNode) : AnyValue
      func = eval(expr.func)
      args = [] of AnyValue
      expr.args.each do |a|
        if a.is_a?(Nodes::UnaryOpNode) && a.op == "*"
          item = eval(a.operand)
          args.concat(KrikriJinja.to_iterable(item))
        elsif a.is_a?(Nodes::UnaryOpNode) && a.op == "**"
          item = eval(a.operand)
          if item.raw.is_a?(Hash)
            item.raw.as(Hash).each { |k, v| expr.kwargs << {k, Nodes::ConstNode.new(v.raw, expr.line)} }
          end
        else
          args << eval(a)
        end
      end
      kwargs = eval_kwargs(expr.kwargs)
      case raw = func.raw
      when Callable
        raw.call(args, kwargs, @ctx)
      when LoopCallable
        raw.call(args, kwargs, @ctx)
      when Markup
        AnyValue.new(raw)
      else
        raise TemplateError.new("#{stringify(func)} is not callable", expr.line)
      end
    end

    private def eval_kwargs(kwargs : Array(Tuple(String, ExprNode))) : Hash(String, AnyValue)
      h = {} of String => AnyValue
      kwargs.each { |k, e| h[k] = eval(e) }
      h
    end
  end
end
