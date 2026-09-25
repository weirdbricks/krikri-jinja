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

  register_filter("upper") do |v, _a, _k, _c|
    r = stringify(v).upcase
    v.raw.is_a?(Markup) ? AnyValue.new(Markup.new(r)) : AnyValue.new(r)
  end
  register_filter("lower") do |v, _a, _k, _c|
    r = stringify(v).downcase
    v.raw.is_a?(Markup) ? AnyValue.new(Markup.new(r)) : AnyValue.new(r)
  end
  register_filter("capitalize") do |v, _a, _k, _c|
    s = stringify(v)
    AnyValue.new(s.empty? ? s : s[0].upcase + s[1..].downcase)
  end
  register_filter("title") do |v, _a, _k, _c|
    s = stringify(v).split(/([-\s({\[<]+)/).map do |part|
      part.empty? ? part : part[0].upcase + part[1..].downcase
    end
    AnyValue.new(s.join)
  end
  register_filter("trim") do |v, args, kwargs, _c|
    if (c0 = args[0]?) && !c0.raw.is_a?(String) && !c0.raw.nil?
      raise TemplateError.new("strip arg must be None or str", 0)
    end
    chars = args[0]?.try(&.raw.as?(String)) || kwargs["chars"]?.try(&.raw.as?(String)) || " \t\r\n"
    r = stringify(v).strip(chars)
    v.raw.is_a?(Markup) ? AnyValue.new(Markup.new(r)) : AnyValue.new(r)
  end
  register_filter("length") { |v, _a, _k, _c| AnyValue.new(length_of(v)) }
  register_filter("count") { |v, _a, _k, _c| AnyValue.new(length_of(v)) }
  register_filter("string") { |v, _a, _k, _c| AnyValue.new(stringify(v)) }
  register_filter("escape") do |v, _a, _k, _c|
    case v.raw
    when Markup then v
    else AnyValue.new(Markup.new(escape_html(stringify(v))))
    end
  end
  register_filter("e") do |v, _a, _k, _c|
    case v.raw
    when Markup then v
    else AnyValue.new(Markup.new(escape_html(stringify(v))))
    end
  end
  register_filter("forceescape") { |v, _a, _k, _c| AnyValue.new(Markup.new(escape_html(stringify(v)))) }
  register_filter("safe") do |v, _a, _k, _c|
    case raw = v.raw
    when Markup then v
    else AnyValue.new(Markup.new(stringify(v)))
    end
  end
  register_filter("int") do |v, args, kwargs, _c|
    raise TemplateError.new("'missing' is undefined", 0) if v.raw.is_a?(Undefined)
    raw = v.raw
    if raw.is_a?(BigIntValue)
      v
    elsif raw.is_a?(String) && big_int_string?(raw)
      AnyValue.new(BigIntValue.parse(raw))
    else
      default = (kwargs["default"]? || args[0]? || AnyValue.new(0i64)).raw.as?(Int64) || 0i64
      base = (kwargs["base"]? || AnyValue.new(10i64)).raw.as?(Int64) || 10i64
      AnyValue.new(to_int(raw, base) || default)
    end
  end
  register_filter("float") do |v, args, kwargs, _c|
    raise TemplateError.new("'missing' is undefined", 0) if v.raw.is_a?(Undefined)
    default = (kwargs["default"]? || args[0]? || AnyValue.new(0.0)).raw.as?(Float64) || 0.0
    AnyValue.new(to_float(v.raw) || default)
  end
  register_filter("list") do |v, _a, _k, _c|
    items = case raw = v.raw
            when Array then raw
            when GeneratorValue then raw.materialize
            when TupleValue then raw.items
            when Undefined then [] of AnyValue
            when String then raw.chars.map { |c| AnyValue.new(c.to_s) }
            when BigIntValue then raise TemplateError.new("'int' object is not iterable", 0)
            when Hash then raw.keys.map { |k| AnyValue.new(k) }
            else
              raise TemplateError.new("cannot convert #{raw.class} to list", 0)
            end
    AnyValue.new(items)
  end
  register_filter("join") do |v, args, kwargs, _c|
    sep = (args[0]?.try(&.raw) || kwargs["d"]?.try(&.raw)).try { |r| stringify(AnyValue.new(r)) } || ""
    attr = kwargs["attribute"]?.try(&.raw.as?(String))
    parts = to_iterable(v).map do |item|
      item = get_attr(item, attr) || AnyValue.new(Undefined.new) if attr && !item.raw.nil?
      stringify(item)
    end
    AnyValue.new(parts.join(sep))
  end
  register_filter("default") do |v, args, kwargs, _c|
    boolean_default = (kwargs["boolean"]? || AnyValue.new(false)).raw == true || args[1]?.try(&.raw) == true
    if !v.raw.is_a?(Undefined) && !(boolean_default && !truthy?(v))
      v
    else
      args[0]? || AnyValue.new("")
    end
  end
  register_filter("d") { |v, args, kwargs, c| BUILTIN_FILTERS["default"].call(v, args, kwargs, c) }
  register_filter("first") do |v, _a, _k, _c|
    to_iterable(v).first? || AnyValue.new(Undefined.new)
  end
  register_filter("last") do |v, _a, _k, _c|
    raise TemplateError.new("'generator' object is not reversible", 0) if v.raw.is_a?(GeneratorValue)
    to_iterable(v).last? || AnyValue.new(Undefined.new)
  end
  register_filter("reverse") do |v, _a, _k, _c|
    case raw = v.raw
    when String then AnyValue.new(raw.reverse)
    when Undefined then AnyValue.new(GeneratorValue.new([] of AnyValue))
    else
      AnyValue.new(GeneratorValue.new(to_iterable(v).reverse))
    end
  end
  register_filter("unique") do |v, _a, kwargs, _c|
    attr = kwargs["attribute"]?.try(&.raw.as?(String))
    case_sensitive = (kwargs["case_sensitive"]? || AnyValue.new(false)).raw == true
    result = [] of AnyValue
    keys = [] of AnyValue
    src = begin
      to_iterable(v)
    rescue
      next AnyValue.new(GeneratorValue.new([] of AnyValue, "object is not iterable"))
    end
    src.each do |item|
      key = attr ? (get_attr(item, attr) || AnyValue.new(nil)) : item
      key = AnyValue.new(stringify(key).downcase) if !case_sensitive && key.raw.is_a?(String)
      unless keys.any? { |x| values_equal(x, key) }
        keys << key
        result << item
      end
    end
    AnyValue.new(GeneratorValue.new(result))
  end
  register_filter("min") do |v, _args, kwargs, _c|
    items = to_iterable(v)
    if items.empty?
      AnyValue.new(Undefined.new)
    else
      attr = kwargs["attribute"]?.try(&.raw.as?(String))
      case_sensitive = (kwargs["case_sensitive"]? || AnyValue.new(false)).raw == true
      best = items.reduce do |a, b|
        ka = sort_key(attr ? (get_attr(a, attr) || AnyValue.new(nil)) : a, case_sensitive)
        kb = sort_key(attr ? (get_attr(b, attr) || AnyValue.new(nil)) : b, case_sensitive)
        compare_values(ka, kb) <= 0 ? a : b
      end
      AnyValue.wrap(best)
    end
  end
  register_filter("max") do |v, _args, kwargs, _c|
    items = to_iterable(v)
    if items.empty?
      AnyValue.new(Undefined.new)
    else
      attr = kwargs["attribute"]?.try(&.raw.as?(String))
      case_sensitive = (kwargs["case_sensitive"]? || AnyValue.new(false)).raw == true
      best = items.reduce do |a, b|
        ka = sort_key(attr ? (get_attr(a, attr) || AnyValue.new(nil)) : a, case_sensitive)
        kb = sort_key(attr ? (get_attr(b, attr) || AnyValue.new(nil)) : b, case_sensitive)
        compare_values(ka, kb) >= 0 ? a : b
      end
      AnyValue.wrap(best)
    end
  end

  # Sort key applying case-insensitive lowering for strings (jinja's filters
  # default to case_sensitive=False).
  private def self.sort_key(v : AnyValue, case_sensitive : Bool) : AnyValue
    if !case_sensitive && v.raw.is_a?(String)
      AnyValue.new(v.raw.as(String).downcase)
    else
      v
    end
  end

  private def self.stable_sort(items : Array(AnyValue), &cmp : (AnyValue, AnyValue -> Int32)) : Array(AnyValue)
    decorated = items.map_with_index { |item, i| {item, i} }
    decorated.sort! do |a, b|
      c = cmp.call(a[0], b[0])
      c == 0 ? a[1] <=> b[1] : c
    end
    decorated.map(&.[0])
  end
  register_filter("sort") do |v, _args, kwargs, _c|
    attr = kwargs["attribute"]?.try(&.raw.as?(String))
    reverse = (kwargs["reverse"]? || AnyValue.new(false)).raw == true
    case_sensitive = (kwargs["case_sensitive"]? || AnyValue.new(false)).raw == true
    items = to_iterable(v)
    sorted = stable_sort(items) do |a, b|
      ka = sort_key(attr ? (get_attr(a, attr) || AnyValue.new(nil)) : a, case_sensitive)
      kb = sort_key(attr ? (get_attr(b, attr) || AnyValue.new(nil)) : b, case_sensitive)
      compare_values(ka, kb)
    end
    sorted.reverse! if reverse
    AnyValue.new(sorted)
  end



  register_filter("sum") do |v, args, kwargs, _c|
    attr = kwargs["attribute"]?.try(&.raw.as?(String))
    items = to_iterable(v)
    if attr
      items = items.map { |i| get_attr(i, attr) || AnyValue.new(nil) }
    end
    start = (kwargs["start"]? || args[0]? || AnyValue.new(0i64)).raw
    AnyValue.new(items.reduce(start) { |acc, item| numeric_add(acc, item.raw) })
  end
  register_filter("abs") do |v, _a, _k, _c|
    case raw = v.raw
    when Int64   then AnyValue.new(raw.abs)
    when BigIntValue then AnyValue.new(raw.absolute)
    when Float64 then AnyValue.new(raw.abs)
    when true    then AnyValue.new(1i64)
    when false   then AnyValue.new(0i64)
    else raise TemplateError.new("abs expects a number", 0)
    end
  end
  register_filter("round") do |v, args, kwargs, _c|
    p_raw = args[0]?.try(&.raw) || kwargs["precision"]?.try(&.raw)
    precision = if p_raw.nil?
                  0i64
                else
                    (p_raw.as?(Int64) || (p_raw.as?(Bool).try { |b| b ? 1i64 : 0i64 }) ||
                     (p_raw.as?(BigIntValue).try { |n| n.negative? ? -20i64 : 20i64 }) ||
                     (s = p_raw.as?(String); s && big_int_string?(s) ? (s.starts_with?('-') ? -20i64 : 20i64) : nil) ||
                    raise(TemplateError.new("round() cannot interpret the precision", 0))).to_i64
                end
    if iv = v.raw.as?(Int64) || v.raw.as?(BigIntValue)
      # python round(int, n) returns an int; n >= 0 leaves it unchanged
      if precision >= 0
        AnyValue.new(iv)
      elsif iv.is_a?(Int64)
        factor = 10.0 ** (-precision)
        AnyValue.new((sprintf("%.0f", iv / factor).to_f64 * factor).to_i64)
      else
        AnyValue.new(iv)
      end
    elsif v.raw.is_a?(Bool)
      AnyValue.new(v.raw.as(Bool) ? 1i64 : 0i64)
    else
      method = kwargs["method"]?.try(&.raw.as?(String)) || args[1]?.try(&.raw.as?(String)) || "common"
      x = v.raw.as?(Float64) || raise TemplateError.new("round expects a number", 0)
      result = case method
               when "ceil" then (x * 10.0 ** precision).ceil / 10.0 ** precision
               when "floor" then (x * 10.0 ** precision).floor / 10.0 ** precision
               else
                 if precision >= 0
                   sprintf("%.*f", precision, x).to_f64
                 else
                   factor = 10.0 ** (-precision)
                   (sprintf("%.0f", x / factor).to_f64 * factor)
                 end
               end
      AnyValue.new(result)
    end
  end
  register_filter("replace") do |v, args, kwargs, _c|
    s = stringify(v)
    old_raw = if old_arg = args[0]?
               old_arg.raw
             elsif old_kwarg = kwargs["old"]?
               old_kwarg.raw
             else
               raise TemplateError.new("replace requires 'old'", 0)
             end
    new_raw = if new_arg = args[1]?
               new_arg.raw
             elsif new_kwarg = kwargs["new"]?
               new_kwarg.raw
             end
    old = stringify(AnyValue.new(old_raw))
    new = new_raw.nil? ? "" : stringify(AnyValue.new(new_raw))
    count = (args[2]?.try(&.raw.as?(Int64)) || kwargs["count"]?.try(&.raw.as?(Int64)) || Int64::MAX)
    AnyValue.new(replace_limited(s, old, new, count))
  end
  register_filter("truncate") do |v, args, kwargs, _c|
    length_raw = if a0 = args[0]?
                   a0.raw
                 elsif kl = kwargs["length"]?
                   kl.raw
                 else
                   255i64
                 end
    end_raw = if a2 = args[2]?
                a2.raw
              elsif ke = kwargs["end"]?
                ke.raw
              else
                nil
              end
    end_str = end_raw.as?(String) || "..."
    end_len = case r = end_raw
              when nil    then 3i64
              when String then r.size.to_i64
              when Array  then r.size.to_i64
              when Hash   then r.size.to_i64
              when TupleValue then r.items.size.to_i64
              else raise TemplateError.new("object of type '#{r}' has no len()", 0)
              end
    leeway = (args[3]?.try(&.raw.as?(Int64)) || kwargs["leeway"]?.try(&.raw.as?(Int64)) || 5i64)
    case length_raw
    when Int64
      raise TemplateError.new("expected length >= #{end_len}, got #{length_raw}", 0) if length_raw < end_len
    when Float64
      raise TemplateError.new("expected length >= #{end_len}, got #{format_float(length_raw)}", 0) if length_raw < end_len
    else
      raise TemplateError.new("'>=' not supported between instances of 'int' and 'X'", 0)
    end
    if v.raw.is_a?(Undefined)
      next AnyValue.new("")
    end
    body = case r = v.raw
           when String then r
           when Markup then r.value
           else nil
           end
    vlen = if body
             body.size.to_i64
           else
             case r = v.raw
             when Array then r.size.to_i64
             when Hash then r.size.to_i64
             when TupleValue then r.items.size.to_i64
             else raise TemplateError.new("object of type '#{r}' has no len()", 0)
             end
           end
    s = body || stringify(v)
    killwords = truthy?(args[1]? || AnyValue.new(false)) || truthy?(kwargs["killwords"]? || AnyValue.new(false))
    result = if vlen <= length_raw.as(Int64 | Float64).to_i64 + leeway
               v.raw.is_a?(Markup) || body.nil? ? v.raw : s
             else
               li = length_raw.as?(Int64) || raise TemplateError.new("slice indices must be integers", 0)
               cut = s[0, (li - end_str.size).clamp(0, s.size)]
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
    AnyValue.new(stringify(v).scan(/[\p{L}\p{N}_]+/).size.to_i64)
  end
  register_filter("indent") do |v, args, kwargs, _c|
    raise TemplateError.new("unsupported operand type(s) for +=: 'int' and 'str'", 0) unless v.raw.is_a?(String) || v.raw.is_a?(Markup)
    amount = (args[0]?.try(&.raw.as?(Int64)) || kwargs["width"]?.try(&.raw.as?(Int64)))
    if args[0]? && amount.nil?
      raise TemplateError.new("can't multiply sequence by non-int of type '#{args[0].raw.class}'", 0) unless args[0].raw.is_a?(String)
      next v if v.raw.is_a?(Markup)
      next AnyValue.new(stringify(v))
    end
    amount ||= 4i64
    first = (kwargs["first"]? || kwargs["indentfirst"]? || AnyValue.new(false)).raw == true || args[1]?.try(&.raw) == true
    blank = (kwargs["blank"]? || args[2]? || AnyValue.new(false)).raw == true
    if amount <= 0
      AnyValue.new(stringify(v))
    else
      prefix = first ? " " * amount : ""
      lines = stringify(v).split('\n')
      lines_out = [prefix + lines[0]]
      lines_out.concat(lines[1..].map { |l| (!blank && l.empty?) ? l : (" " * amount) + l })
      AnyValue.new(lines_out.join('\n'))
    end
  end
  register_filter("striptags") do |v, _a, _k, _c|
    s = stringify(v).gsub(/<[^>]*>/, "").gsub(/\s+/, " ").strip
    s = s.gsub(/&#(\d+);/) { $1.to_i.chr.to_s }
         .gsub(/&#x([0-9a-fA-F]+);/) { $1.to_i(16).chr.to_s }
         .gsub("&lt;", "<").gsub("&gt;", ">").gsub("&quot;", "\"")
         .gsub("&#39;", "'").gsub("&nbsp;", " ").gsub("&amp;", "&")
    AnyValue.new(s)
  end
  register_filter("urlencode") do |v, _a, kwargs, _c|
    raise TemplateError.new("do_urlencode() got an unexpected keyword argument '#{kwargs.first_key}'", 0) unless kwargs.empty?
    case raw = v.raw
    when String then AnyValue.new(KrikriJinja.percent_encode(raw, "/"))
    when Hash
      AnyValue.new(raw.map { |k, x| "#{KrikriJinja.quote_plus(k.to_s)}=#{KrikriJinja.quote_plus(KrikriJinja.stringify(x))}" }.join("&"))
    when Array
      parts = raw.map do |item|
        pair = item.raw.as?(Array) || item.raw.as?(TupleValue).try(&.items) ||
               raise TemplateError.new("too many values to unpack", 0)
        raise TemplateError.new("too many values to unpack", 0) unless pair.size == 2
        "#{KrikriJinja.quote_plus(KrikriJinja.stringify(pair[0]))}=#{KrikriJinja.quote_plus(KrikriJinja.stringify(pair[1]))}"
      end
      AnyValue.new(parts.join("&"))
    when TupleValue
      raise TemplateError.new("too many values to unpack", 0) unless raw.items.size == 2
      AnyValue.new("#{KrikriJinja.quote_plus(KrikriJinja.stringify(raw.items[0]))}=#{KrikriJinja.quote_plus(KrikriJinja.stringify(raw.items[1]))}")
    else AnyValue.new(KrikriJinja.percent_encode(stringify(v)))
    end
  end
  register_filter("items") do |v, _a, _k, _c|
    raw = v.raw
    unless raw.is_a?(Hash)
      raise TemplateError.new("items expects a mapping", 0)
    end
    AnyValue.new(raw.map { |k, x| AnyValue.new(TupleValue.new([AnyValue.new(k), x])) })
  end
  register_filter("map") do |v, args, kwargs, c|
    attr = kwargs["attribute"]?
    attr_s = attr ? (attr.raw.is_a?(String) ? attr.raw.as(String) : stringify(attr)) : nil
    result = if attr_s
               default = kwargs["default"]? || AnyValue.new(nil)
               has_default = !default.raw.is_a?(Nil) && !default.raw.is_a?(Undefined)
               to_iterable(v).map do |item|
                 found = get_attr(item, attr_s)
                 if found.nil? || found.raw.is_a?(Undefined)
                   has_default ? default : AnyValue.new(Undefined.new)
                 else
                   found
                 end
               end
             elsif tname = kwargs["test"]?.try(&.raw.as?(String))
               t = BUILTIN_TESTS[tname]?
               raise TemplateError.new("unknown test #{tname.inspect} in map", 0) unless t
               extra = args[0..]
               to_iterable(v).select { |item| t.call(item, extra, kwargs, c) }
             else
               fname = kwargs["filter"]?.try(&.raw.as?(String)) || args[0]?.try(&.raw.as?(String))
               raise TemplateError.new("map requires attribute or filter", 0) unless fname
               f = BUILTIN_FILTERS[fname]?
               raise TemplateError.new("unknown filter #{fname.inspect} in map", 0) unless f
               inner_kwargs = kwargs.reject("attribute", "default", "test", "filter")
               if !inner_kwargs.empty? && !KWARG_FILTERS.includes?(fname)
                 raise TemplateError.new("#{fname}() got an unexpected keyword argument", 0)
               end
               max_args = MAX_POSITIONAL[fname]?
               if max_args && args[1..].size > max_args
                 raise TemplateError.new("#{fname}() takes at most #{max_args} positional argument(s)", 0)
               end
               to_iterable(v).map { |item| f.call(item, args[1..], inner_kwargs, c) }
             end
    AnyValue.new(GeneratorValue.new(result))
  end
  register_filter("select") do |v, args, kwargs, c|
    AnyValue.new(GeneratorValue.new(test_select(v, args, kwargs, c, keep: true)))
  end
  register_filter("reject") do |v, args, kwargs, c|
    AnyValue.new(GeneratorValue.new(test_select(v, args, kwargs, c, keep: false)))
  end
  register_filter("selectattr") do |v, args, kwargs, c|
    AnyValue.new(GeneratorValue.new(attr_select(v, args, kwargs, c, keep: true)))
  end
  register_filter("rejectattr") do |v, args, kwargs, c|
    AnyValue.new(GeneratorValue.new(attr_select(v, args, kwargs, c, keep: false)))
  end
  register_filter("groupby") do |v, args, kwargs, _c|
    attr = args[0]?.try(&.raw.as?(String)) || raise TemplateError.new("groupby requires an attribute", 0)
    case_sensitive = (kwargs["case_sensitive"]? || AnyValue.new(false)).raw == true
    groups = [] of Tuple(AnyValue, String, Array(AnyValue))
    sorted_items = stable_sort(to_iterable(v)) do |a, b|
      compare_values(get_attr(a, attr) || kwargs["default"]? || AnyValue.new(Undefined.new),
                     get_attr(b, attr) || kwargs["default"]? || AnyValue.new(Undefined.new))
    end
    sorted_items.each do |item|
      key = get_attr(item, attr) || kwargs["default"]? || AnyValue.new(Undefined.new)
      gkey = !case_sensitive && key.raw.is_a?(String) ? key.raw.as(String).downcase : stringify(key)
      if g = groups.find { |(_, ck, _)| ck == gkey }
        g[2] << item
      else
        groups << {key, gkey, [item]}
      end
    end
    grouped = groups.map do |k, _ck, items|
      h = {} of String => AnyValue
      h["grouper"] = k
      h["list"] = AnyValue.new(items)
      AnyValue.new(h)
    end
    sorted_groups = stable_sort(grouped) do |a, b|
      ka = a.raw.as(Hash)["grouper"]
      kb = b.raw.as(Hash)["grouper"]
      compare_values(ka, kb)
    end
    AnyValue.new(sorted_groups)
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
    fill_with ? AnyValue.new(out_arr) : AnyValue.new(GeneratorValue.new(out_arr))
  end
  register_filter("slice") do |v, args, _k, _c|
    a0 = args[0]? || raise TemplateError.new("slice requires a count", 0)
    count = a0.raw.as?(Int64)
    # python defers count problems until the generator is consumed
    unless count
      begin
        count = length_of(a0)
      rescue
        fill_with = args[1]?
        next fill_with ? AnyValue.new([] of AnyValue) : AnyValue.new(GeneratorValue.new([] of AnyValue, "slice: count must be an integer"))
      end
    end
    if count <= 0
      next AnyValue.new(GeneratorValue.new([] of AnyValue, "integer division or modulo by zero"))
    end
    fill_with = args[1]?
    begin
      items = to_iterable(v)
    rescue
      next AnyValue.new(GeneratorValue.new([] of AnyValue, "object of type '#{v.raw.class}' is not iterable"))
    end
    if count > 4_000_000 && count > items.size
      # python would lazily emit trillions of empty slices; fail on touch
      next AnyValue.new(GeneratorValue.new([] of AnyValue, "slice count too large"))
    end
    out_arr = [] of AnyValue
    base = items.size // count
    extra = items.size % count
    offset = 0
    first_len = base + (extra > 0 ? 1 : 0)
    count.times do |i|
      n = base + (i < extra ? 1 : 0)
      part = offset < items.size ? items[offset, Math.min(n, items.size - offset)] : [] of AnyValue
      if fill_with && part.size < first_len
        part = part + Array(AnyValue).new(first_len - part.size) { fill_with }
      end
      out_arr << AnyValue.new(part)
      offset += n
    end
    AnyValue.new(GeneratorValue.new(out_arr))
  end
  register_filter("attr") do |v, args, _k, _c|
    name = args[0]?.try(&.raw.as?(String)) || raise TemplateError.new("attr requires a name", 0)
    if v.raw.is_a?(Hash) || v.raw.is_a?(Undefined)
      AnyValue.new(Undefined.new)
    else
      get_attr(v, name) || AnyValue.new(Undefined.new)
    end
  end
  register_filter("tojson") do |v, _a, kwargs, _c|
    indent = kwargs["indent"]?.try(&.raw.as?(Int64))
    AnyValue.new(to_json_value(v, indent))
  end
  register_filter("format") do |v, args, _k, _c|
    AnyValue.new(KrikriJinja.py_format(stringify(v), args))
  end
  register_filter("xmlattr") do |v, _a, _k, _c|
    raw = v.raw
    raise TemplateError.new("xmlattr is not supported", 0) unless raw.is_a?(Hash)
    AnyValue.new(raw.map { |k, x| "#{k}=\"#{escape_html(x.to_s)}\"" }.join(" "))
  end
  register_filter("wordwrap") do |v, args, kwargs, _c|
    width = (args[0]?.try(&.raw.as?(Int64)) || kwargs["width"]?.try(&.raw.as?(Int64)) || 79i64)
    break_long = (kwargs["break_long_words"]? || args[1]? || AnyValue.new(true)).raw != false
    wrapstring = kwargs["wrapstring"]?.try(&.raw.as?(String)) || args[2]?.try(&.raw.as?(String)) || "\n"
    raise TemplateError.new("invalid width #{width} (must be > 0)", 0) unless width > 0
    result = stringify(v).split('\n').map do |line|
      words = line.split(' ')
      out_buf = [] of String
      cur = ""
      words.each do |w|
        if cur.empty?
          if !break_long
            cur = w
          elsif break_long && w.size > width
            # break the long word into width-sized chunks
            while w.size > width
              out_buf << w[0, width]
              w = w[width..]
            end
            cur = w
          else
            cur = w
          end
        elsif cur.size + 1 + w.size <= width
          cur += " " + w
        elsif !break_long
          out_buf << cur unless cur.empty?
          cur = w
        elsif break_long && w.size > width
          space_left = width - cur.size - 1
          if space_left > 0
            cur += " " + w[0, space_left]
            out_buf << cur
            w = w[space_left..]
          else
            out_buf << cur
          end
          while w.size > width
            out_buf << w[0, width]
            w = w[width..]
          end
          cur = w
        else
          out_buf << cur
          cur = w
        end
      end
      out_buf << cur unless cur.empty?
      out_buf.join(wrapstring)
    end
    AnyValue.new(result.join(wrapstring))
  end

  register_filter("dictsort") do |v, args, kwargs, _c|
    raw = v.raw
    raise TemplateError.new("dictsort expects a mapping", 0) unless raw.is_a?(Hash)
    by = kwargs["by"]?.try(&.raw.as?(String)) || "key"
    reverse = (kwargs["reverse"]? || AnyValue.new(false)).raw == true
    case_sensitive = (kwargs["case_sensitive"]? || AnyValue.new(false)).raw == true
    entries = raw.map { |k, x| AnyValue.new(TupleValue.new([AnyValue.new(k), x])) }
    entries.sort! do |a, b|
      ka = a.raw.as(TupleValue).items[0]
      kb = b.raw.as(TupleValue).items[0]
      if by == "value"
        ka = a.raw.as(TupleValue).items[1]
        kb = b.raw.as(TupleValue).items[1]
      end
      ka = sort_key(ka, case_sensitive) unless ka.raw.is_a?(Int64) || ka.raw.is_a?(Float64)
      kb = sort_key(kb, case_sensitive) unless kb.raw.is_a?(Int64) || kb.raw.is_a?(Float64)
      cmp = begin
        compare_values(ka, kb)
      rescue TemplateError
        (case_sensitive ? stringify(ka) : stringify(ka).downcase) <=>
          (case_sensitive ? stringify(kb) : stringify(kb).downcase)
      end
      reverse ? -(cmp) : cmp
    end
    AnyValue.new(entries)
  end
  register_filter("filesizeformat") do |v, args, kwargs, _c|
    binary = (kwargs["binary"]? || args[0]? || AnyValue.new(false)).raw == true
    bytes = v.raw.as?(Int64) || v.raw.as?(Float64).try(&.to_i64) ||
            (v.raw.is_a?(Bool) ? (v.raw.as(Bool) ? 1i64 : 0i64) : nil) ||
            v.raw.as?(BigIntValue) ||
            (s = v.raw.as?(String); s && big_int_string?(s) ? s : nil) ||
            raise TemplateError.new("filesizeformat expects a number", 0)
    base = binary ? 1024i64 : 1000i64
    prefixes = binary ? ["KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"]
                      : ["kB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]
    AnyValue.new(KrikriJinja.filesizeformat(bytes, base, prefixes, binary))
  end
  register_filter("format") do |v, args, _k, _c|
    AnyValue.new(KrikriJinja.py_format(stringify(v), args))
  end
  register_filter("center") do |v, args, kwargs, _c|
    raise TemplateError.new("center() takes at most 1 positional argument(s)", 0) if args.size > 1
    width_raw = args[0]?.try(&.raw) || kwargs["width"]?.try(&.raw) || 80i64
    width = width_raw.as?(Int64) || (width_raw.as?(Bool).try { |b| b ? 1i64 : 0i64 }) ||
            raise TemplateError.new("object cannot be interpreted as an integer", 0)
    s = stringify(v)
    pad = width - s.size
    result = if pad <= 0
               s
             else
               # python str.center: left = pad // 2 + (pad & width & 1)
               left = pad // 2 + ((pad & width) & 1)
               (" " * left) + s + (" " * (pad - left))
             end
    AnyValue.new(result)
  end
  register_filter("pprint") { |v, _a, _k, _c| AnyValue.new(stringify(v)) }
  register_filter("urlize") do |v, args, kwargs, _c|
    text = stringify(v)
    email_re = /^[\w.+-]+@[\w-]+(?:\.[\w-]+)+$/
    pieces = text.split(/(\s+)/)
    rendered = pieces.map do |word|
      if word.match(/^\s*$/) || word.empty?
        word
      else
        token = word
        trail = ""
        while !token.empty? && ".,;:!?)]}'\"".includes?(token[-1])
          trail = "#{token[-1]}#{trail}"
          token = token[0...-1]
        end
        href : String? = nil
        if token.starts_with?("http://") || token.starts_with?("https://")
          href = token
        elsif token.downcase.starts_with?("http://") || token.downcase.starts_with?("https://")
          href = "https://#{token}"
        elsif token.starts_with?("www.")
          href = "https://#{token}"
        end
        if href
          %(<a href="#{KrikriJinja.escape_html(href.not_nil!)}" rel="noopener">#{KrikriJinja.escape_html(token)}</a>#{KrikriJinja.escape_html(trail)})
        elsif email_re.matches?(token)
          %(<a href="mailto:#{KrikriJinja.escape_html(token)}">#{KrikriJinja.escape_html(token)}</a>#{KrikriJinja.escape_html(trail)})
        else
          KrikriJinja.escape_html(word)
        end
      end
    end.join
    AnyValue.new(Markup.new(rendered))
  end

  register_filter("random") do |v, _a, _k, _c|
    items = to_iterable(v)
    items.empty? ? AnyValue.new(Undefined.new) : items[Random.new.rand(items.size)]
  end

  # Filters that accept keyword arguments in real Jinja2; map/filter passing
  # must raise for any others (Python raises TypeError instead).
  KWARG_FILTERS = %w(default dictsort filesizeformat float indent int join map
                     max min reject rejectattr replace round select selectattr
                     slice sort sum tojson trim truncate unique urlencode
                     wordwrap groupby batch urlize wordcount format)

  # Strict positional arity for filters python raises on when over-called.
  MAX_POSITIONAL = {"center" => 1, "trim" => 1, "indent" => 2, "round" => 2,
                    "batch" => 2, "slice" => 2, "join" => 1, "int" => 2,
                    "float" => 1, "default" => 2, "truncate" => 4,
                    "wordwrap" => 2, "filesizeformat" => 1, "sum" => 2}

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

  def self.replace_limited(s : String, old : String, new : String, count : Int64) : String
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

  # python str.istitle: each cased word starts upper, continues lower
  def self.istitle_check(s : String) : Bool
    prev_cased = false
    ok = true
    s.each_char do |ch|
      if ch.ascii_letter?
        if prev_cased
          ok = false unless ch.lowercase?
        else
          ok = false unless ch.uppercase?
        end
        prev_cased = true
      else
        prev_cased = false
      end
      break unless ok
    end
    ok
  end

  def self.length_of(v : AnyValue) : Int64
    case raw = v.raw
    when String then raw.size.to_i64
    when BigIntValue then raise TemplateError.new("object of type Int has no length", 0)
    when Array  then raw.size.to_i64
    when Hash   then raw.size.to_i64
    when TupleValue then raw.items.size.to_i64
    when Markup then raw.value.size.to_i64
    when Undefined then 0i64
    else raise TemplateError.new("object of type #{raw.class} has no length", 0)
    end
  end

  def self.to_iterable(v : AnyValue) : Array(AnyValue)
    case raw = v.raw
    when Array then raw
    when GeneratorValue then raw.materialize
    when String then raw.chars.map { |c| AnyValue.new(c.to_s) }
    when BigIntValue then raise TemplateError.new("'int' object is not iterable", 0)
    when Markup then raw.value.chars.map { |c| AnyValue.new(c.to_s) }
    when TupleValue then raw.items
    when Hash then raw.keys.map { |k| AnyValue.new(k) }
    when Undefined then [] of AnyValue
    else raise TemplateError.new("#{raw.class} object is not iterable", 0)
    end
  end

  private def self.to_int(v : AnyV, base : Int64 = 10i64) : Int64 | BigIntValue?
    case v
    when Int64 then v
    when BigIntValue then v
    when Float64 then v.to_i64
    when Bool then v ? 1i64 : 0i64
    when String
      s = v.strip
      if s.empty?
        nil
      elsif base == 10
        if big_int_string?(s)
          BigIntValue.parse(s)
        else
          s.to_i64? || s.to_f64?.try(&.to_i64)
        end
      elsif s.starts_with?("0x") || s.starts_with?("0X")
        s[2..].to_i64?(16)
      elsif s.starts_with?("0o") || s.starts_with?("0O")
        s[2..].to_i64?(8)
      elsif s.starts_with?("0b") || s.starts_with?("0B")
        s[2..].to_i64?(2)
      else
        s.to_i64?(base)
      end
    else nil
    end
  end

  private def self.to_float(v : AnyV) : Float64?
    case v
    when Int64 then v.to_f64
    when BigIntValue then v.to_f64
    when Bool then v ? 1.0 : 0.0
    when Float64 then v
    when String
      v.strip.empty? ? nil : v.strip.to_f64?
    else nil
    end
  end

  private def self.digit_string_v(v : AnyV) : String?
    case v
    when Int64       then (v >= 0 ? v.to_s : nil)
    when BigIntValue then v.negative? ? nil : v.value
    else nil
    end
  end

  private def self.numeric_add(a : AnyV, b : AnyV) : AnyV
    if a_big = a.as?(BigIntValue)
      case b
      when Int64       then return KrikriJinja.norm_decimal(KrikriJinja.big_add(a_big.value, b.to_s))
      when BigIntValue then return KrikriJinja.norm_decimal(KrikriJinja.big_add(a_big.value, b.value))
      when Float64     then return a_big.to_f64 + b
      when Bool        then return KrikriJinja.norm_decimal(KrikriJinja.big_add(a_big.value, b ? "1" : "0"))
      end
    end
    if b_big = b.as?(BigIntValue)
      case a
      when Int64       then return KrikriJinja.norm_decimal(KrikriJinja.big_add(a.to_s, b_big.value))
      when Float64     then return a + b_big.to_f64
      when Bool        then return KrikriJinja.norm_decimal(KrikriJinja.big_add(a ? "1" : "0", b_big.value))
      end
    end
    x = a.as?(Int64) || a.as?(Float64) || (a.is_a?(Bool) ? (a ? 1i64 : 0i64) : nil)
    y = b.as?(Int64) || b.as?(Float64) || (b.is_a?(Bool) ? (b ? 1i64 : 0i64) : nil)
    if x && y
      if x.is_a?(Int64) && y.is_a?(Int64)
        if (x > 0 && y > 0 && x > Int64::MAX - y) || (x < 0 && y < 0 && x < Int64::MIN - y)
          return KrikriJinja.norm_decimal(KrikriJinja.big_add(x.to_s, y.to_s))
        end
        return x + y
      end
      return x.to_f64 + y.to_f64
    end
    raise TemplateError.new("unsupported operand type(s) for +", 0)
  end

  # Bound string methods (Python str.*), callable from templates.
  private def self.string_method(s : String, name : String) : AnyValue
    impl = case name
           when "replace"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               old = stringify(args[0])
               new = stringify(args[1]? || AnyValue.new(""))
               if count = args[2]?.try(&.raw.as?(Int64))
                 AnyValue.new(KrikriJinja.replace_limited(s, old, new, count))
               else
                 AnyValue.new(s.gsub(old, new))
               end
             end
           when "split", "rsplit"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               sep = args[0]?.try(&.raw.as?(String))
               raise TemplateError.new("empty separator", 0) if sep == ""
               parts = if sep.nil?
                         s.split(/[ \t\r\n]+/).reject(&.empty?)
                       elsif name == "rsplit"
                         # no native rsplit with maxsplit; approximate for maxsplit<=0
                         s.split(sep)
                       else
                         s.split(sep)
                       end
               maxsplit = args[1]?.try(&.raw.as?(Int64))
               if maxsplit && maxsplit >= 0 && sep && !sep.empty?
                 if name == "split"
                   parts = s.split(sep, (maxsplit + 1).to_i32)
                 else
                   # rsplit: split from the right, keeping left part whole
                   pieces = s.split(sep)
                   if pieces.size > maxsplit + 1
                     head = pieces[0...(pieces.size - maxsplit)].join(sep)
                     parts = [head] + pieces[(pieces.size - maxsplit)..]
                   end
                 end
               end
               AnyValue.new(parts.map { |p| AnyValue.new(p) })
             end
           when "startswith", "endswith"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               prefix = stringify(args[0])
               ok = name == "startswith" ? s.starts_with?(prefix) : s.ends_with?(prefix)
               AnyValue.new(ok)
             end
           when "strip", "lstrip", "rstrip"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               chars = args[0]?.try(&.raw.as?(String)) || " \t\r\n"
               r = case name
                   when "strip" then s.strip(chars)
                   when "lstrip" then s.lstrip(chars)
                   else s.rstrip(chars)
                   end
               AnyValue.new(r)
             end
           when "count"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               sub = stringify(args[0])
               start = args[1]?.try(&.raw.as?(Int64)) || 0i64
               stop = args[2]?.try(&.raw.as?(Int64)) || s.size.to_i64
               region = s[(start < 0 ? s.size + start : start)..(stop < 0 ? s.size + stop - 1 : stop - 1)].to_s
               if sub.empty?
                 n = region.size + 1
               else
                 n = 0
                 pos = 0
                 while (idx = region.index(sub, pos))
                   n += 1
                   pos = idx + sub.size
                 end
               end
               AnyValue.new(n.to_i64)
             end
           when "find", "index", "rfind"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               sub = stringify(args[0])
               start = args[1]?.try(&.raw.as?(Int64)) || 0i64
               stop = args[2]?.try(&.raw.as?(Int64)) || s.size.to_i64
               lo = (start < 0 ? s.size + start : start).clamp(0, s.size)
               hi = (stop < 0 ? s.size + stop : stop).clamp(0, s.size)
               region = lo <= hi ? s[lo...hi] : ""
               pos = name == "rfind" ? region.rindex(sub) : region.index(sub)
               offset = (start < 0 ? s.size + start : start)
               if name == "index"
                 raise TemplateError.new("substring not found", 0) unless pos
               end
               AnyValue.new(pos ? (offset + pos).to_i64 : -1i64)
             end
           when "join"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               items = to_iterable(args[0]? || AnyValue.new(nil))
               AnyValue.new(items.map { |i| stringify(i) }.join(s))
             end
           when "zfill"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               width = args[0]?.try(&.raw.as?(Int64)) || 0i64
               sign = s.starts_with?("-") ? "-" : (s.starts_with?("+") ? "+" : "")
               digits = s.lstrip('-').lstrip('+')
               AnyValue.new(sign + digits.rjust(width - sign.size, '0'))
             end
           when "ljust", "rjust"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               width = args[0]?.try(&.raw.as?(Int64)) || 0i64
               fill = args[1]?.try(&.raw.as?(String)) || " "
               raise TemplateError.new("The fill character must be exactly one character long", 0) if fill.size > 1
               fc = fill.empty? ? ' ' : fill[0]
               name == "ljust" ? AnyValue.new(s.ljust(width, fc)) : AnyValue.new(s.rjust(width, fc))
             end
           when "partition", "rpartition"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               sep = stringify(args[0])
               raise TemplateError.new("empty separator", 0) if sep.empty?
               parts = if name == "partition"
                         idx = s.index(sep)
                         idx ? [s[0, idx], sep, s[(idx + sep.size)..]] : [s, "", ""]
                       else
                         idx = s.rindex(sep)
                         idx ? [s[0, idx], sep, s[(idx + sep.size)..]] : ["", "", s]
                       end
               AnyValue.new(TupleValue.new(parts.map { |p| AnyValue.new(p) }))
             end
           when "splitlines"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               keepends = args[0]?.try(&.raw) == true
               if s.empty?
                 AnyValue.new([] of AnyValue)
               else
                 lines = [] of String
                 start = 0
                 i = 0
                 while i < s.size
                   if s[i] == '\r' || s[i] == '\n'
                     term = (s[i] == '\r' && s[i + 1]? == '\n') ? 2 : 1
                     lines << (keepends ? s[start..(i + term - 1)] : s[start...i])
                     i += term
                     start = i
                   else
                     i += 1
                   end
                 end
                 lines << s[start..] if start < s.size
                 AnyValue.new(lines.map { |l| AnyValue.new(l) })
               end
             end
           when "removeprefix", "removesuffix"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               affix = stringify(args[0])
               r = if name == "removeprefix"
                     s.starts_with?(affix) ? s[affix.size..] : s
                   else
                     s.ends_with?(affix) ? s[0, s.size - affix.size] : s
                   end
               AnyValue.new(r)
             end
           when "expandtabs"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               tabsize = args[0]?.try(&.raw.as?(Int64)) || 8i64
               if tabsize <= 0
                 AnyValue.new(s.gsub('\t', ""))
               else
               col = 0i64
               expanded = String.build do |io|
                 s.each_char do |ch|
                   if ch == '\t'
                     spaces = tabsize - (col % tabsize)
                     spaces.times { io << ' ' }
                     col += spaces
                   else
                     io << ch
                     col += 1
                   end
                 end
               end
               AnyValue.new(expanded)
               end
             end
           when "casefold"
             ->(_args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               AnyValue.new(s.downcase)
             end
           when "swapcase"
             ->(_args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               AnyValue.new(s.chars.map { |c| c.ascii_uppercase? ? c.downcase : c.upcase }.join)
             end
           when "isdigit"
             ->(_args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               AnyValue.new(!s.empty? && s.chars.all?(&.number?))
             end
           when "isalpha"
             ->(_args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               AnyValue.new(!s.empty? && s.chars.all? { |c| c.letter? })
             end
           when "format"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               AnyValue.new(KrikriJinja.str_format(s, args))
             end
           when "center"
             ->(args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               width = args[0]?.try(&.raw.as?(Int64)) || 0i64
               fill = args[1]?.try(&.raw.as?(String)) || " "
               raise TemplateError.new("The fill character must be exactly one character long", 0) if fill.size > 1
               fc = fill.empty? ? ' ' : fill[0]
               rem = width - s.size
               if rem <= 0
                 AnyValue.new(s)
               else
                 # python: left = rem // 2 + (rem & width & 1)
                 left = rem // 2 + ((rem & width) & 1)
                 AnyValue.new((fc.to_s * left) + s + (fc.to_s * (rem - left)))
               end
             end
           when "islower"
             ->(_args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               letters = s.chars.select(&.ascii_letter?)
               AnyValue.new(letters.size > 0 && letters.all?(&.lowercase?))
             end
           when "isupper"
             ->(_args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               AnyValue.new(s.chars.select(&.ascii_letter?).size > 0 && s.chars.select(&.ascii_letter?).all?(&.uppercase?))
             end
           when "istitle"
             ->(_args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               AnyValue.new(!s.empty? && s.chars.select(&.ascii_letter?).size > 0 && istitle_check(s))
             end
           when "isspace"
             ->(_args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               AnyValue.new(!s.empty? && s.chars.all?(&.whitespace?))
             end
           when "isalnum"
             ->(_args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               AnyValue.new(!s.empty? && s.chars.all?(&.alphanumeric?))
             end
           when "title"
             ->(_args : Array(AnyValue), _k : Hash(String, AnyValue), _c : Context) do
               prev_alpha = false
               titled = String.build do |io|
                 s.each_char do |ch|
                   if ch.ascii_letter?
                     io << (prev_alpha ? ch.downcase : ch.upcase)
                     prev_alpha = true
                   else
                     io << ch
                     prev_alpha = false
                   end
                 end
               end
               AnyValue.new(titled)
             end
           else
             raise TemplateError.new("unknown method #{name}", 0)
           end
    AnyValue.new(KrikriJinja::SimpleCallable.new(name, &impl))
  end

  def self.get_attr(obj : AnyValue, name : String?) : AnyValue?
    return nil unless name
    case raw = obj.raw
    when Hash
      case name
      when "keys"
        AnyValue.new(KrikriJinja::SimpleCallable.new("keys") do |_a, _k, _c|
          AnyValue.new(raw.keys.map { |k| KrikriJinja.decode_key(k) })
        end)
      when "values"
        AnyValue.new(KrikriJinja::SimpleCallable.new("values") do |_a, _k, _c|
          AnyValue.new(raw.values)
        end)
      when "items"
        AnyValue.new(KrikriJinja::SimpleCallable.new("items") do |_a, _k, _c|
          AnyValue.new(raw.map { |k, x| AnyValue.new(TupleValue.new([KrikriJinja.decode_key(k), x])) })
        end)
      when "get"
        AnyValue.new(KrikriJinja::SimpleCallable.new("get") do |args, _k, _c|
          key = args[0]
          enc = KrikriJinja.dict_key(key)
          alt = KrikriJinja.dict_key_alt(key)
          found = raw[enc]? || (alt ? raw[alt]? : nil)
          found || args[1]? || AnyValue.new(nil)
        end)
      else raw[name]?
      end
    when LoopObject
      case name
      when "cycle"
        AnyValue.new(KrikriJinja::SimpleCallable.new("cycle") do |args, _k, _c|
          args[raw.index % args.size]
        end)
      when "changed"
        AnyValue.new(KrikriJinja::SimpleCallable.new("changed") do |args, _k, _c|
          current = args[0]?
          changed = raw.last_changed.nil? || !KrikriJinja.values_equal(raw.last_changed.not_nil!, current || AnyValue.new(nil))
          raw.last_changed = current
          AnyValue.new(changed)
        end)
      else
        raw.to_ctx_hash[name]?
      end
    when LoopCallable
      case name
      when "cycle"
        AnyValue.new(KrikriJinja::SimpleCallable.new("cycle") do |args, _k, _c|
          idx = raw.index % args.size
          args[idx]
        end)
      when "changed"
        AnyValue.new(KrikriJinja::SimpleCallable.new("changed") do |args, _k, _c|
          current = args[0]?
          changed = raw.last_changed.nil? || !KrikriJinja.values_equal(raw.last_changed.not_nil!, current || AnyValue.new(nil))
          raw.last_changed = current
          AnyValue.new(changed)
        end)
      else
        raw.to_ctx_hash[name]?
      end
    when Namespace then raw.data[name]?
    when Cycler
      case name
      when "next"
        AnyValue.new(KrikriJinja::SimpleCallable.new("next") { |_a, _k, _c| raw.next_item })
      when "reset"
        AnyValue.new(KrikriJinja::SimpleCallable.new("reset") { |_a, _k, _c| raw.reset })
      when "current"
        raw.current_value
      else nil
      end
    when TupleValue
      if raw.is_a?(TupleValue) && (idx = name.to_i64?)
        (0 <= idx < raw.items.size) ? raw.items[idx] : nil
      else
        nil
      end
    when Int64
      if name == "bit_length"
        AnyValue.new(KrikriJinja::SimpleCallable.new("bit_length") do |_a, _k, _c|
          AnyValue.new(raw.bit_length.to_i64)
        end)
      else
        nil
      end
    when Array, String
      case name
      when "upper"
        if raw.is_a?(String)
          val_up = AnyValue.new(raw.upcase)
          AnyValue.new(KrikriJinja::SimpleCallable.new("upper") do |_a, _k, _c|
            val_up.as(AnyValue)
          end)
        else
          nil
        end
      when "lower"
        if raw.is_a?(String)
          val_dn = AnyValue.new(raw.downcase)
          AnyValue.new(KrikriJinja::SimpleCallable.new("lower") do |_a, _k, _c|
            val_dn.as(AnyValue)
          end)
        else
          nil
        end
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
      when "append"
        if raw.is_a?(Array)
          AnyValue.new(KrikriJinja::SimpleCallable.new("append") do |args, _k, _c|
            raw << args[0]
            AnyValue.new(nil)
          end)
        else
          nil
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
      when "replace"
        raw.is_a?(String) ? string_method(raw, name) : nil
      when "split", "rsplit", "startswith", "endswith", "strip", "lstrip",
           "rstrip", "count", "find", "index", "join", "format", "zfill",
           "ljust", "rjust", "partition", "rpartition", "splitlines",
           "removeprefix", "removesuffix", "expandtabs", "casefold", "swapcase",
           "isdigit", "isalpha", "center", "rfind", "islower", "isupper",
           "istitle", "isspace", "isalnum", "title"
        raw.is_a?(String) ? string_method(raw, name) : nil
      when "keys"
        h = obj.raw.as?(Hash)
        if h
          keys = h.keys.map { |k| KrikriJinja.decode_key(k) }
          impl_keys = keys
          AnyValue.new(KrikriJinja::SimpleCallable.new("keys") do |_a, _k, _c|
            AnyValue.new(impl_keys)
          end)
        else
          nil
        end
      when "values"
        h2 = obj.raw.as?(Hash)
        if h2
          vals = h2.values
          impl_vals = vals
          AnyValue.new(KrikriJinja::SimpleCallable.new("values") do |_a, _k, _c|
            AnyValue.new(impl_vals)
          end)
        else
          nil
        end
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

  # JSON string escaping with ensure_ascii (Python json.dumps default).
  private def self.json_string(io : IO, s : String)
    io << '"'
    s.each_char do |c|
      case c
      when '"' then io << '\\' << c
      when '\\' then io << '\\' << '\\'
      when '\b' then io << '\\' << 'b'
      when '\f' then io << '\\' << 'f'
      when '\n' then io << '\\' << 'n'
      when '\r' then io << '\\' << 'r'
      when '\t' then io << '\\' << 't'
      else
        if c.ascii_control? || c.ord > 127 || {'<', '>', '&', '\''}.includes?(c)
          cp = c.ord
          if cp > 0xFFFF
            cp -= 0x10000
            hi = 0xD800 + (cp >> 10)
            lo = 0xDC00 + (cp & 0x3FF)
            io << '\\' << 'u' << hi.to_s(16).rjust(4, '0')
            io << '\\' << 'u' << lo.to_s(16).rjust(4, '0')
          else
            io << '\\' << 'u' << cp.to_s(16).rjust(4, '0')
          end
        else
          io << c
        end
      end
    end
    io << '"'
  end

  private def self.json_write(io : IO, v : AnyV, indent : Int64?, depth : Int32)
    case v
    when Nil then io << "null"
    when Bool then io << (v ? "true" : "false")
    when Int64 then v.to_s(io)
    when BigIntValue
      check_int_str_limit(v.value)
      io << v.value
    when Float64 then format_float(v).to_s(io)
    when String then json_string(io, v)
    when Markup
      json_string(io, v.value)
    when TupleValue
      io << "["
      v.items.each_with_index do |item, i|
        io << ", " if i > 0
        json_write(io, item.raw, indent, depth + 1)
      end
      io << "]"
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
      # Python json.dumps(sort_keys=True) as configured by Jinja's tojson.
      entries = v.to_a.sort! { |a, b| a[0] <=> b[0] }
      key_str = ->(k : String) : String do
        dec = KrikriJinja.decode_key(k).raw
        case dec
        when Int64 then dec.to_s
        when BigIntValue then dec.value
        when Bool  then dec ? "true" : "false"
        when Nil   then "null"
        when Float64 then KrikriJinja.format_float(dec)
        else dec.as(String)
        end
      end
      io << "{"
      if indent && !entries.empty?
        entries.each_with_index do |(k, x), i|
          io << "," if i > 0
          io << '\n' << (" " * (indent * (depth + 1)))
          json_string(io, key_str.call(k))
          io << ": "
          json_write(io, x.raw, indent, depth + 1)
        end
        io << '\n' << (" " * (indent * depth))
      else
        entries.each_with_index do |(k, x), i|
          io << ", " if i > 0
          json_string(io, key_str.call(k))
          io << ": "
          json_write(io, x.raw, indent, depth + 1)
        end
      end
      io << "}"
    when Undefined
      raise TemplateError.new("Object of type Undefined is not JSON serializable", 0)
    else
      stringify(AnyValue.wrap(v)).to_json(io)
    end
  end
end
