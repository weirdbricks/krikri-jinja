require "uri"
require "json"

module KrikriJinja
  # Built-in filters. Each filter receives (value, args, kwargs, ctx) where
  # all values are boxed AnyValue, and returns AnyValue. Signatures follow
  # the Jinja2 Template Designer Documentation's filter list.
  alias FilterFn = Proc(AnyValue, Array(AnyValue), Hash(String, AnyValue), Context, AnyValue)

  BUILTIN_FILTERS = {} of String => FilterFn

  private def self.register_filter(name : String, &block : FilterFn)
    BUILTIN_FILTERS[name] = block
  end

  register_filter("upper") { |v, _a, _k, _c| AnyValue.new(stringify(v).upcase) }
  register_filter("lower") { |v, _a, _k, _c| AnyValue.new(stringify(v).downcase) }
  register_filter("capitalize") do |v, _a, _k, _c|
    s = stringify(v)
    AnyValue.new(s.empty? ? s : s[0].upcase + s[1..].downcase)
  end
  register_filter("title") do |v, _a, _k, _c|
    s = stringify(v).split(/(\s+)/).map do |part|
      part.empty? || part.starts_with?(/\s/) ? part : part[0].upcase + part[1..].downcase
    end
    AnyValue.new(s.join)
  end
  register_filter("trim") do |v, args, _k, _c|
    chars = args[0]?.try(&.raw.as?(String)) || " \t\r\n"
    AnyValue.new(stringify(v).strip(chars))
  end
  register_filter("length") { |v, _a, _k, _c| AnyValue.new(length_of(v)) }
  register_filter("count") { |v, _a, _k, _c| AnyValue.new(length_of(v)) }
  register_filter("string") { |v, _a, _k, _c| AnyValue.new(stringify(v)) }
  register_filter("escape") { |v, _a, _k, _c| AnyValue.new(escape_html(stringify(v))) }
  register_filter("e") { |v, _a, _k, _c| AnyValue.new(escape_html(stringify(v))) }
  register_filter("safe") { |v, _a, _k, _c| v }
  register_filter("int") do |v, args, kwargs, _c|
    default = (kwargs["default"]? || args[0]? || AnyValue.new(0i64)).raw.as?(Int64) || 0i64
    AnyValue.new(to_int(v.raw) || default)
  end
  register_filter("float") do |v, args, kwargs, _c|
    default = (kwargs["default"]? || args[0]? || AnyValue.new(0.0)).raw.as?(Float64) || 0.0
    AnyValue.new(to_float(v.raw) || default)
  end
  register_filter("list") do |v, _a, _k, _c|
    items = case raw = v.raw
            when Array then raw
            when String then raw.chars.map { |c| AnyValue.new(c.to_s) }
            when Hash
              raw.map do |k, x|
                pair = Array(AnyValue).new(2)
                pair << AnyValue.new(k)
                pair << x
                AnyValue.new(pair)
              end
            else
              raise TemplateError.new("cannot convert #{raw.class} to list", 0)
            end
    AnyValue.new(items)
  end
  register_filter("join") do |v, args, kwargs, _c|
    sep = (args[0]?.try(&.raw.as?(String)) || kwargs["d"]?.try(&.raw.as?(String)) || "")
    attr = kwargs["attribute"]?.try(&.raw.as?(String))
    parts = to_iterable(v).map do |item|
      item = get_attr(item, attr) || AnyValue.new(nil) if attr && !item.raw.nil?
      stringify(item)
    end
    AnyValue.new(parts.join(sep))
  end
  register_filter("default") do |v, args, kwargs, _c|
    boolean_default = (kwargs["boolean"]? || AnyValue.new(false)).raw == true || args[1]?.try(&.raw) == true
    if !undefined?(v) && !(boolean_default && !truthy?(v))
      v
    else
      args[0]? || AnyValue.new("")
    end
  end
  register_filter("d") { |v, args, kwargs, c| BUILTIN_FILTERS["default"].call(v, args, kwargs, c) }
  register_filter("first") do |v, _a, _k, _c|
    to_iterable(v).first? || AnyValue.new(nil)
  end
  register_filter("last") do |v, _a, _k, _c|
    to_iterable(v).last? || AnyValue.new(nil)
  end
  register_filter("reverse") do |v, _a, _k, _c|
    case raw = v.raw
    when String then AnyValue.new(raw.reverse)
    else AnyValue.new(to_iterable(v).reverse)
    end
  end
  register_filter("unique") do |v, _a, _k, _c|
    result = [] of AnyValue
    to_iterable(v).each do |item|
      result << item unless result.any? { |x| values_equal(x, item) }
    end
    AnyValue.new(result)
  end
  register_filter("min") do |v, _args, kwargs, _c|
    items = to_iterable(v)
    if items.empty?
      AnyValue.new(nil)
    else
      attr = kwargs["attribute"]?.try(&.raw.as?(String))
      if attr
        items = items.map { |i| get_attr(i, attr) || AnyValue.new(nil) }
      end
      AnyValue.wrap(items.reduce { |a, b| compare_values_safe(a, b) <= 0 ? a : b })
    end
  end
  register_filter("max") do |v, _args, kwargs, _c|
    items = to_iterable(v)
    if items.empty?
      AnyValue.new(nil)
    else
      attr = kwargs["attribute"]?.try(&.raw.as?(String))
      if attr
        items = items.map { |i| get_attr(i, attr) || AnyValue.new(nil) }
      end
      AnyValue.wrap(items.reduce { |a, b| compare_values_safe(a, b) >= 0 ? a : b })
    end
  end
  register_filter("sort") do |v, _args, kwargs, _c|
    attr = kwargs["attribute"]?.try(&.raw.as?(String))
    reverse = (kwargs["reverse"]? || AnyValue.new(false)).raw == true
    items = to_iterable(v)
    begin
      if attr
        items.sort! { |a, b| compare_values(get_attr(a, attr) || AnyValue.new(nil), get_attr(b, attr) || AnyValue.new(nil)) }
      else
        items.sort! { |a, b| compare_values(a, b) }
      end
    rescue TemplateError
      items.sort! { |a, b| stringify(a) <=> stringify(b) }
    end
    items.reverse! if reverse
    AnyValue.new(items)
  end

  # compare that falls back to string comparison for mixed types
  private def self.compare_values_safe(a : AnyValue, b : AnyValue) : Int32
    begin
      compare_values(a, b)
    rescue TemplateError
      stringify(a) <=> stringify(b)
    end
  end

  register_filter("sum") do |v, args, kwargs, _c|
    attr = kwargs["attribute"]?.try(&.raw.as?(String))
    items = to_iterable(v)
    if attr
      items = items.map { |i| get_attr(i, attr) || AnyValue.new(nil) }
    end
    start = (args[0]? || AnyValue.new(0i64)).raw
    AnyValue.new(items.reduce(start) { |acc, item| numeric_add(acc, item.raw) })
  end
  register_filter("abs") do |v, _a, _k, _c|
    case raw = v.raw
    when Int64   then AnyValue.new(raw.abs)
    when Float64 then AnyValue.new(raw.abs)
    else raise TemplateError.new("abs expects a number", 0)
    end
  end
  register_filter("round") do |v, args, kwargs, _c|
    precision = (args[0]?.try(&.raw.as?(Int64)) || kwargs["precision"]?.try(&.raw.as?(Int64)) || 0i64)
    method = kwargs["method"]?.try(&.raw.as?(String)) || args[1]?.try(&.raw.as?(String)) || "common"
    x = v.raw.as?(Float64) || v.raw.as?(Int64).try(&.to_f64) ||
        raise TemplateError.new("round expects a number", 0)
    factor = 10.0 ** precision
    result = case method
             when "ceil" then (x * factor).ceil / factor
             when "floor" then (x * factor).floor / factor
             else (x * factor).round / factor
             end
    AnyValue.new(result)
  end
  register_filter("replace") do |v, args, kwargs, _c|
    s = stringify(v)
    old = (args[0]?.try(&.raw.as?(String)) || kwargs["old"]?.try(&.raw.as?(String)) ||
           raise TemplateError.new("replace requires 'old'", 0))
    new = (args[1]?.try(&.raw.as?(String)) || kwargs["new"]?.try(&.raw.as?(String)) || "")
    count = (args[2]?.try(&.raw.as?(Int64)) || kwargs["count"]?.try(&.raw.as?(Int64)) || Int64::MAX)
    AnyValue.new(replace_limited(s, old, new, count))
  end
  register_filter("truncate") do |v, args, kwargs, _c|
    s = stringify(v)
    length = (args[0]?.try(&.raw.as?(Int64)) || kwargs["length"]?.try(&.raw.as?(Int64)) || 255i64)
    killwords = (kwargs["killwords"]? || AnyValue.new(false)).raw == true || (args[1]?.try(&.raw) == true)
    end_str = kwargs["end"]?.try(&.raw.as?(String)) || args[2]?.try(&.raw.as?(String)) || "..."
    leeway = (kwargs["leeway"]?.try(&.raw.as?(Int64)) || 5i64)
    result = if s.size <= length + leeway
               s
             else
               cut = s[0, length]
               if killwords
                 cut + end_str
               else
                 idx = cut.rindex(' ')
                 (idx ? cut[0, idx] : cut) + end_str
               end
             end
    AnyValue.new(result)
  end
  register_filter("wordcount") do |v, _a, _k, _c|
    AnyValue.new(stringify(v).split(/[ \t\r\n]+/).reject(&.empty?).size.to_i64)
  end
  register_filter("indent") do |v, args, kwargs, _c|
    amount = (args[0]?.try(&.raw.as?(Int64)) || kwargs["width"]?.try(&.raw.as?(Int64)) || 4i64)
    first = (kwargs["first"]? || kwargs["indentfirst"]? || AnyValue.new(false)).raw == true
    prefix = first ? " " * amount : ""
    lines = stringify(v).split('\n')
    lines_out = [prefix + lines[0]]
    lines_out.concat(lines[1..].map { |l| (" " * amount) + l })
    AnyValue.new(lines_out.join(92.chr))
  end
  register_filter("striptags") do |v, _a, _k, _c|
    AnyValue.new(stringify(v).gsub(/<[^>]*>/, "").gsub(/\s+/, " ").strip)
  end
  register_filter("urlencode") do |v, _a, _k, _c|
    case raw = v.raw
    when String then AnyValue.new(URI.encode_www_form(raw.to_s))
    when Hash
      AnyValue.new(raw.map { |k, x| "#{URI.encode_www_form(k.to_s)}=#{URI.encode_www_form(x.to_s.to_s)}" }.join("&"))
    else AnyValue.new(URI.encode_www_form(stringify(v)))
    end
  end
  register_filter("items") do |v, _a, _k, _c|
    raw = v.raw
    unless raw.is_a?(Hash)
      raise TemplateError.new("items expects a mapping", 0)
    end
    AnyValue.new(raw.map do |k, x|
      pair = Array(AnyValue).new(2)
      pair << AnyValue.new(k)
      pair << x
      AnyValue.new(pair)
    end)
  end
  register_filter("map") do |v, args, kwargs, c|
    attr = kwargs["attribute"]?.try(&.raw.as?(String)) || args[0]?.try(&.raw.as?(String))
    result = if attr
               default = kwargs["default"]?
               to_iterable(v).map do |item|
                 found = get_attr(item, attr)
                 found.nil? && default ? default : found || AnyValue.new(nil)
               end
             else
               fname = kwargs["filter"]?.try(&.raw.as?(String))
               raise TemplateError.new("map requires attribute or filter", 0) unless fname
               f = BUILTIN_FILTERS[fname]?
               raise TemplateError.new("unknown filter #{fname.inspect} in map", 0) unless f
               to_iterable(v).map { |item| f.call(item, [] of AnyValue, {} of String => AnyValue, c) }
             end
    AnyValue.new(result)
  end
  register_filter("select") do |v, args, kwargs, c|
    AnyValue.new(test_select(v, args, kwargs, c, keep: true))
  end
  register_filter("reject") do |v, args, kwargs, c|
    AnyValue.new(test_select(v, args, kwargs, c, keep: false))
  end
  register_filter("selectattr") do |v, args, kwargs, c|
    AnyValue.new(attr_select(v, args, kwargs, c, keep: true))
  end
  register_filter("rejectattr") do |v, args, kwargs, c|
    AnyValue.new(attr_select(v, args, kwargs, c, keep: false))
  end
  register_filter("groupby") do |v, args, _k, _c|
    attr = args[0]?.try(&.raw.as?(String)) || raise TemplateError.new("groupby requires an attribute", 0)
    groups = [] of Tuple(AnyValue, Array(AnyValue))
    to_iterable(v).each do |item|
      key = get_attr(item, attr) || AnyValue.new(nil)
      if g = groups.find { |(k, _)| values_equal(k, key) }
        g[1] << item
      else
        groups << {key, [item]}
      end
    end
    grouped = groups.map do |k, items|
      h = {} of String => AnyValue
      h["grouper"] = k
      h["list"] = AnyValue.new(items)
      AnyValue.new(h)
    end
    AnyValue.new(grouped)
  end
  register_filter("batch") do |v, args, _k, _c|
    size = args[0]?.try(&.raw.as?(Int64)) || raise TemplateError.new("batch requires a size", 0)
    fill_with = args[1]?
    items = to_iterable(v)
    out_arr = [] of AnyValue
    items.each_slice(size) do |slice|
      if slice.size < size && fill_with
        slice = slice + Array(AnyValue).new(size - slice.size) { fill_with }
      end
      out_arr << AnyValue.new(slice)
    end
    AnyValue.new(out_arr)
  end
  register_filter("slice") do |v, args, _k, _c|
    count = args[0]?.try(&.raw.as?(Int64)) || raise TemplateError.new("slice requires a count", 0)
    fill_with = args[1]?
    items = to_iterable(v)
    out_arr = [] of AnyValue
    base = items.size // count
    extra = items.size % count
    offset = 0
    count.times do |i|
      n = base + (i < extra ? 1 : 0)
      part = items[offset, n]
      if fill_with
        part = part + Array(AnyValue).new(count - part.size) { fill_with }
      end
      out_arr << AnyValue.new(part)
      offset += n
    end
    AnyValue.new(out_arr)
  end
  register_filter("attr") do |v, args, _k, _c|
    name = args[0]?.try(&.raw.as?(String)) || raise TemplateError.new("attr requires a name", 0)
    get_attr(v, name) || AnyValue.new(nil)
  end
  register_filter("tojson") do |v, _a, kwargs, _c|
    indent = kwargs["indent"]?.try(&.raw.as?(Int64))
    AnyValue.new(to_json_value(v, indent))
  end
  register_filter("format") do |v, args, _k, _c|
    fmt = stringify(v)
    idx = 0
    result = fmt.gsub(/%[sd]/) do |m|
      arg = args[idx]? || AnyValue.new(nil)
      idx += 1
      m == "%s" ? stringify(arg) : arg.raw.as?(Int64).try(&.to_s) || stringify(arg)
    end
    AnyValue.new(result)
  end
  register_filter("xmlattr") do |v, _a, _k, _c|
    raw = v.raw
    raise TemplateError.new("xmlattr is not supported", 0) unless raw.is_a?(Hash)
    AnyValue.new(raw.map { |k, x| "#{k}=\"#{escape_html(x.to_s)}\"" }.join(" "))
  end
  register_filter("wordwrap") do |v, args, _k, _c|
    width = (args[0]?.try(&.raw.as?(Int64)) || 79i64)
    result = stringify(v).split('\n').map do |line|
      words = line.split(' ')
      out_buf = [] of String
      cur = ""
      words.each do |w|
        if cur.empty?
          cur = w
        elsif cur.size + 1 + w.size <= width
          cur += " " + w
        else
          out_buf << cur
          cur = w
        end
      end
      out_buf << cur unless cur.empty?
      out_buf.join('\n')
    end
    AnyValue.new(result.join('\n'))
  end

  private def self.test_select(v, args, kwargs, ctx, keep : Bool) : Array(AnyValue)
    fname = args[0]?.try(&.raw.as?(String)) || kwargs["test"]?.try(&.raw.as?(String)) ||
            raise TemplateError.new("select/reject requires a test name", 0)
    test = BUILTIN_TESTS[fname]?
    raise TemplateError.new("unknown test #{fname.inspect}", 0) unless test
    rest = args[1..]
    to_iterable(v).select do |item|
      result = test.call(item, rest, kwargs, ctx)
      keep ? result : !result
    end
  end

  private def self.attr_select(v, args, kwargs, ctx, keep : Bool) : Array(AnyValue)
    attr = args[0]?.try(&.raw.as?(String)) || raise TemplateError.new("selectattr/rejectattr requires an attribute", 0)
    fname = args[1]?.try(&.raw.as?(String)) || kwargs["test"]?.try(&.raw.as?(String))
    items = to_iterable(v)
    if fname
      test = BUILTIN_TESTS[fname]?
      raise TemplateError.new("unknown test #{fname.inspect}", 0) unless test
      rest = args[2..]
      items.select do |item|
        val = get_attr(item, attr) || AnyValue.new(nil)
        result = test.call(val, rest, kwargs, ctx)
        keep ? result : !result
      end
    else
      items.select do |item|
        val = get_attr(item, attr) || AnyValue.new(nil)
        result = !undefined?(val) && truthy?(val)
        keep ? result : !result
      end
    end
  end

  private def self.replace_limited(s : String, old : String, new : String, count : Int64) : String
    return s.gsub(old, new) if count == Int64::MAX
    pos = 0
    done = 0
    out = IO::Memory.new
    while done < count && (idx = s.index(old, pos))
      out << s[pos...idx] << new
      pos = idx + old.size
      done += 1
    end
    out << s[pos..]
    out.to_s
  end

  def self.length_of(v : AnyValue) : Int64
    case raw = v.raw
    when String then raw.size.to_i64
    when Array  then raw.size.to_i64
    when Hash   then raw.size.to_i64
    else raise TemplateError.new("object of type #{raw.class} has no length", 0)
    end
  end

  def self.to_iterable(v : AnyValue) : Array(AnyValue)
    case raw = v.raw
    when Array then raw
    when String then raw.chars.map { |c| AnyValue.new(c.to_s) }
    when Hash then raw.keys.map { |k| AnyValue.new(k) }
    else raise TemplateError.new("#{raw.class} object is not iterable", 0)
    end
  end

  private def self.to_int(v : AnyV) : Int64?
    case v
    when Int64 then v
    when Float64 then v.to_i64
    when Bool then v ? 1i64 : 0i64
    when String
      s = v.strip
      s.empty? ? nil : (s.to_i64? || s.to_f64?.try(&.to_i64))
    else nil
    end
  end

  private def self.to_float(v : AnyV) : Float64?
    case v
    when Int64 then v.to_f64
    when Float64 then v
    when String
      v.strip.empty? ? nil : v.strip.to_f64?
    else nil
    end
  end

  private def self.numeric_add(a : AnyV, b : AnyV) : AnyV
    if a.is_a?(Int64) && b.is_a?(Int64)
      a + b
    else
      x = a.as?(Float64) || a.as?(Int64).try(&.to_f64) || 0.0
      y = b.as?(Float64) || b.as?(Int64).try(&.to_f64) || 0.0
      x + y
    end
  end

  def self.get_attr(obj : AnyValue, name : String?) : AnyValue?
    return nil unless name
    case raw = obj.raw
    when Hash then raw[name]?
    when LoopObject then raw.to_ctx_hash[name]?
    when Namespace then raw.data[name]?
    when Array, String
      case name
      when "length", "count"
        AnyValue.new(length_of(obj))
      when "upper"
        raw.is_a?(String) ? AnyValue.new(raw.upcase) : nil
      when "lower"
        raw.is_a?(String) ? AnyValue.new(raw.downcase) : nil
      when "title"
        raw.is_a?(String) ? BUILTIN_FILTERS["title"].call(obj, [] of AnyValue, {} of String => AnyValue, Context.new) : nil
      when "reverse"
        raw.is_a?(String) ? AnyValue.new(raw.reverse) : nil
      when "first"
        case raw
        when Array then raw.first?
        when String then raw.empty? ? nil : AnyValue.new(raw[0].to_s)
        else nil
        end
      when "last"
        case raw
        when Array then raw.last?
        when String then raw.empty? ? nil : AnyValue.new(raw[-1].to_s)
        else nil
        end
      when "items"
        if raw.is_a?(Hash)
          AnyValue.new(raw.map do |k, x|
            pair = Array(AnyValue).new(2)
            pair << AnyValue.new(k)
            pair << x
            AnyValue.new(pair)
          end)
        else
          nil
        end
      when "strip"
        raw.is_a?(String) ? AnyValue.new(raw.strip) : nil
      when "keys"
        raw.is_a?(Hash) ? AnyValue.new(raw.keys.map { |k| AnyValue.new(k) }) : nil
      when "values"
        raw.is_a?(Hash) ? AnyValue.new(raw.values) : nil
      else nil
      end
    else nil
    end
  end

  def self.to_json_value(v : AnyValue, indent : Int64? = nil) : String
    String.build do |io|
      json_write(io, v.raw, indent, 0)
    end
  end

  private def self.json_write(io : IO, v : AnyV, indent : Int64?, depth : Int32)
    case v
    when Nil then io << "null"
    when Bool then io << (v ? "true" : "false")
    when Int64 then v.to_s(io)
    when Float64 then format_float(v).to_s(io)
    when String
      v.to_json(io)
    when Array
      io << "["
      if indent && !v.empty?
        v.each_with_index do |item, i|
          io << "," if i > 0
          io << '\n' << (" " * (indent * (depth + 1)))
          json_write(io, item.raw, indent, depth + 1)
        end
        io << '\n' << (" " * (indent * depth))
      else
        v.each_with_index do |item, i|
          io << ", " if i > 0
          json_write(io, item.raw, indent, depth + 1)
        end
      end
      io << "]"
    when Hash
      io << "{"
      if indent && !v.empty?
        v.each_with_index do |(k, x), i|
          io << "," if i > 0
          io << '\n' << (" " * (indent * (depth + 1)))
          k.to_json(io)
          io << ": "
          json_write(io, x.raw, indent, depth + 1)
        end
        io << '\n' << (" " * (indent * depth))
      else
        v.each_with_index do |(k, x), i|
          io << ", " if i > 0
          k.to_json(io)
          io << ": "
          json_write(io, x.raw, indent, depth + 1)
        end
      end
      io << "}"
    else
      stringify(AnyValue.wrap(v)).to_json(io)
    end
  end
end
