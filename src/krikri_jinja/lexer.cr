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

  # The reserved words that are tokenized as idents but mean something
  # to the parser.
  KEYWORDS = %w(and or not in is if else true false True False none None
                recursive ignore missing context macro)

  class Lexer
    def self.id_start?(ch : Char) : Bool
      ch.letter? || ch == '_'
    end

    def self.id_cont?(ch : Char) : Bool
      ch.letter? || ch == '_' || ch.number?
    end

    def initialize(source : String, @block_start = "{%", @block_end = "%}",
                   @var_start = "{{", @var_end = "}}", @comment_start = "{#",
                   @comment_end = "#}", @trim_blocks = false, @lstrip_blocks = false)
      @source = source
    end

    def tokens : Array(Token)
      out_tokens = [] of Token
      line = 1
      src = @source
      pos = 0

      while pos < src.size
        var_idx = src.index(@var_start, pos)
        block_idx = src.index(@block_start, pos)
        comment_idx = src.index(@comment_start, pos)
        candidates = [var_idx, block_idx, comment_idx].compact
        next_delim = candidates.min?

        if next_delim.nil?
          text = src[pos..]
          out_tokens << Token.new(TokenType::Text, text, line)
          break
        end

        if next_delim > pos
          text = src[pos...next_delim]
          out_tokens << Token.new(TokenType::Text, text, line)
          line += text.count('\n')
        end

        opening = src[next_delim, 2]
        delim_end = opening == @var_start ? @var_end : (opening == @block_start ? @block_end : @comment_end)
        content_start = next_delim + 2
        close_idx = src.index(delim_end, content_start)
        unless close_idx
          raise TemplateError.new("unclosed #{opening.inspect} tag", line)
        end

        content = src[content_start...close_idx]
        case opening
        when @var_start
          out_tokens << Token.new(TokenType::VarStart, @var_start, line)
          out_tokens.concat tokenize_expression(content, line)
          out_tokens << Token.new(TokenType::VarEnd, @var_end, line)
        when @block_start
          out_tokens << Token.new(TokenType::BlockStart, @block_start, line)
          out_tokens.concat tokenize_expression(content, line)
          out_tokens << Token.new(TokenType::BlockEnd, @block_end, line)
        else
          # comment: drop entirely
        end

        after = close_idx + delim_end.size
        # line count for consumed region (content + delimiters)
        line += src[next_delim...after].count('\n')

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

        if ch == '#'
          # line comment inside expressions ({# handled at template level;
          # '##' style comments inside blocks are not Jinja but be lenient)
          i += 1
          while i < n && src[i] != '\n'
            i += 1
          end
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
