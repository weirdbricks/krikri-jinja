module KrikriJinja
  class LoopObject
    getter items : Array(AnyValue)
    property index : Int32
    getter depth : Int32
    property parent : LoopObject?
    property last_changed : AnyValue?

    def initialize(@items, @index, @parent = nil, @depth = 1)
    end

    def length : Int64
      @items.size.to_i64
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
      h["previtem"] = @index > 0 ? @items[@index - 1] : AnyValue.new(nil)
      h["nextitem"] = @index < @items.size - 1 ? @items[@index + 1] : AnyValue.new(nil)
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

    def initialize(@items, @body : Array(Nodes::Node), @ctx : Context, @engine : Engine,
                   @targets : Array(String), @parent = nil, @depth = 1, @sink : IO = IO::Memory.new)
    end

    def length : Int64
      @items.size.to_i64
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
      h["previtem"] = @index > 0 ? @items[@index - 1] : AnyValue.new(nil)
      h["nextitem"] = @index < @items.size - 1 ? @items[@index + 1] : AnyValue.new(nil)
      h
    end

    def call(args : Array(AnyValue), _kwargs : Hash(String, AnyValue), ctx : Context) : AnyValue
      first = args[0]?
      sub = LoopCallable.new(first ? (first.raw.is_a?(Array) ? first.raw.as(Array) : args) : args,
                             @body, ctx, @engine, @targets, self, @depth + 1, @sink)
      old_loop = ctx["loop"]?
      ctx.push_scope
      begin
        sub.items.each_with_index do |item, i|
          sub.index = i
          KrikriJinja.assign_targets(ctx, @targets, item)
          ctx["loop"] = AnyValue.new(sub)
          Evaluator.new(ctx, @engine, @sink).render_nodes(@body)
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

    def call(args : Array(AnyValue), kwargs : Hash(String, AnyValue), ctx : Context) : AnyValue
      ctx.push_scope
      begin
        remaining_args = args.size > @params.size ? args[@params.size..] : [] of AnyValue
        ctx["varargs"] = AnyValue.new(remaining_args)
        remaining_kwargs = kwargs.dup
        @params.each { |(pname, _)| remaining_kwargs.delete(pname) }
        ctx["kwargs"] = AnyValue.new(remaining_kwargs)
        ctx["name"] = AnyValue.new(@name)
        @params.each_with_index do |(pname, default), i|
          value = if i < args.size
                    args[i]
                  elsif kwargs.has_key?(pname)
                    kwargs[pname]
                  elsif default
                    Evaluator.new(@closure).eval(default.not_nil!)
                  else
                    AnyValue.new(nil)
                  end
          ctx[pname] = value
        end
        if (caller_val = ctx["__caller__"]?) && !ctx.has_key?("caller")
          ctx["caller"] = caller_val
        end
        rendered = Evaluator.new(ctx).render_nodes_to_string(@body)
        AnyValue.new(Markup.new(rendered))
      ensure
        ctx.pop_scope
      end
    end
  end

  # Caller body passed to macros via {% call %}.
  class CallerCallable < Callable
    def initialize(@body : Array(Nodes::Node), @ctx : Context, @params : Array(String) = [] of String)
    end

    def call(args : Array(AnyValue), _kwargs : Hash(String, AnyValue), ctx : Context) : AnyValue
      ctx.push_scope
      begin
        ctx["caller"] = AnyValue.new(self)
        @params.each_with_index do |pname, i|
          ctx[pname] = args[i]? || AnyValue.new(nil)
        end
        AnyValue.new(Markup.new(Evaluator.new(ctx).render_nodes_to_string(@body)))
      ensure
        ctx.pop_scope
      end
    end
  end

  def self.assign_targets(ctx : Context, targets : Array(String), value : AnyValue)
    if targets.size == 1
      ctx[targets[0]] = value
    else
      unpacked : Array(AnyValue) = case raw = value.raw
                                   when Array then raw
                                   when String then raw.chars.map { |c| AnyValue.new(c.to_s) }
                                   else raise TemplateError.new("cannot unpack #{raw.class}", 0)
                                   end
      raise TemplateError.new("too many values to unpack", 0) if unpacked.size < targets.size
      targets.each_with_index { |t, i| ctx[t] = unpacked[i] }
    end
  end

  class Engine
    getter loader : Loader?
    getter globals : Hash(String, AnyValue)
    getter options : LexerOptions
    getter autoescape : Bool

    def initialize(@loader : Loader? = nil, user_globals : Hash(String, AnyV) = {} of String => AnyV,
                   @options : LexerOptions = LexerOptions.new, @autoescape : Bool = false)
      globals = KrikriJinja.default_globals
      user_globals.each { |k, v| globals[k] = AnyValue.wrap(v) }
      @globals = globals
    end

    def render_string(source : String, variables : Hash(String, AnyV) = {} of String => AnyV) : String
      render_variables(source, variables)
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
      raise TemplateError.new("template #{name.inspect} not found", 0) unless source
      source
    end

    private def render_variables(source : String, variables)
      ctx = Context.new(@globals.dup, @loader)
      ctx.autoescape = @autoescape
      variables.each { |k, v| ctx[k] = AnyValue.wrap(v) }
      node = Parser.parse(source, @options)
      Evaluator.new(ctx, self).render_template(node)
    end

    def load(name : String) : Nodes::TemplateNode
      Parser.parse(load_source(name), @options)
    end
  end

  class Evaluator
    @ctx : Context
    @engine : Engine
    @out : ::IO

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
        end
        render_nodes(parent.body)
      else
        render_nodes(node.body)
      end
      @out.to_s
    end

    private def collect_blocks(body : Array(Nodes::Node))
      body.each do |n|
        case n
        when Nodes::BlockNode
          @ctx.register_block(n.name, n)
          collect_blocks(n.body)
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
            render_nodes(body)
            return
          end
        end
        render_nodes(node.orelse || [] of Nodes::Node)
      when Nodes::ForNode
        render_for(node)
      when Nodes::SetNode
        render_set(node)
      when Nodes::BlockNode
        blocks = @ctx.blocks[node.name]?
        if blocks && !blocks.empty?
          render_nodes(blocks.first.body)
        else
          render_nodes(node.body)
        end
      when Nodes::MacroNode
        @ctx[node.name] = AnyValue.new(MacroCallable.new(node.name, node.params, node.body, @ctx))
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
                                when Nil    then [] of AnyValue
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
        loop_obj = LoopCallable.new(items, node.body, @ctx, @engine, node.targets, parent_loop, (parent_loop.try(&.depth) || 0) + 1, @out)
        @ctx.push_scope
        begin
          items.each_with_index do |item, i|
            loop_obj.index = i
            assign_targets(node.targets, item)
            @ctx["loop"] = AnyValue.new(loop_obj)
            render_nodes(node.body)
          end
        ensure
          @ctx.pop_scope
          if parent_loop.nil?
            @ctx.delete("loop")
          else
            @ctx.scopes[0]["loop"] = AnyValue.new(parent_loop.not_nil!)
          end
        end
        return
      end

      parent_loop = @ctx["loop"]?.try(&.raw.as?(LoopObject))
      loop_obj = LoopObject.new(items, 0, parent: parent_loop, depth: (parent_loop.try(&.depth) || 0) + 1)
      @ctx.push_scope
      begin
        items.each_with_index do |item, i|
          assign_targets(node.targets, item)
          @ctx["loop"] = AnyValue.new(loop_obj)
          render_nodes(node.body)
          loop_obj.index = i + 1
        end
      ensure
        @ctx.pop_scope
        if parent_loop.nil?
          @ctx.delete("loop")
        else
          @ctx.scopes[0]["loop"] = AnyValue.new(parent_loop.not_nil!)
        end
      end
    end

    private def assign_targets(targets : Array(String), value : AnyValue)
      if targets.size == 1
        @ctx[targets[0]] = value
      else
        unpacked : Array(AnyValue) = case raw = value.raw
                                     when Array then raw
                                     when String then raw.chars.map { |c| AnyValue.new(c.to_s) }
                                     else raise TemplateError.new("cannot unpack #{raw.class}", 0)
                                     end
        raise TemplateError.new("too many values to unpack", 0) if unpacked.size < targets.size
        targets.each_with_index { |t, i| @ctx[t] = unpacked[i] }
      end
    end

    private def render_set(node : Nodes::SetNode)
      if body = node.body
        rendered = render_nodes_to_string(body)
        @ctx[node.targets.first] = AnyValue.new(rendered)
        return
      end
      value = eval(node.expr)
      if target = node.attr_target
        case target
        when Nodes::GetattrNode
          obj = eval(target.obj)
          if obj.raw.is_a?(Hash)
            obj.raw.as(Hash)[target.attr] = value
          elsif obj.raw.is_a?(Namespace)
            obj.raw.as(Namespace).data[target.attr] = value
          else
            raise TemplateError.new("cannot set attribute on #{obj.raw.class}", node.line)
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
          items = value.raw.as?(Array) || raise TemplateError.new("cannot unpack set target", node.line)
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
      filter_node = node.filter.as(Nodes::FilterNode)
      f = BUILTIN_FILTERS[filter_node.name]? ||
          raise TemplateError.new("unknown filter #{filter_node.name.inspect}", node.line)
      args = filter_node.args.map { |a| eval(a) }
      kwargs = eval_kwargs(filter_node.kwargs)
      @out << stringify(f.call(AnyValue.new(Markup.new(rendered)), args, kwargs, @ctx))
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
        raise TemplateError.new("template #{name.inspect} not found", node.line)
      end
      sub_ctx = node.with_context ? @ctx : Context.new(@ctx.globals, @ctx.loader, @ctx.autoescape)
      sub_node = Parser.parse(source)
      sub_eval = Evaluator.new(sub_ctx, @engine)
      sub_eval.render_template(sub_node)
      @out << sub_eval.output.to_s
    end

    private def render_import(node : Nodes::ImportNode)
      name = eval(node.template).raw.as?(String) ||
             raise TemplateError.new("import expects a template name", node.line)
      source = @ctx.loader.try(&.get_source(name))
      raise TemplateError.new("template #{name.inspect} not found", node.line) unless source
      sub_ctx = Context.new({} of String => AnyValue, @ctx.loader, @ctx.autoescape)
      sub_node = Parser.parse(source)
      collect_module_exports(sub_node.body, sub_ctx)
      mod = sub_ctx.scopes[0].dup
      if node.from_import
        node.names.each { |n| @ctx[n] = mod[n]? || AnyValue.new(nil) }
      else
        node.names.each { |n| @ctx[n] = AnyValue.new(mod) }
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
        @ctx[expr.name]
      when Nodes::ListExprNode
        AnyValue.new(expr.items.map { |i| eval(i) })
      when Nodes::TupleExprNode
        AnyValue.new(expr.items.map { |i| eval(i) })
      when Nodes::DictExprNode
        h = {} of String => AnyValue
        expr.keys.each_with_index do |k, i|
          h[stringify(eval(k))] = eval(expr.values[i])
        end
        AnyValue.new(h)
      when Nodes::BinOpNode
        eval_binop(expr)
      when Nodes::UnaryOpNode
        case expr.op
        when "not" then AnyValue.new(!truthy?(eval(expr.operand)))
        when "-" then AnyValue.new(negate(eval(expr.operand).raw))
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
          expr.falsy ? eval(expr.falsy.not_nil!) : AnyValue.new(nil)
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

    private def add(a : AnyV, b : AnyV) : AnyV
      case {a, b}
      when {Int64, Int64} then a + b
      when {Float64, Float64} then a + b
      when {Int64, Float64} then a.to_f64 + b
      when {Float64, Int64} then a + b.to_f64
      when {String, String} then a + b
      when {Array, Array} then a + b
      else raise TemplateError.new("unsupported operands for +: #{a.class} and #{b.class}", 0)
      end
    end

    private def subtract(a : AnyV, b : AnyV) : AnyV
      case {a, b}
      when {Int64, Int64} then a - b
      when {Float64, Float64} then a - b
      when {Int64, Float64} then a.to_f64 - b
      when {Float64, Int64} then a - b.to_f64
      else raise TemplateError.new("unsupported operands for -: #{a.class} and #{b.class}", 0)
      end
    end

    private def multiply(a : AnyV, b : AnyV) : AnyV
      case {a, b}
      when {Int64, Int64} then a * b
      when {Float64, Float64} then a * b
      when {Int64, Float64} then a.to_f64 * b
      when {Float64, Int64} then a * b.to_f64
      when {String, Int64} then a * b
      when {Int64, String} then b * a
      else raise TemplateError.new("unsupported operands for *: #{a.class} and #{b.class}", 0)
      end
    end

    private def divide(a : AnyV, b : AnyV) : AnyV
      x = a.as?(Float64) || a.as?(Int64).try(&.to_f64)
      y = b.as?(Float64) || b.as?(Int64).try(&.to_f64)
      raise TemplateError.new("unsupported operand for /", 0) unless x && y
      raise TemplateError.new("division by zero", 0) if y == 0.0
      x / y
    end

    private def floor_divide(a : AnyV, b : AnyV) : AnyV
      if a.is_a?(Int64) && b.is_a?(Int64)
        raise TemplateError.new("integer division or modulo by zero", 0) if b == 0
        a // b
      else
        x = a.as?(Float64) || a.as?(Int64).try(&.to_f64) || raise TemplateError.new("unsupported operand", 0)
        y = b.as?(Float64) || b.as?(Int64).try(&.to_f64) || raise TemplateError.new("unsupported operand", 0)
        raise TemplateError.new("division by zero", 0) if y == 0.0
        (x / y).floor.to_f64
      end
    end

    private def modulo(a : AnyV, b : AnyV) : AnyV
      if a.is_a?(Int64) && b.is_a?(Int64)
        raise TemplateError.new("integer division or modulo by zero", 0) if b == 0
        r = a % b
        r = r + b.abs if r != 0 && (r < 0) != (b < 0)
        r
      else
        x = a.as?(Float64) || a.as?(Int64).try(&.to_f64) || raise TemplateError.new("unsupported operand", 0)
        y = b.as?(Float64) || b.as?(Int64).try(&.to_f64) || raise TemplateError.new("unsupported operand", 0)
        raise TemplateError.new("division by zero", 0) if y == 0.0
        r = x % y
        r = r + y.abs if r != 0 && (r < 0) != (y < 0)
        r
      end
    end

    private def power(a : AnyV, b : AnyV) : AnyV
      if a.is_a?(Int64) && b.is_a?(Int64) && b >= 0
        a ** b
      else
        (a.as?(Float64) || a.as?(Int64).try(&.to_f64) || raise TemplateError.new("unsupported operand", 0)) ** (b.as?(Float64) || b.as?(Int64).try(&.to_f64) || raise TemplateError.new("unsupported operand", 0))
      end
    end

    private def negate(v : AnyV) : AnyV
      case v
      when Int64 then -v
      when Float64 then -v
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
             when "in" then contains?(right, left)
             when "not in" then !contains?(right, left)
             else raise TemplateError.new("unknown comparison #{op}", expr.line)
             end
        return false unless ok
        left = right
      end
      true
    end

    private def eval_filter(expr : Nodes::FilterNode) : AnyValue
      value = eval(expr.target)
      f = BUILTIN_FILTERS[expr.name]? ||
          raise TemplateError.new("unknown filter #{expr.name.inspect}", expr.line)
      args = expr.args.map { |a| eval(a) }
      kwargs = eval_kwargs(expr.kwargs)
      f.call(value, args, kwargs, @ctx)
    end

    private def eval_test(expr : Nodes::TestNode) : Bool
      value = eval(expr.target)
      t = BUILTIN_TESTS[expr.name]? ||
          raise TemplateError.new("unknown test #{expr.name.inspect}", expr.line)
      args = expr.args.map { |a| eval(a) }
      kwargs = eval_kwargs(expr.kwargs)
      result = t.call(value, args, kwargs, @ctx)
      expr.negated ? !result : result
    end

    private def eval_getattr(expr : Nodes::GetattrNode) : AnyValue
      obj = eval(expr.obj)
      get_attr(obj, expr.attr) || AnyValue.new(nil)
    end

    private def eval_getitem(expr : Nodes::GetitemNode) : AnyValue
      obj = eval(expr.obj)
      key = eval(expr.key)
      result = case raw = obj.raw
               when Hash
                 k = key.raw.as?(String) || stringify(key)
                 raw[k]?
               when Array
                 idx = key.raw.as?(Int64) || raise TemplateError.new("list indices must be integers", expr.line)
                 idx < 0 ? raw[raw.size + idx]? : raw[idx]?
               when String
                 idx = key.raw.as?(Int64) || raise TemplateError.new("string indices must be integers", expr.line)
                 pos = idx < 0 ? raw.size + idx : idx
                 (0 <= pos < raw.size) ? AnyValue.new(raw[pos].to_s) : nil
               when Nil
                 nil
               else
                 get_attr(obj, key.raw.as?(String) || stringify(key))
               end
      result || AnyValue.new(nil)
    end

    private def eval_slice(expr : Nodes::SliceNode) : AnyValue
      obj = eval(expr.obj)
      step = expr.step ? (eval(expr.step.not_nil!).raw.as?(Int64) || 1i64) : 1i64
      size_hint = (obj.raw.is_a?(String) ? obj.raw.as(String).size : obj.raw.as?(Array).try(&.size)) || 0
      default_start = step < 0 ? (size_hint - 1).to_i64 : 0i64
      start = expr.start ? (eval(expr.start.not_nil!).raw.as?(Int64) || default_start) : default_start
      stop = expr.stop ? eval(expr.stop.not_nil!).raw.as?(Int64) : nil

      case raw = obj.raw
      when String
        idxs = slice_indices(raw.size, start, stop, step)
        AnyValue.new(idxs.map { |i| raw[i].to_s }.join)
      when Array
        idxs = slice_indices(raw.size, start, stop, step)
        AnyValue.new(idxs.map { |i| raw[i] })
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
      args = expr.args.map { |a| eval(a) }
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
