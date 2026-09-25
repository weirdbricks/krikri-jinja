module KrikriJinja
  class Context
    getter scopes : Array(Hash(String, AnyValue))
    getter globals : Hash(String, AnyValue)
    property autoescape : Bool
    property undefined : Undefined
    getter loader : Loader?
    property blocks : Hash(String, Array(Nodes::BlockNode))
    property hide_locals : Bool
    property hide_from : Int32
    property hide_loop_var : Bool
    property hide_super : Bool
    property loop_is_local : Bool

    def initialize(@globals : Hash(String, AnyValue) = {} of String => AnyValue,
                   @loader : Loader? = nil,
                   @autoescape = false,
                   @undefined : Undefined = Undefined.new)
      @scopes = [{} of String => AnyValue]
      @blocks = {} of String => Array(Nodes::BlockNode)
      @scope_is_local = [false]
      @hide_locals = false
      @hide_from = 0
      @hide_loop_var = false
      @hide_super = false
      @loop_is_local = true
    end

    def [](name : String) : AnyValue
      (v = self[name]?) ? v : AnyValue.new(@undefined)
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
      return AnyValue.new(@undefined) if @hide_loop_var && name == "loop"
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
      @root_path = File.expand_path(@root)
    end

    def get_source(name : String) : String?
      path = File.expand_path(name, @root_path)
      return nil unless path == @root_path || path.starts_with?(@root_path + File::SEPARATOR)
      File.read(path) if File.file?(path)
    end
  end
end
