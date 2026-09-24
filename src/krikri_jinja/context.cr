module KrikriJinja
  class Context
    getter scopes : Array(Hash(String, AnyValue))
    getter globals : Hash(String, AnyValue)
    property autoescape : Bool
    getter loader : Loader?
    getter blocks : Hash(String, Array(Nodes::BlockNode))
    property hide_locals : Bool
    property hide_from : Int32
    property hide_loop_var : Bool

    def initialize(@globals : Hash(String, AnyValue) = {} of String => AnyValue,
                   @loader : Loader? = nil,
                   @autoescape = false)
      @scopes = [{} of String => AnyValue]
      @blocks = {} of String => Array(Nodes::BlockNode)
      @scope_is_local = [false]
      @hide_locals = false
      @hide_from = 0
      @hide_loop_var = false
    end

    def [](name : String) : AnyValue
      (v = self[name]?) ? v : AnyValue.new(Undefined.new)
    end

    def []?(name : String) : AnyValue?
      return if @hide_loop_var && name == "loop"
      @scopes.reverse_each.with_index do |scope, rev_i|
        i = @scopes.size - 1 - rev_i
        next if @hide_locals && i < @hide_from && @scope_is_local[i]?
        return scope[name]? if scope.has_key?(name)
      end
      return AnyValue.new(Undefined.new) if @hide_loop_var && name == "loop"
      @globals[name]?
    end

    def has_key?(name : String) : Bool
      v = self[name]?
      !!(v && !v.raw.is_a?(Undefined))
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
    def initialize(@root : String)
    end

    def get_source(name : String) : String?
      path = File.expand_path(name, @root)
      return nil unless path.starts_with?(File.expand_path(@root))
      File.read(path) if File.file?(path)
    end
  end
end
