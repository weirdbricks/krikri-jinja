module KrikriJinja
  class Context
    getter scopes : Array(Hash(String, AnyValue))
    getter globals : Hash(String, AnyValue)
    property autoescape : Bool
    getter loader : Loader?
    getter blocks : Hash(String, Array(Nodes::BlockNode))

    def initialize(@globals : Hash(String, AnyValue) = {} of String => AnyValue,
                   @loader : Loader? = nil,
                   @autoescape = false)
      @scopes = [{} of String => AnyValue]
      @blocks = {} of String => Array(Nodes::BlockNode)
    end

    def [](name : String) : AnyValue
      @scopes.reverse_each do |scope|
        if scope.has_key?(name)
          return scope[name]
        end
      end
      if @globals.has_key?(name)
        return @globals[name]
      end
      AnyValue.new(nil)
    end

    def []?(name : String) : AnyValue?
      @scopes.reverse_each do |scope|
        return scope[name]? if scope.has_key?(name)
      end
      @globals[name]?
    end

    def has_key?(name : String) : Bool
      !!self[name]?
    end

    def []=(name : String, value : AnyValue)
      @scopes.last[name] = value
    end

    def delete(name : String)
      @scopes[0].delete(name)
    end

    def push_scope
      @scopes.push({} of String => AnyValue)
    end

    def pop_scope
      @scopes.pop
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
