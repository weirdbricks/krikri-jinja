module KrikriJinja
  class Context
    getter scopes : Array(Hash(String, AnyValue))
    getter globals : Hash(String, AnyValue)
    property autoescape : Bool
    property undefined : Undefined
    getter loader : Loader?
    getter filters : Hash(String, FilterFn)
    getter tests : Hash(String, TestFn)
    property blocks : Hash(String, Array(Nodes::BlockNode))
    property hide_locals : Bool
    property hide_from : Int32
    property hide_loop_var : Bool
    property hide_super : Bool
    property loop_is_local : Bool
    # Opaque caller-supplied context handed to registered filters, tests,
    # and functions, for hosts that need controller-side state (variable
    # scope, role paths, plugin runners) that the engine cannot know about.
    property host_context : HostContext?
    # Lazy variable source consulted after every scope and before globals.
    property resolver : VariableResolver?

    def initialize(@globals : Hash(String, AnyValue) = {} of String => AnyValue,
                   @loader : Loader? = nil,
                   @autoescape = false,
                   @undefined : Undefined = Undefined.new,
                   @filters : Hash(String, FilterFn) = BUILTIN_FILTERS.dup,
                   @tests : Hash(String, TestFn) = BUILTIN_TESTS.dup)
      @scopes = [{} of String => AnyValue]
      @blocks = {} of String => Array(Nodes::BlockNode)
      @scope_is_local = [false]
      @hide_locals = false
      @hide_from = 0
      @hide_loop_var = false
      @hide_super = false
      @loop_is_local = true
      @host_context = nil.as(HostContext?)
      @resolver = nil.as(VariableResolver?)
    end

    def [](name : String) : AnyValue
      (v = self[name]?) ? v : undefined_named(name)
    end

    # The engine's shared Undefined instance carries no name; a lookup miss
    # hands out a copy tagged with the variable that was missing so error
    # messages can name it the way real Jinja2 does.
    def undefined_named(name : String, hint : String? = nil) : AnyValue
      undefined = @undefined
      value = undefined.strict? ? StrictUndefined.new(name, undefined.chainable) : Undefined.new(name, undefined.chainable)
      value.hint = hint
      AnyValue.new(value)
    end

    # An undefined for an attribute or key *name* that *obj* lacks, with
    # Jinja's own message ("'dict object' has no attribute 'x'").
    def missing_attribute(obj : AnyValue, name : String) : AnyValue
      undefined_named(name, "'#{KrikriJinja.type_label(obj)} object' has no attribute '#{name}'")
    end

    def []?(name : String) : AnyValue?
      return if (@hide_loop_var && name == "loop") || (@hide_super && name == "super")
      @scopes.reverse_each.with_index do |scope, rev_i|
        i = @scopes.size - 1 - rev_i
        next if @hide_locals && i < @hide_from && @scope_is_local[i]?
        if value = scope[name]?
          return value
        end
      end
      return undefined_named(name) if @hide_loop_var && name == "loop"
      if (resolver = @resolver) && (value = resolver.resolve(name))
        return value
      end
      @globals[name]?
    end

    def has_key?(name : String) : Bool
      v = self[name]?
      !!(v && !v.raw.is_a?(Undefined))
    end

    # A fully-qualified collection name (`ansible.builtin.ternary`,
    # namespace.collection.name) resolves to the filter or test registered
    # under its trailing segment, the way Ansible resolves
    # `| ansible.builtin.ternary(...)` to `ternary`. A single dot is not a
    # collection name (`x | first.to_s` stays unknown, as in jinja).
    def filter(name : String) : FilterFn?
      @filters[name]? || collection_member(name).try { |short| @filters[short]? }
    end

    def test(name : String) : TestFn?
      @tests[name]? || collection_member(name).try { |short| @tests[short]? }
    end

    private def collection_member(name : String) : String?
      name.count('.') >= 2 ? name.rpartition('.')[2] : nil
    end

    def []=(name : String, value : AnyValue)
      @scopes.last[name] = value
    end

    def delete(name : String)
      @scopes[0].delete(name)
    end

    def push_scope(local = false)
      @scopes.push({} of String => AnyValue)
      @scope_is_local.push(local)
    end

    def pop_scope
      @scopes.pop
      @scope_is_local.pop
    end

    def register_block(name : String, node : Nodes::BlockNode)
      (@blocks[name] ||= [] of Nodes::BlockNode) << node
    end
  end

  # Template source providers.
  abstract class Loader
    abstract def get_source(name : String) : String?
  end

  class DictLoader < Loader
    def initialize(@templates : Hash(String, String))
    end

    def get_source(name : String) : String?
      @templates[name]?
    end
  end

  class FileSystemLoader < Loader
    @cache : Hash(String, {Time, String})

    def initialize(@root : String)
      @root_path = File.expand_path(@root)
      @cache = {} of String => {Time, String}
    end

    # Caches file contents keyed by name, invalidated by mtime, so
    # repeated includes/imports of the same template do not re-read disk.
    def get_source(name : String) : String?
      path = File.expand_path(name, @root_path)
      return nil unless path == @root_path || path.starts_with?(@root_path + File::SEPARATOR)
      info = File.info?(path)
      return nil unless info
      mtime = info.modification_time
      if (cached = @cache[name]?) && cached[0] == mtime
        return cached[1]
      end
      content = File.read(path)
      @cache[name] = {mtime, content}
      content
    end
  end
end
