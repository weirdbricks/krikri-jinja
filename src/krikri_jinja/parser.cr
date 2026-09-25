module KrikriJinja
  # Recursive-descent parser over the lexer's token stream.
  #
  # Written against the Jinja2 Template Designer Documentation (the public
  # spec of what templates must mean), not against any implementation.
  class Parser
    @tokens : Array(Token)
    @pos = 0

    def initialize(@tokens : Array(Token))
    end

    def self.parse(source : String, options : LexerOptions = LexerOptions.new) : Nodes::TemplateNode
      new(Lexer.new(source, options).tokens).parse_template
    end

    def self.parse_expression(source : String, options : LexerOptions = LexerOptions.new) : Nodes::ExprNode
      parser = new(Lexer.new("{{ #{source} }}", options).tokens)
      parser.advance
      expr = parser.parse_expression
      unless parser.current.type == TokenType::VarEnd
        raise TemplateError.new("unexpected token after expression", parser.current.line)
      end
      expr
    end

    def parse_template : Nodes::TemplateNode
      body, _tag, _line = parse_until(nil)
      Nodes::TemplateNode.new(body, 1)
    end

    # Parses nodes until a tag in `end_tags` is found (the tag token is
    # consumed and its name returned), or EOF when `end_tags` is nil.
    private def parse_until(end_tags : Array(String)?) : Tuple(Array(Nodes::Node), String, Int32)
      body = [] of Nodes::Node
      while true
        tok = current
        case tok.type
        when TokenType::Eof
          if end_tags
            raise TemplateError.new("unexpected end of template, expected one of #{end_tags.join(", ")}", tok.line)
          end
          return body, "", tok.line
        when TokenType::Text
          body << Nodes::TextNode.new(tok.value, tok.line)
          advance
        when TokenType::VarStart
          line = tok.line
          advance
          expr = parse_expression
          expect_var_end
          body << Nodes::OutputNode.new(expr, line)
        when TokenType::BlockStart
          name_tok = peek(1)
          tag_name = name_tok.type == TokenType::Ident ? name_tok.value : ""
          if end_tags && end_tags.includes?(tag_name)
            advance # block start
            advance # tag name
            expect_block_end unless tag_name == "elif"
            return body, tag_name, tok.line
          end
          body << parse_block_tag
        else
          raise TemplateError.new("unexpected #{tok.type}", tok.line)
        end
      end
    end

    private def parse_block_tag : Nodes::Node
      start = current
      line = start.line
      advance # consume block start
      tag_tok = current
      unless tag_tok.type == TokenType::Ident
        raise TemplateError.new("expected tag name after block start", line)
      end
      tag = tag_tok.value
      line = tag_tok.line
      advance

      case tag
      when "if"        then parse_if(line)
      when "for"       then parse_for(line)
      when "set"       then parse_set(line)
      when "block"     then parse_block(line)
      when "macro"     then parse_macro(line)
      when "call"      then parse_call(line)
      when "filter"    then parse_filter_block(line)
      when "with"      then parse_with(line)
      when "include"   then parse_include(line)
      when "extends"   then parse_extends(line)
      when "import", "from" then parse_import(tag, line)
      when "do"        then parse_do(line)
      when "autoescape" then parse_autoescape(line)
      when "raw"
        raise TemplateError.new("raw should have been handled by the lexer", line)
      else
        raise TemplateError.new("unknown tag #{tag.inspect}", line)
      end
    end

    private def parse_if(line : Int32) : Nodes::IfNode
      branches = [] of Tuple(ExprNode, Array(Node))
      cond = parse_expression
      expect_block_end
      body, tag, _ = parse_until(["elif", "else", "endif"])
      branches << {cond, body}
      while tag == "elif"
        cond = parse_expression
        expect_block_end
        body, tag, _ = parse_until(["elif", "else", "endif"])
        branches << {cond, body}
      end
      orelse = nil
      if tag == "else"
        orelse, _tag, _ = parse_until(["endif"])
      end
      Nodes::IfNode.new(branches, orelse, line)
    end

    private def parse_for(line : Int32) : Nodes::ForNode
      targets = parse_target_list
      expect_ident("in")
      iter = parse_tuple_no_cond
      test = nil
      if accept_ident("if")
        test = parse_expression
      end
      recursive = !!accept_ident("recursive")
      expect_block_end
      body, tag, _ = parse_until(["else", "endfor"])
      orelse = nil
      if tag == "else"
        orelse, _tag, _ = parse_until(["endfor"])
      end
      Nodes::ForNode.new(targets, iter, body, orelse, test, recursive, line)
    end

    private def parse_set(line : Int32) : Nodes::SetNode
      # Try `set ns.attr = expr` vs `set a, b = expr` vs `set a = expr`
      first_tok = current
      unless first_tok.type == TokenType::Ident
        raise TemplateError.new("expected target name in set", line)
      end
      first_name = first_tok.value
      advance
      if accept_op(".")
        attr_tok = current
        unless attr_tok.type == TokenType::Ident
          raise TemplateError.new("expected attribute name after '.' in set", line)
        end
        advance
        target = Nodes::GetattrNode.new(Nodes::NameNode.new(first_name, line), attr_tok.value, line)
        expect_op("=")
        value = parse_expression
        expect_block_end
        Nodes::SetNode.new([first_name], value, target, line)
      elsif accept_op("|")
        fname_tok = current
        unless fname_tok.type == TokenType::Ident
          raise TemplateError.new("expected filter name after '|' in set", line)
        end
        advance
        fargs = [] of ExprNode
        fkwargs = [] of Tuple(String, ExprNode)
        if accept_op("(")
          loop do
            break if accept_op(")")
            if current.type == TokenType::Ident && peek(1).type == TokenType::Op &&
               peek(1).value == "="
              k = current.value
              advance
              advance
              fkwargs << {k, parse_expression}
            else
              fargs << parse_expression
            end
            unless accept_op(",")
              expect_op(")")
              break
            end
            break if accept_op(")")
          end
        end
        expect_block_end
        body, _tag, _ = parse_until(["endset"])
        value = Nodes::ConstNode.new("__set_block__", line)
        node = Nodes::SetNode.new(targets_block(first_name), value, nil, line)
        node.body = body
        node.filter_name = fname_tok.value
        node.filter_args = fargs
        node.filter_kwargs = fkwargs
        node
      elsif accept_block_end
        # block form: {% set x %}...{% endset %}
        body, _tag, _ = parse_until(["endset"])
        value = Nodes::ConstNode.new("__set_block__", line)
        node = Nodes::SetNode.new(targets_block(first_name), value, nil, line)
        node.body = body
        node
      else
        targets = [first_name]
        while accept_op(",")
          targets << parse_target_name
        end
        expect_op("=")
        value = parse_tuple_expression
        expect_block_end
        Nodes::SetNode.new(targets, value, nil, line)
      end
    end

    private def targets_block(name : String) : Array(String)
      [name]
    end

    private def parse_block(line : Int32) : Nodes::BlockNode
      name = current
      unless name.type == TokenType::Ident
        raise TemplateError.new("expected block name", line)
      end
      block_name = name.value
      advance
      # `scoped` / `required` modifiers are accepted; scoping semantics
      # are not observable without includes-over-blocks and are ignored.
      accept_ident("scoped")
      required = !!accept_ident("required")
      expect_block_end
      body, _tag, _ = parse_until(["endblock"])
      if required && body.any? { |n| !(n.is_a?(Nodes::TextNode) && n.text.strip.empty?) }
        raise TemplateError.new("Required blocks can only contain comments or whitespace", line)
      end
      Nodes::BlockNode.new(block_name, body, line)
    end

    private def parse_macro(line : Int32) : Nodes::MacroNode
      name = current
      unless name.type == TokenType::Ident
        raise TemplateError.new("expected macro name", line)
      end
      macro_name = name.value
      advance
      params = parse_param_list
      expect_block_end
      body, _tag, _ = parse_until(["endmacro"])
      Nodes::MacroNode.new(macro_name, params, body, line)
    end

    private def parse_param_list : Array(Tuple(String, ExprNode?))
      expect_op("(")
      params = [] of Tuple(String, ExprNode?)
      loop do
        break if accept_op(")")
        tok = current
        unless tok.type == TokenType::Ident
          raise TemplateError.new("expected parameter name", tok.line)
        end
        pname = tok.value
        advance
        default = nil
        if accept_op("=")
          default = parse_expression
        end
        if pname == "caller" && default.nil?
          raise TemplateError.new("the special 'caller' argument must be omitted or given a default", tok.line)
        end
        params << {pname, default}
        unless accept_op(",")
          expect_op(")")
          break
        end
        break if accept_op(")")
      end
      params
    end

    private def parse_call(line : Int32) : Nodes::CallNode
      call_params = [] of String
      if current.type == TokenType::Op && current.value == "("
        # {% call(x, y) macro() %} - caller body parameter names
        advance
        loop do
          break if accept_op(")")
          call_params << parse_target_name
          break if accept_op(")")
          unless accept_op(",")
            raise TemplateError.new("expected ',' or ')' in call parameters", current.line)
          end
        end
      end
      parsed = parse_expression
      args, kwargs = if parsed.is_a?(Nodes::CallExprNode)
                       macro_expr = parsed.func
                       call_args = parsed.args
                       call_kwargs = parsed.kwargs
                       {call_args, call_kwargs}
                     else
                       macro_expr = parsed
                       parse_arg_list
                     end
      body = nil
      if accept_block_end
        inner, _tag, _ = parse_until(["endcall"])
        body = inner
      else
        expect_block_end
      end
      node = Nodes::CallNode.new(macro_expr, args, kwargs, body, line)
      node.call_params = call_params
      node
    end

    private def parse_filter_block(line : Int32) : Nodes::FilterBlockNode
      filter = parse_filter_expr
      while accept_op("|")
        filter = parse_filter_expr(filter)
      end
      expect_block_end
      body, _tag, _ = parse_until(["endfilter"])
      Nodes::FilterBlockNode.new(filter, body, line)
    end

    private def parse_with(line : Int32) : Nodes::WithNode
      bindings = [] of Tuple(String, ExprNode)
      loop do
        tok = current
        unless tok.type == TokenType::Ident
          break
        end
        name = tok.value
        advance
        expect_op("=")
        bindings << {name, parse_expression}
        break unless accept_op(",")
      end
      expect_block_end
      body, _tag, _ = parse_until(["endwith"])
      Nodes::WithNode.new(bindings, body, line)
    end

    private def parse_include(line : Int32) : Nodes::IncludeNode
      template = parse_expression
      ignore = false
      with_ctx = true
      loop do
        if accept_ident("ignore")
          expect_ident("missing")
          ignore = true
        elsif accept_ident("with")
          expect_ident("context")
          with_ctx = true
        elsif accept_ident("without")
          expect_ident("context")
          with_ctx = false
        else
          break
        end
      end
      expect_block_end
      Nodes::IncludeNode.new(template, ignore, with_ctx, line)
    end

    private def parse_extends(line : Int32) : Nodes::ExtendsNode
      template = parse_expression
      expect_block_end
      Nodes::ExtendsNode.new(template, line)
    end

    private def parse_import(tag : String, line : Int32) : Nodes::ImportNode
      template = parse_expression
      names = [] of Tuple(String, String)
      with_context = false
      if tag == "from"
        expect_ident("import")
        loop do
          tok = current
          unless tok.type == TokenType::Ident
            raise TemplateError.new("expected name after import", tok.line)
          end
          name = tok.value
          advance
          alias_name = name
          if accept_ident("as")
            alias_name = parse_target_name
          end
          names << {name, alias_name}
          break unless accept_op(",")
        end
      else
        expect_ident("as")
        alias_name = parse_target_name
        names << {alias_name, alias_name}
      end
      if accept_ident("with")
        expect_ident("context")
        with_context = true
      elsif accept_ident("without")
        expect_ident("context")
      end
      expect_block_end
      Nodes::ImportNode.new(template, names, with_context, tag == "from", line)
    end

    private def parse_do(line : Int32) : Nodes::DoNode
      expr = parse_expression
      expect_block_end
      Nodes::DoNode.new(expr, line)
    end

    private def parse_autoescape(line : Int32) : Nodes::AutoescapeNode
      enabled = true
      tok = current
      if tok.type == TokenType::Ident
        if tok.value == "true" || tok.value == "True"
          enabled = true
          advance
        elsif tok.value == "false" || tok.value == "False"
          enabled = false
          advance
        end
      end
      expect_block_end
      body, _tag, _ = parse_until(["endautoescape"])
      Nodes::AutoescapeNode.new(enabled, body, line)
    end

    # --- targets --------------------------------------------------------------

    private def parse_target_list : Array(TargetSpec)
      targets = [parse_target_spec]
      while accept_op(",")
        targets << parse_target_spec
      end
      targets
    end

    private def parse_target_spec : TargetSpec
      if current.type == TokenType::Op && current.value == "("
        advance
        children = [parse_target_spec]
        while accept_op(",")
          children << parse_target_spec
        end
        expect_op(")")
        return TargetSpec.new("", children)
      end
      TargetSpec.new(parse_target_name)
    end

    private def parse_target_name : String
      tok = current
      unless tok.type == TokenType::Ident
        raise TemplateError.new("expected name, got #{tok.type}", tok.line)
      end
      advance
      tok.value
    end

    private def expect_ident(name : String)
      tok = current
      unless tok.type == TokenType::Ident && tok.value == name
        raise TemplateError.new("expected #{name.inspect}, got #{tok.value.inspect}", tok.line)
      end
      advance
    end

    private def accept_ident(name : String) : Bool
      tok = current
      if tok.type == TokenType::Ident && tok.value == name
        advance
        true
      else
        false
      end
    end

    # --- expressions ------------------------------------------------------------
    # Precedence (low to high), per the designer docs:
    #   cond (a if b else c)
    #   or
    #   and
    #   not
    #   comparisons (==, !=, <, >, <=, >=, in, not in, is, is not)
    #   ~ (concat)
    #   + -
    #   * / // %
    #   unary + - not is not applicable here
    #   **
    #   postfix: filters, calls, attributes, items

    def parse_expression : Nodes::ExprNode
      parse_cond
    end

    # Like parse_tuple_expression but the items cannot be `a if b else c`
    # conditional expressions (used by {% for %} so the loop `if` filter
    # is not swallowed by the ternary grammar).
    def parse_tuple_no_cond : Nodes::ExprNode
      first = parse_or
      if current.type == TokenType::Op && current.value == ","
        items = [first]
        while accept_op(",")
          break if at_block_or_var_end
          items << parse_or
        end
        return Nodes::TupleExprNode.new(items, first.line)
      end
      first
    end

    # Tuple expressions: `a, b, c` only meaningful where tuples are allowed.
    def parse_tuple_expression : Nodes::ExprNode
      first = parse_expression
      if current.type == TokenType::Op && current.value == ","
        items = [first]
        while accept_op(",")
          break if at_block_or_var_end
          items << parse_expression
        end
        return Nodes::TupleExprNode.new(items, first.line)
      end
      first
    end

    private def parse_cond : Nodes::ExprNode
      expr = parse_or
      if accept_ident("if")
        test = parse_or
        falsy = nil
        if accept_ident("else")
          falsy = parse_expression
        end
        return Nodes::CondExprNode.new(test, expr, falsy, expr.line)
      end
      expr
    end

    private def parse_or : Nodes::ExprNode
      expr = parse_and
      while accept_ident("or")
        expr = Nodes::BinOpNode.new("or", expr, parse_and, expr.line)
      end
      expr
    end

    private def parse_and : Nodes::ExprNode
      expr = parse_not
      while accept_ident("and")
        expr = Nodes::BinOpNode.new("and", expr, parse_not, expr.line)
      end
      expr
    end

    private def parse_not : Nodes::ExprNode
      line = current.line
      if accept_ident("not")
        # `not` binds looser than comparisons: `not a in b` == not (a in b)
        return Nodes::UnaryOpNode.new("not", parse_not, line)
      end
      parse_compare
    end

    private def parse_compare : Nodes::ExprNode
      left = parse_concat
      ops = [] of String
      comparators = [] of ExprNode
      loop do
        tok = current
        op = nil
        if tok.type == TokenType::Op && {"==", "!=", "<", ">", "<=", ">="}.includes?(tok.value)
          op = tok.value
          advance
        elsif tok.type == TokenType::Ident && tok.value == "in"
          op = "in"
          advance
        elsif tok.type == TokenType::Ident && tok.value == "not" &&
              peek(1).type == TokenType::Ident && peek(1).value == "in"
          op = "not in"
          advance
          advance
        elsif tok.type == TokenType::Ident && tok.value == "is"
          advance
          left = parse_test(left)
          # filters may follow a test: `x is odd | string`
          while current.type == TokenType::Op && current.value == "|"
            advance
            left = parse_filter_call(left)
          end
          next
        else
          break
        end
        comparators << parse_concat
        ops << op.not_nil!
      end
      return left if ops.empty?
      Nodes::CompareNode.new(left, ops, comparators, left.line)
    end

    # `x is test [args]` / `x is not test`
    private def parse_test(left : ExprNode) : ExprNode
      negated = !!accept_ident("not")
      tok = current
      unless tok.type == TokenType::Ident
        raise TemplateError.new("expected test name after 'is'", tok.line)
      end
      name = tok.value
      advance
      if current.type == TokenType::Ident && current.value == "is"
        raise TemplateError.new("You cannot chain multiple tests with is", current.line)
      end
      args = [] of ExprNode
      kwargs = [] of Tuple(String, ExprNode)
      # a single trailing argument without parens is allowed: `is divisibleby 3`;
      # it binds as a primary/postfix chain, so `1 is eq 1 + 1` is (1 is eq 1) + 1
      if !at_block_or_var_end && !at_filter_or_paren_end && is_test_arg_start
        args << parse_postfix_no_filter
      end
      if accept_op("(")
        loop do
          break if accept_op(")")
          if current.type == TokenType::Ident && peek(1).type == TokenType::Op &&
             peek(1).value == "="
            k = current.value
            advance
            advance
            kwargs << {k, parse_expression}
          else
            args << parse_expression
          end
          unless accept_op(",")
            expect_op(")")
            break
          end
          break if accept_op(")")
        end
      end
      Nodes::TestNode.new(name, args, kwargs, left, negated, left.line)
    end

    private def is_test_arg_start : Bool
      tok = current
      case tok.type
      when TokenType::Int, TokenType::Float, TokenType::String
        true
      when TokenType::Ident
        !{"else", "or", "and"}.includes?(tok.value)
      when TokenType::Op
        {"[", "{"}.includes?(tok.value)
      else
        false
      end
    end

    private def at_filter_or_paren_end : Bool
      tok = current
      tok.type == TokenType::Op && {"|", ")", ",", "]"}.includes?(tok.value)
    end

    private def at_block_or_var_end : Bool
      t = current.type
      t == TokenType::BlockEnd || t == TokenType::VarEnd || t == TokenType::Eof
    end

    private def parse_concat : Nodes::ExprNode
      first = parse_add
      if current.type == TokenType::Op && current.value == "~"
        parts = [first]
        while accept_op("~")
          parts << parse_add
        end
        return Nodes::ConcatNode.new(parts, first.line)
      end
      first
    end

    private def parse_add : Nodes::ExprNode
      expr = parse_sub_is_add_really
      while true
        tok = current
        if tok.type == TokenType::Op && (tok.value == "+" || tok.value == "-")
          advance
          expr = Nodes::BinOpNode.new(tok.value, expr, parse_mul, tok.line)
        else
          break
        end
      end
      expr
    end

    private def parse_sub_is_add_really : Nodes::ExprNode
      parse_mul
    end

    private def parse_mul : Nodes::ExprNode
      expr = parse_pow
      while true
        tok = current
        if tok.type == TokenType::Op && {"*", "/", "//", "%"}.includes?(tok.value)
          advance
          expr = Nodes::BinOpNode.new(tok.value, expr, parse_pow, tok.line)
        else
          break
        end
      end
      expr
    end

    private def parse_pow : Nodes::ExprNode
      expr = parse_unary
      if expr.is_a?(Nodes::UnaryOpNode) && {"-", "+"}.includes?(expr.op) &&
         numeric_const?(expr.operand) && current.type == TokenType::Op && current.value == "**"
        # jinja folds -<literal> into a signed constant; the emitted python
        # source then re-applies normal precedence unless the exponent is
        # also fully constant: -2 ** p == -(2 ** p), -2 ** 2 == (-2) ** 2
        base = expr.not_nil!
        advance
        exp = parse_pow
        if expr_constant?(exp)
          expr = Nodes::BinOpNode.new("**", base, exp, base.line)
        else
          inner = base.operand
          pow = Nodes::BinOpNode.new("**", inner, exp, base.line)
          expr = base.op == "-" ? Nodes::UnaryOpNode.new("-", pow, base.line).as(ExprNode) : pow.as(ExprNode)
        end
        return expr
      end
      while current.type == TokenType::Op && current.value == "**"
        advance
        expr = Nodes::BinOpNode.new("**", expr, parse_unary, expr.line)
      end
      expr
    end

    private def numeric_const?(node : Nodes::ExprNode) : Bool
      node.is_a?(Nodes::ConstNode) && (v = node.value; v.is_a?(Int64) || v.is_a?(BigIntValue) || v.is_a?(Float64))
    end

    private def expr_constant?(node : Nodes::ExprNode) : Bool
      case node
      when Nodes::ConstNode then true
      when Nodes::UnaryOpNode then expr_constant?(node.operand)
      when Nodes::BinOpNode then expr_constant?(node.left) && expr_constant?(node.right)
      when Nodes::ListExprNode then node.items.all? { |i| expr_constant?(i) }
      when Nodes::TupleExprNode then node.items.all? { |i| expr_constant?(i) }
      when Nodes::DictExprNode
        node.keys.all? { |k| expr_constant?(k) } && node.values.all? { |v| expr_constant?(v) }
      when Nodes::FilterNode
        expr_constant?(node.target) &&
          node.args.all? { |a| expr_constant?(a) } &&
          node.kwargs.all? { |(_, v)| expr_constant?(v) }
      when Nodes::GetitemNode
        expr_constant?(node.obj) && expr_constant?(node.key)
      else false
      end
    end

    private def parse_unary : Nodes::ExprNode
      tok = current
      if tok.type == TokenType::Op && {"-", "+"}.includes?(tok.value)
        advance
        operand = parse_unary_no_filter
        expr = Nodes::UnaryOpNode.new(tok.value, operand, tok.line).as(ExprNode)
        # python: unary binds tighter than `is` tests and filters apply to
        # the negated value (-4.7|abs == abs(-4.7))
        return parse_postfix_from(expr, expr.line, allow_filter: true, allow_test: true)
      end
      parse_postfix
    end

    private def parse_unary_no_filter : Nodes::ExprNode
      tok = current
      if tok.type == TokenType::Op && {"-", "+"}.includes?(tok.value)
        advance
        operand = parse_unary_no_filter
        return tok.value == "-" ? Nodes::UnaryOpNode.new("-", operand, tok.line).as(ExprNode) : operand
      end
      parse_postfix_no_filter
    end

    private def parse_postfix : Nodes::ExprNode
      expr = parse_primary
      parse_postfix_from(expr, expr.line)
    end

    private def parse_postfix_no_filter : Nodes::ExprNode
      expr = parse_primary
      parse_postfix_from(expr, expr.line, allow_filter: false, allow_test: false)
    end

    private def parse_postfix_from(expr : ExprNode, line : Int32, allow_filter = true, allow_test = true) : ExprNode
      loop do
        tok = current
        if tok.type == TokenType::Op && tok.value == "."
          advance
          attr = current
          unless attr.type == TokenType::Ident
            raise TemplateError.new("expected attribute name after '.'", attr.line)
          end
          advance
          expr = Nodes::GetattrNode.new(expr, attr.value, line)
        elsif tok.type == TokenType::Op && tok.value == "["
          advance
          start, stop, step, is_slice = parse_slice_parts
          if is_slice
            expr = Nodes::SliceNode.new(expr, start, stop, step, line)
          else
            expr = Nodes::GetitemNode.new(expr, start.not_nil!, line)
          end
        elsif tok.type == TokenType::Op && tok.value == "("
          args, kwargs = parse_arg_list
          expr = Nodes::CallExprNode.new(expr, args, kwargs, line)
        elsif tok.type == TokenType::Ident && tok.value == "is" && allow_test
          advance
          expr = parse_test(expr)
        elsif tok.type == TokenType::Op && tok.value == "|" && allow_filter
          advance
          name_tok = current
          unless name_tok.type == TokenType::Ident
            raise TemplateError.new("expected filter name after '|'", name_tok.line)
          end
          advance
          fname = name_tok.value
          # jinja parses dotted names as one filter name (which then fails
          # lookup): `x | first.to_s` is "No filter named 'first.to_s'"
          while current.type == TokenType::Op && current.value == "." &&
                peek(1).type == TokenType::Ident
            advance
            fname += ".#{current.value}"
            advance
          end
          args = [] of ExprNode
          kwargs = [] of Tuple(String, ExprNode)
          if accept_op("(")
            args, kwargs = parse_call_args_until_close
          end
          expr = Nodes::FilterNode.new(fname, args, kwargs, expr, line)
        else
          break
        end
      end
      expr
    end

    private def parse_filter_call(left : ExprNode) : ExprNode
      name_tok = current
      unless name_tok.type == TokenType::Ident
        raise TemplateError.new("expected filter name after '|'", name_tok.line)
      end
      advance
      args = [] of ExprNode
      kwargs = [] of Tuple(String, ExprNode)
      if accept_op("(")
        args, kwargs = parse_call_args_until_close
      end
      Nodes::FilterNode.new(name_tok.value, args, kwargs, left, left.line)
    end

    private def parse_slice_parts : Tuple(ExprNode?, ExprNode?, ExprNode?, Bool)
      start : ExprNode? = nil
      stop : ExprNode? = nil
      step : ExprNode? = nil
      is_slice = false

      unless current.type == TokenType::Op && current.value == ":"
        start = parse_expression
      end
      if accept_op(":")
        is_slice = true
        unless current.type == TokenType::Op && {"]", ":"}.includes?(current.value)
          stop = parse_expression
        end
        if accept_op(":")
          unless current.type == TokenType::Op && current.value == "]"
            step = parse_expression
          end
        end
      end
      expect_op("]")
      {start, stop, step, is_slice}
    end

    private def parse_arg_list : Tuple(Array(ExprNode), Array(Tuple(String, ExprNode)))
      expect_op("(")
      parse_call_args_until_close
    end

    private def parse_call_args_until_close : Tuple(Array(ExprNode), Array(Tuple(String, ExprNode)))
      args = [] of ExprNode
      kwargs = [] of Tuple(String, ExprNode)
      loop do
        break if accept_op(")")
        if current.type == TokenType::Op && current.value == "*"
          advance
          args << Nodes::UnaryOpNode.new("*", parse_expression, current.line)
        elsif current.type == TokenType::Op && current.value == "**"
          advance
          args << Nodes::UnaryOpNode.new("**", parse_expression, current.line)
        elsif current.type == TokenType::Ident && peek(1).type == TokenType::Op && peek(1).value == "=" &&
              !{"true", "false", "True", "False", "none", "None"}.includes?(current.value)
          k = current.value
          advance
          advance
          kwargs << {k, parse_expression}
        elsif !kwargs.empty?
          raise TemplateError.new("invalid syntax for function call expression", current.line)
        else
          args << parse_expression
        end
        unless accept_op(",")
          expect_op(")")
          break
        end
        break if accept_op(")")
      end
      {args, kwargs}
    end

    private def parse_primary : ExprNode
      tok = current
      line = tok.line
      case tok.type
      when TokenType::Int
        advance
        # int literals beyond Int64 become BigIntValue
        Nodes::ConstNode.new(BigIntValue.parse(tok.value), line)
      when TokenType::Float
        advance
        Nodes::ConstNode.new(tok.value.to_f64, line)
      when TokenType::String
        advance
        # adjacent string literals concatenate
        value = tok.value
        while current.type == TokenType::String
          value += current.value
          advance
        end
        Nodes::ConstNode.new(value, line)
      when TokenType::Ident
        case tok.value
        when "true", "True"
          advance
          Nodes::ConstNode.new(true, line)
        when "false", "False"
          advance
          Nodes::ConstNode.new(false, line)
        when "none", "None"
          advance
          Nodes::ConstNode.new(nil, line)
        else
          advance
          Nodes::NameNode.new(tok.value, line)
        end
      when TokenType::Op
        case tok.value
        when "("
          advance
          if accept_op(")")
            return Nodes::TupleExprNode.new([] of ExprNode, line)
          end
          first = parse_expression
          is_tuple = false
          closed = false
          items = [first]
          while accept_op(",")
            is_tuple = true
            if accept_op(")")
              closed = true
              break
            end
            items << parse_expression
          end
          expect_op(")") unless closed
          if is_tuple
            return Nodes::TupleExprNode.new(items, line)
          end
          first
        when "["
          advance
          items = [] of ExprNode
          loop do
            break if accept_op("]")
            items << parse_expression
            unless accept_op(",")
              expect_op("]")
              break
            end
            break if accept_op("]")
          end
          Nodes::ListExprNode.new(items, line)
        when "{"
          advance
          keys = [] of ExprNode
          values = [] of ExprNode
          loop do
            break if accept_op("}")
            k = parse_expression
            expect_op(":")
            v = parse_expression
            keys << k
            values << v
            unless accept_op(",")
              expect_op("}")
              break
            end
            break if accept_op("}")
          end
          Nodes::DictExprNode.new(keys, values, line)
        else
          raise TemplateError.new("unexpected #{tok.value.inspect}", line)
        end
      else
        raise TemplateError.new("unexpected token #{tok.type}", line)
      end
    end

    private def parse_filter_expr(target : ExprNode? = nil) : ExprNode
      # For {% filter name(args) %} - build a FilterNode around a placeholder
      line = current.line
      name_tok = current
      unless name_tok.type == TokenType::Ident
        raise TemplateError.new("expected filter name", line)
      end
      advance
      args = [] of ExprNode
      kwargs = [] of Tuple(String, ExprNode)
      if accept_op("(")
        args, kwargs = parse_call_args_until_close
      end
      expr = target || Nodes::NameNode.new("__filter_block__", line).as(ExprNode)
      Nodes::FilterNode.new(name_tok.value, args, kwargs, expr, line)
    end

    # --- token stream helpers ---------------------------------------------------

    def current : Token
      tok = @tokens[@pos]?
      raise TemplateError.new("unexpected end of token stream", 0) unless tok
      tok
    end

    private def peek(offset : Int32) : Token
      idx = @pos + offset
      @tokens[idx]? || Token.new(TokenType::Eof, "", 0)
    end

    def advance
      @pos += 1 unless at_eof?
    end

    private def at_eof? : Bool
      @tokens[@pos]?.try(&.type) == TokenType::Eof
    end

    private def expect_op(op : String)
      tok = current
      unless tok.type == TokenType::Op && tok.value == op
        raise TemplateError.new("expected #{op.inspect}, got #{tok.value.inspect}", tok.line)
      end
      advance
    end

    private def accept_op(op : String) : Bool
      tok = current
      if tok.type == TokenType::Op && tok.value == op
        advance
        true
      else
        false
      end
    end

    private def expect_block_end
      tok = current
      unless tok.type == TokenType::BlockEnd || tok.type == TokenType::VarEnd
        raise TemplateError.new("expected end of tag, got #{tok.value.inspect}", tok.line)
      end
      advance
    end

    private def expect_var_end
      tok = current
      unless tok.type == TokenType::VarEnd
        raise TemplateError.new("expected #{"}"}end of expression", tok.line)
      end
      advance
    end

    private def accept_block_end : Bool
      tok = current
      if tok.type == TokenType::BlockEnd
        advance
        true
      else
        false
      end
    end
  end
end
