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
      # jinja normalizes \r\n and \r to \n when reading the source.
      src = src.gsub("\r\n", "\n").gsub('\r', '\n')
      # keep_trailing_newline: by default one trailing newline is removed,
      # matching the documented environment default.
      unless @options.keep_trailing_newline
        src = src.sub(/\n\Z/, "")
      end
      @source = src
    end

    # Finds the tag closer starting at `start`, skipping quoted strings and
    # balancing braces when the closer itself starts with "}".
    def self.scan_tag_end(src : String, start : Int32, delim_end : String) : Tuple(Int32?, Bool)
      depth = 0
      i = start
      balance = delim_end[0] == '}'
      right_strip = false
      while i < src.size
        c = src[i]
        if c == '\'' || c == '"'
          quote = c
          i += 1
          while i < src.size && src[i] != quote
            i += src[i] == '\\' ? 2 : 1
          end
          i += 1
        elsif c == '{'
          depth += 1 if balance
          i += 1
        elsif c == '}'
          if balance && depth > 0
            depth -= 1
            i += 1
          else
            if src[i, delim_end.size] == delim_end
              rs = i > start && src[i - 1] == '-'
              return {rs ? i - 1 : i, rs}
            end
            i += 1
          end
        elsif src[i, delim_end.size] == delim_end
          rs = i > start && src[i - 1] == '-'
          return {rs ? i - 1 : i, rs}
        else
          i += 1
        end
      end
      {nil, false}
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
        # and "+{%"-style plus markers that disable whitespace control
        left_strip = false
        plus_left = false
        case src[content_start]?
        when '-' then left_strip = true
        when '+' then plus_left = true
        end
        content_start += 1 if left_strip || plus_left

        # find the closer, skipping string literals and (for "}}" closers)
        # balancing braces so dict literals with "}}" endings work
        close_idx, right_strip = Lexer.scan_tag_end(src, content_start, delim_end)
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
            # find the {% endraw %} block: scan block tags until one whose
            # content (ignoring - markers) is exactly "endraw"
            end_idx = nil
            end_content_start = 0
            end_inner = 0
            end_left_strip = false
            end_right_strip = false
            search_from = close_idx + delim_end.size + (right_strip ? 1 : 0)
            while idx2 = src.index(opts.block_start, search_from)
              c2 = idx2 + opts.block_start.size
              l2 = src[c2]? == '-'
              c2 += 1 if l2
              if i2 = src.index(opts.block_end, c2)
                r2 = c2 < i2 && src[i2 - 1]? == '-'
                i2_eff = r2 ? i2 - 1 : i2
                if src[c2...i2_eff].strip.gsub(/[-\s]/, "") == "endraw"
                  end_idx = idx2
                  end_content_start = c2
                  end_inner = i2_eff
                  end_left_strip = l2
                  end_right_strip = r2
                  break
                end
                search_from = idx2 + opts.block_start.size
              else
                break
              end
            end
            raise TemplateError.new("unclosed raw block", line) unless end_idx
            open_text_start = close_idx + delim_end.size + (right_strip ? 1 : 0)
            end_text_start = end_inner + opts.block_end.size + (end_right_strip ? 1 : 0)
            raw_text = src[open_text_start...end_idx]
            if right_strip
              raw_text = raw_text.sub(/\A\s+/, "")
            end
            if left_strip || (opts.lstrip_blocks && !plus_left)
              if text_count_before > 0 && out_tokens[text_count_before - 1].type == TokenType::Text
                stripped_prev = left_strip ? out_tokens[text_count_before - 1].value.sub(/\s+\Z/, "") : out_tokens[text_count_before - 1].value.sub(/[ \t]+\Z/, "")
                out_tokens[text_count_before - 1] = Token.new(TokenType::Text, stripped_prev, out_tokens[text_count_before - 1].line)
                out_tokens.delete_at(text_count_before - 1) if stripped_prev.empty? && opts.lstrip_blocks && !left_strip
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
            if opts.trim_blocks && src[after]? == '\n' && !end_right_strip
              after += 1
              line += 1
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
        # it (var and comment tags do not; comments included per jinja).
        if opts.trim_blocks && (opening == opts.block_start || opening == opts.comment_start)
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
        if opts.lstrip_blocks && (opening == opts.block_start || opening == opts.comment_start) && !plus_left
          idx = text_count_before > 0 ? text_count_before - 1 : nil
          if idx && out_tokens[idx].type == TokenType::Text
            tok = out_tokens[idx]
            nl = tok.value.rindex('\n')
            tail = nl ? tok.value[(nl + 1)..] : tok.value
            if !tail.empty? && tail.matches?(/^[ \t]+$/)
              stripped_text = nl ? tok.value[0..nl] : ""
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
            when 'u'
              if i + 4 < src.size && (hex = src[(i + 1)..(i + 4)])
                cp = hex.to_i32?(16)
                if cp
                  buf << cp.unsafe_chr
                  i += 4
                else
                  buf << '\\' << 'u'
                end
              else
                buf << '\\' << 'u'
              end
            when 'x'
              if i + 2 < src.size && (hex = src[(i + 1)..(i + 2)])
                cp = hex.to_i32?(16)
                if cp
                  buf << cp.unsafe_chr
                  i += 2
                else
                  buf << '\\' << 'x'
                end
              else
                buf << '\\' << 'x'
              end
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

    private def read_number(src, i, toks, line, hex_mode = false) : Int32
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
      hex_mode = false
      while i < src.size && (src[i].number? || src[i] == '_')
        i += 1
      end
      if i < src.size && (src[i] == 'e' || src[i] == 'E') && !hex_mode
        j = i + 1
        j += 1 if j < src.size && (src[j] == '+' || src[j] == '-')
        if j < src.size && src[j].number?
          while j < src.size && src[j].number?
            j += 1
          end
          toks << Token.new(TokenType::Float, src[start...j], line)
          return j
        end
      end
      if i < src.size && src[i] == '.' && i + 1 < src.size && src[i + 1].number?
        i += 1
        while i < src.size && src[i].number?
          i += 1
        end
        # scientific notation: 1e3, 2.5E-2
        if i < src.size && (src[i] == 'e' || src[i] == 'E')
          j = i + 1
          j += 1 if j < src.size && (src[j] == '+' || src[j] == '-')
          if j < src.size && src[j].number?
            while j < src.size && src[j].number?
              j += 1
            end
            i = j
          end
        end
        toks << Token.new(TokenType::Float, src[start...i], line)
      else
        toks << Token.new(TokenType::Int, src[start...i].delete('_'), line)
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
