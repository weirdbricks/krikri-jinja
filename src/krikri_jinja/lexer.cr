module KrikriJinja
  # Token types for the two-level lexer.
  #
  # Level 1: the raw template is split into text, {{ ... }}, {% ... %} and
  # {# ... #} segments.
  #
  # Level 2: the contents of {{ }} and {% %} are tokenized as expressions
  # using the same token stream type (identifiers, literals, operators).
  enum TokenType
    Text
    VarStart
    VarEnd
    BlockStart
    BlockEnd
    Ident
    Int
    Float
    String
    Op
    Eof
  end

  struct Token
    property type : TokenType
    property value : String
    property line : Int32

    def initialize(@type : TokenType, @value : String, @line : Int32)
    end

    def to_s(io : IO)
      io << "#{@type}(#{value.inspect})@#{line}"
    end
  end

  class TemplateError < Exception
    property line : Int32

    def initialize(message : String, @line : Int32)
      super("line #{@line}: #{message}")
    end
  end

  # Lexer configuration, matching the documented environment options.
  struct LexerOptions
    property block_start : String
    property block_end : String
    property var_start : String
    property var_end : String
    property comment_start : String
    property comment_end : String
    property trim_blocks : Bool
    property lstrip_blocks : Bool
    property keep_trailing_newline : Bool

    def initialize(@block_start = "{%", @block_end = "%}",
                   @var_start = "{{", @var_end = "}}",
                   @comment_start = "{#", @comment_end = "#}",
                   @trim_blocks = false, @lstrip_blocks = false,
                   @keep_trailing_newline = false)
    end
  end

  # The reserved words that are tokenized as idents but mean something
  # to the parser.
  KEYWORDS = %w(and or not in is if else true false True False none None
                recursive ignore missing context macro)

  class Lexer
    @source : String

    def self.id_start?(ch : Char) : Bool
      ch.letter? || ch == '_'
    end

    def self.id_cont?(ch : Char) : Bool
      ch.letter? || ch == '_' || ch.number?
    end

    def initialize(source : String, @options : LexerOptions = LexerOptions.new)
      src : String = source
      # keep_trailing_newline: by default one trailing newline is removed,
      # matching the documented environment default.
      unless @options.keep_trailing_newline
        src = src.sub(/\r?\n\Z/, "")
      end
      @source = src
    end

    def tokens : Array(Token)
      out_tokens = [] of Token
      line = 1
      src = @source
      pos = 0
      opts = @options

      while pos < src.size
        var_idx = src.index(opts.var_start, pos)
        block_idx = src.index(opts.block_start, pos)
        comment_idx = src.index(opts.comment_start, pos)
        candidates = [var_idx, block_idx, comment_idx].compact
        next_delim = candidates.min?

        if next_delim.nil?
          text = src[pos..]
          out_tokens << Token.new(TokenType::Text, text, line) unless text.empty?
          break
        end

        if next_delim > pos
          text = src[pos...next_delim]
          out_tokens << Token.new(TokenType::Text, text, line)
          line += text.count('\n')
        end

        opening = src[next_delim, 2]
        delim_end = case opening
                    when opts.var_start then opts.var_end
                    when opts.block_start then opts.block_end
                    else opts.comment_end
                    end

        content_start = next_delim + 2
        # whitespace control marker directly after the opener: "{%-", "{{-"
        left_strip = src[content_start]? == '-'
        content_start += 1 if left_strip

        # find the closer, tolerating "-}}" / "-%}" (marker glued to closer)
        close_idx = src.index(delim_end, content_start)
        right_strip = false
        if alt_idx = src.index("-" + delim_end, content_start)
          if close_idx.nil? || alt_idx <= close_idx
            # only treat as marker if the "-" belongs to this tag (the closer
            # is not preceded by an expression token boundary confusion) -
            # "-" + closer must be contiguous and not part of e.g. "1 -}} "
            # it always is when contiguous; a plain closer earlier in the
            # tag would win above.
            if close_idx.nil? || alt_idx < close_idx || src[close_idx - 1]? == '-'
              close_idx = alt_idx
              right_strip = true
            end
          end
        end
        unless close_idx
          raise TemplateError.new("unclosed #{opening.inspect} tag", line)
        end

        text_count_before = out_tokens.size
        content = src[content_start...close_idx]
        case opening
        when opts.var_start
          out_tokens << Token.new(TokenType::VarStart, opts.var_start, line)
          out_tokens.concat tokenize_expression(content, line)
          out_tokens << Token.new(TokenType::VarEnd, opts.var_end, line)
        when opts.block_start
          stripped = content.strip
          if stripped.starts_with?("raw") && stripped.gsub(/[-\s]/, "") == "raw"
            # {% raw %} ... {% endraw %}: emit everything up to endraw as text
            end_idx = src.index(opts.block_start, close_idx + delim_end.size)
            unless end_idx
              raise TemplateError.new("unclosed raw block", line)
            end
            end_content = src[end_idx + opts.block_start.size...]
            # find the endraw block's closer (with optional - marker)
            end_content_start = end_idx + opts.block_start.size
            end_left_strip = end_content[0]? == '-'
            if end_left_strip
              end_content_start += 1
            end
            end_inner = src.index(opts.block_end, end_content_start)
            raise TemplateError.new("unclosed raw block", line) unless end_inner
            end_right_strip = end_content_start < end_inner && src[end_inner - 1]? == '-'
            if end_right_strip
              end_inner -= 1
            end
            unless src[end_content_start...end_inner].strip.gsub(/[-\s]/, "") == "endraw"
              # not an endraw tag; keep searching for the next block start
              search_from = end_inner + opts.block_end.size
              found = false
              while idx2 = src.index(opts.block_start, search_from)
                inner2_start = idx2 + opts.block_start.size
                inner2_start += 1 if src[inner2_start]? == '-'
                if inner2_close = src.index(opts.block_end, inner2_start)
                  if src[inner2_start...inner2_close].strip.gsub(/[-\s]/, "") == "endraw"
                    end_idx = idx2
                    end_inner = inner2_close
                    found = true
                    break
                  end
                  search_from = inner2_close + opts.block_end.size
                else
                  break
                end
              end
              raise TemplateError.new("unclosed raw block", line) unless found
            end
            open_text_start = close_idx + delim_end.size + (right_strip ? 1 : 0)
            end_text_start = end_inner + opts.block_end.size + (end_right_strip ? 1 : 0)
            raw_text = src[open_text_start...end_idx]
            if right_strip
              raw_text = raw_text.sub(/\A\s+/, "")
            end
            if left_strip
              if text_count_before > 0 && out_tokens[text_count_before - 1].type == TokenType::Text
                stripped_prev = out_tokens[text_count_before - 1].value.sub(/\s+\Z/, "")
                out_tokens[text_count_before - 1] = Token.new(TokenType::Text, stripped_prev, out_tokens[text_count_before - 1].line)
              end
            end
            raw_text = raw_text.sub(/\s+\Z/, "") if end_left_strip
            out_tokens << Token.new(TokenType::Text, raw_text, line) unless raw_text.empty?
            line += raw_text.count('\n')
            after = end_text_start
            if end_right_strip
              if ws_match = src[after..].match(/\A\s+/)
                after += ws_match[0].size
              end
            end
            line += src[next_delim...after].count('\n')
            pos = after
            next
          end
          out_tokens << Token.new(TokenType::BlockStart, opts.block_start, line)
          out_tokens.concat tokenize_expression(content, line)
          out_tokens << Token.new(TokenType::BlockEnd, opts.block_end, line)
        else
          # comment: drop entirely
        end

        after = right_strip ? close_idx + 1 + delim_end.size : close_idx + delim_end.size
        line += src[next_delim...after].count('\n')

        # trim_blocks: a block tag eats the newline that immediately follows
        # it (var and comment tags do not).
        if opts.trim_blocks && opening == opts.block_start
          if src[after]? == '\n'
            after += 1
            line += 1
          elsif src[after, 2]? == "\r\n"
            after += 2
            line += 1
          end
        end

        # lstrip_blocks: strip spaces/tabs from the end of the text token
        # that precedes a block tag, but only up to the line start.
        if opts.lstrip_blocks && opening == opts.block_start
          idx = text_count_before > 0 ? text_count_before - 1 : nil
          if idx && out_tokens[idx].type == TokenType::Text
            tok = out_tokens[idx]
            stripped_text = tok.value.sub(/[ \t]+\Z/, "")
            if stripped_text != tok.value
              out_tokens[idx] = Token.new(TokenType::Text, stripped_text, tok.line)
              out_tokens.delete_at(idx) if stripped_text.empty?
            end
          end
        end

        # whitespace control markers
        if left_strip
          idx = out_tokens.rindex { |t| t.type == TokenType::Text }
          if idx
            stripped = out_tokens[idx].value.sub(/\s+\Z/, "")
            out_tokens[idx] = Token.new(TokenType::Text, stripped, out_tokens[idx].line)
            out_tokens.delete_at(idx) if stripped.empty?
          end
        end
        if right_strip
          rest = src[after..]
          if ws_match = rest.match(/\A\s+/)
            ws = ws_match[0]
            after += ws.size
            line += ws.count('\n')
          end
        end

        pos = after
      end

      out_tokens << Token.new(TokenType::Eof, "", line)
      out_tokens
    end

    private def tokenize_expression(src : String, base_line : Int32) : Array(Token)
      toks = [] of Token
      i = 0
      line = base_line
      n = src.size

      while i < n
        ch = src[i]

        if ch == '\n'
          line += 1
          i += 1
          next
        end
        if ch.whitespace?
          i += 1
          next
        end

        case ch
        when '(' , ')' , '[' , ']' , '{' , '}' , ',' , ':' , '.' , ';' , '%', '~'
          toks << Token.new(TokenType::Op, ch.to_s, line)
          i += 1
        when '+', '-', '*', '/', '>', '<', '=', '!', '|'
          i = read_operator(src, i, toks, line)
        when '"', '\''
          i = read_string(src, i, toks, line)
        when .number?
          i = read_number(src, i, toks, line)
        when .letter?, '_'
          i = read_ident(src, i, toks, line)
        else
          raise TemplateError.new("unexpected character #{ch.inspect}", line)
        end
      end

      toks
    end

    private def read_operator(src, i, toks, line) : Int32
      three = src[i, 3]
      two = src[i, 2]
      case
      when three == "//="
        toks << Token.new(TokenType::Op, "//=", line); i + 3
      when three == "**="
        toks << Token.new(TokenType::Op, "**=", line); i + 3
      when two == "//"
        toks << Token.new(TokenType::Op, "//", line); i + 2
      when two == "**"
        toks << Token.new(TokenType::Op, "**", line); i + 2
      when two == "=="
        toks << Token.new(TokenType::Op, "==", line); i + 2
      when two == "!="
        toks << Token.new(TokenType::Op, "!=", line); i + 2
      when two == ">="
        toks << Token.new(TokenType::Op, ">=", line); i + 2
      when two == "<="
        toks << Token.new(TokenType::Op, "<=", line); i + 2
      when two == "+="
        toks << Token.new(TokenType::Op, "+=", line); i + 2
      when two == "-="
        toks << Token.new(TokenType::Op, "-=", line); i + 2
      when two == "*="
        toks << Token.new(TokenType::Op, "*=", line); i + 2
      when two == "/="
        toks << Token.new(TokenType::Op, "/=", line); i + 2
      else
        toks << Token.new(TokenType::Op, src[i].to_s, line)
        i + 1
      end
    end

    private def read_string(src, i, toks, line) : Int32
      quote = src[i]
      i += 1
      buf = String::Builder.new
      while i < src.size
        ch = src[i]
        if ch == '\\'
          i += 1
          if i < src.size
            case src[i]
            when 'n' then buf << '\n'
            when 't' then buf << '\t'
            when 'r' then buf << '\r'
            when '\\' then buf << '\\'
            when '"' then buf << '"'
            when '\'' then buf << '\''
            else
              buf << '\\' << src[i]
            end
            i += 1
          else
            buf << '\\'
          end
        elsif ch == quote
          i += 1
          break
        else
          buf << ch
          i += 1
        end
      end
      toks << Token.new(TokenType::String, buf.to_s, line)
      i
    end

    private def read_number(src, i, toks, line) : Int32
      start = i
      # hex/octal/binary integers: 0x / 0o / 0b prefixes
      if src[i] == '0' && i + 1 < src.size && "xXoObB".includes?(src[i + 1])
        kind = src[i + 1].downcase.to_s
        i += 2
        allowed = case kind
                  when "x" then "0123456789abcdefABCDEF"
                  when "o" then "01234567"
                  else          "01"
                  end
        STDERR.puts "DBG kind=#{kind} allowed=#{allowed.inspect}";
        while i < src.size && allowed.includes?(src[i])
          i += 1
        end
        text = src[start...i]
        value = case kind
                when "x" then text[2..].to_i64(16)
                when "o" then text[2..].to_i64(8)
                else          text[2..].to_i64(2)
                end
        toks << Token.new(TokenType::Int, value.to_s, line)
        return i
      end
      while i < src.size && src[i].number?
        i += 1
      end
      if i < src.size && src[i] == '.' && i + 1 < src.size && src[i + 1].number?
        i += 1
        while i < src.size && src[i].number?
          i += 1
        end
        toks << Token.new(TokenType::Float, src[start...i], line)
      else
        toks << Token.new(TokenType::Int, src[start...i], line)
      end
      i
    end

    private def read_ident(src, i, toks, line) : Int32
      start = i
      while i < src.size && Lexer.id_cont?(src[i])
        i += 1
      end
      toks << Token.new(TokenType::Ident, src[start...i], line)
      i
    end
  end
end
