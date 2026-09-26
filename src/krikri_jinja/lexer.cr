require "json"

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

  enum ErrorKind
    Syntax
    Runtime
    Undefined
    Type
    Loader
    Conversion
  end

  class TemplateError < Exception
    property line : Int32
    property column : Int32?
    property kind : ErrorKind
    property operation : String?
    property template_name : String?

    def initialize(message : String, @line : Int32, @column : Int32? = nil,
                   @kind : ErrorKind = ErrorKind::Runtime, @operation : String? = nil,
                   @template_name : String? = nil)
      @raw_message = message
      super("line #{@line}: #{message}")
    end

    def raw_message : String
      @raw_message
    end

    def to_json : String
      JSON.build do |json|
        json.object do
          json.field "kind", @kind.to_s.downcase
          json.field "message", @raw_message
          json.field "line", @line
          if column = @column
            json.field "column", column
          end
          if operation = @operation
            json.field "operation", operation
          end
          if template_name = @template_name
            json.field "template", template_name
          end
        end
      end
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
    # Ansible's inline `{{ }}` templating doubles every backslash before
    # Jinja decodes string literals, so a literal's text survives exactly as
    # written. When set, string literals in `{{ }}` tags keep their escapes
    # verbatim; `{% %}` tag literals still decode.
    property verbatim_expression_strings : Bool

    def initialize(@block_start = "{%", @block_end = "%}",
                   @var_start = "{{", @var_end = "}}",
                   @comment_start = "{#", @comment_end = "#}",
                   @trim_blocks = false, @lstrip_blocks = false,
                   @keep_trailing_newline = false,
                   @verbatim_expression_strings = false)
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
      if src.includes?('\r')
        src = src.gsub("\r\n", "\n").gsub('\r', '\n')
      end
      # keep_trailing_newline: by default one trailing newline is removed,
      # matching the documented environment default.
      if !@options.keep_trailing_newline && src.ends_with?('\n')
        src = src.chomp
      end
      @source = src
    end

    # Byte-level comparison of `src` at byte offset `i` against `delim`.
    private def self.bytes_match?(src : UInt8*, src_size : Int32, i : Int32, delim : UInt8*, delim_size : Int32) : Bool
      return false if i + delim_size > src_size
      j = 0
      while j < delim_size
        return false unless src[i + j] == delim[j]
        j += 1
      end
      true
    end

    # Single forward byte scan for the earliest of the three tag openers.
    # Returns the char index of the opener and which opener matched, or nil
    # when none remains. Replaces three separate String#index scans plus an
    # array allocation per tag.
    def self.find_next_tag(src : String, pos : Int32, opts : LexerOptions) : {Int32, String}?
      vb = opts.var_start
      bb = opts.block_start
      cb = opts.comment_start
      return {pos, vb} if vb.empty?
      return {pos, bb} if bb.empty?
      return {pos, cb} if cb.empty?
      vp = vb.to_unsafe
      bp = bb.to_unsafe
      cp = cb.to_unsafe
      vsize = vb.bytesize
      bsize = bb.bytesize
      csize = cb.bytesize
      p = src.to_unsafe
      src_size = src.bytesize
      i = src.char_index_to_byte_index(pos)
      return nil unless i.is_a?(Int32)
      while i < src_size
        b = p[i]
        if b == vp[0] && bytes_match?(p, src_size, i, vp, vsize)
          return {src.byte_index_to_char_index(i).not_nil!, vb}
        elsif b == bp[0] && bytes_match?(p, src_size, i, bp, bsize)
          return {src.byte_index_to_char_index(i).not_nil!, bb}
        elsif b == cp[0] && bytes_match?(p, src_size, i, cp, csize)
          return {src.byte_index_to_char_index(i).not_nil!, cb}
        end
        i += 1
      end
      nil
    end

    # Finds the tag closer starting at `start`, skipping quoted strings and
    # balancing braces when the closer itself starts with "}".
    # Returns the tag's content end, whether it closed with a `-` strip
    # marker, and whether it closed with a `+` KEEP marker (Jinja2's
    # whitespace-control form that suppresses trim_blocks for that tag).
    def self.scan_tag_end(src : String, start : Int32, delim_end : String) : Tuple(Int32?, Bool, Bool)
      p = src.to_unsafe
      src_size = src.bytesize
      d = delim_end.to_unsafe
      dsize = delim_end.bytesize
      d0 = dsize > 0 ? d[0] : 0u8
      depth = 0
      byte_start = src.char_index_to_byte_index(start)
      return {nil, false, false} unless byte_start.is_a?(Int32)
      i = byte_start
      balance = d0 == '}'.ord
      right_strip = false
      while i < src_size
        c = p[i]
        if c == '\''.ord || c == '"'.ord
          quote = c
          i += 1
          while i < src_size && p[i] != quote
            i += p[i] == '\\'.ord ? 2 : 1
          end
          i += 1
        elsif c == '{'.ord
          depth += 1 if balance
          i += 1
        elsif c == '}'.ord
          if balance && depth > 0
            depth -= 1
            i += 1
          else
            if bytes_match?(p, src_size, i, d, dsize)
              rs = i > byte_start && p[i - 1] == '-'.ord
              rp = !rs && i > byte_start && p[i - 1] == '+'.ord
              char_i = src.byte_index_to_char_index(i).not_nil!
              return {rs ? char_i - 1 : char_i, rs, rp}
            end
            i += 1
          end
        elsif bytes_match?(p, src_size, i, d, dsize)
          rs = i > byte_start && p[i - 1] == '-'.ord
          rp = !rs && i > byte_start && p[i - 1] == '+'.ord
          char_i = src.byte_index_to_char_index(i).not_nil!
          return {rs ? char_i - 1 : char_i, rs, rp}
        else
          i += 1
        end
      end
      {nil, false, false}
    end

    def tokens : Array(Token)
      out_tokens = [] of Token
      line = 1
      src = @source
      pos = 0
      opts = @options
      # Source offset just past the most recently emitted Text token, or nil
      # when the last thing emitted was a tag/comment or whitespace was
      # consumed by trim_blocks/right-strip. A `{%-` may only strip the text
      # token that directly abuts the tag (real Jinja2's lexer matches the
      # text and the tag in one regex, stripping "all whitespace between the
      # text and the tag"); when a previous tag already ate the intervening
      # whitespace, reaching back further would eat unrelated content - e.g.
      # a `{%- endif %}` whose preceding newline was already eaten by
      # trim_blocks after `{% endfor %}` would otherwise strip the loop
      # body's own trailing newline, joining all iterations onto one line.
      prev_text_end : Int32? = nil

      while pos < src.size
        found = Lexer.find_next_tag(src, pos, opts)
        if found.nil?
          text = src[pos..]
          out_tokens << Token.new(TokenType::Text, text, line) unless text.empty?
          break
        end
        next_delim, opening = found

        if next_delim > pos
          text = src[pos...next_delim]
          out_tokens << Token.new(TokenType::Text, text, line)
          prev_text_end = next_delim
          line += text.count('\n')
        end

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
        close_idx, right_strip, plus_right = Lexer.scan_tag_end(src, content_start, delim_end)
        unless close_idx
          raise TemplateError.new("unclosed #{opening.inspect} tag", line)
        end

        text_count_before = out_tokens.size
        content = src[content_start...close_idx]
        # A trailing `+` KEEP marker sits between the tag body and its closer.
        content = content.rchop if plus_right && content.ends_with?('+')
        case opening
        when opts.var_start
          out_tokens << Token.new(TokenType::VarStart, opts.var_start, line)
          out_tokens.concat tokenize_expression(content, line, opts.verbatim_expression_strings)
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
            if left_strip && prev_text_end == next_delim
              if text_count_before > 0 && out_tokens[text_count_before - 1].type == TokenType::Text
                stripped_prev = out_tokens[text_count_before - 1].value.sub(/\s+\Z/, "")
                out_tokens[text_count_before - 1] = Token.new(TokenType::Text, stripped_prev, out_tokens[text_count_before - 1].line)
              end
            elsif opts.lstrip_blocks && !plus_left
              if text_count_before > 0 && out_tokens[text_count_before - 1].type == TokenType::Text
                stripped_prev = out_tokens[text_count_before - 1].value.sub(/[ \t]+\Z/, "")
                out_tokens[text_count_before - 1] = Token.new(TokenType::Text, stripped_prev, out_tokens[text_count_before - 1].line)
                out_tokens.delete_at(text_count_before - 1) if stripped_prev.empty?
              end
            end
            raw_text = raw_text.sub(/\s+\Z/, "") if end_left_strip
            if raw_text.empty?
              prev_text_end = nil
            else
              out_tokens << Token.new(TokenType::Text, raw_text, line)
              prev_text_end = end_idx
            end
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
        if opts.trim_blocks && (opening == opts.block_start || opening == opts.comment_start) && !plus_right
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

        # whitespace control markers. The `{%-` strip only applies when the
        # preceding text token still abuts this tag (see prev_text_end).
        if left_strip && prev_text_end == next_delim
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

        # A tag (or consumed whitespace after one) breaks the adjacency of
        # whatever text token preceded it.
        prev_text_end = nil

        pos = after
      end

      out_tokens << Token.new(TokenType::Eof, "", line)
      out_tokens
    end

    private def tokenize_expression(src : String, base_line : Int32, verbatim_strings : Bool = false) : Array(Token)
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
          i = verbatim_strings ? read_verbatim_string(src, i, toks, line) : read_string(src, i, toks, line)
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
      a = src[i]
      b = src[i + 1]?
      c = src[i + 2]?
      if a == '/' && b == '/' && c == '='
        toks << Token.new(TokenType::Op, "//=", line); i + 3
      elsif a == '*' && b == '*' && c == '='
        toks << Token.new(TokenType::Op, "**=", line); i + 3
      elsif a == '/' && b == '/'
        toks << Token.new(TokenType::Op, "//", line); i + 2
      elsif a == '*' && b == '*'
        toks << Token.new(TokenType::Op, "**", line); i + 2
      elsif a == '=' && b == '='
        toks << Token.new(TokenType::Op, "==", line); i + 2
      elsif a == '!' && b == '='
        toks << Token.new(TokenType::Op, "!=", line); i + 2
      elsif a == '>' && b == '='
        toks << Token.new(TokenType::Op, ">=", line); i + 2
      elsif a == '<' && b == '='
        toks << Token.new(TokenType::Op, "<=", line); i + 2
      elsif a == '+' && b == '='
        toks << Token.new(TokenType::Op, "+=", line); i + 2
      elsif a == '-' && b == '='
        toks << Token.new(TokenType::Op, "-=", line); i + 2
      elsif a == '*' && b == '='
        toks << Token.new(TokenType::Op, "*=", line); i + 2
      elsif a == '/' && b == '='
        toks << Token.new(TokenType::Op, "/=", line); i + 2
      else
        toks << Token.new(TokenType::Op, a.to_s, line)
        i + 1
      end
    end

    # A backslash still pairs with the next character, so an escaped quote
    # does not end the literal, but both characters are kept as written.
    private def read_verbatim_string(src, i, toks, line) : Int32
      quote = src[i]
      i += 1
      buf = String::Builder.new
      while i < src.size
        ch = src[i]
        if ch == '\\' && i + 1 < src.size
          buf << ch << src[i + 1]
          i += 2
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
