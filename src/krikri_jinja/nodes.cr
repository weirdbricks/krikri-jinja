module KrikriJinja
  # Render-time values: a JSON::Any-style wrapper so arrays/hashes can hold
  # arbitrary values (Crystal cannot express recursive type aliases).
  class AnyValue
    getter raw : AnyV

    def initialize(@raw : AnyV)
    end

    def self.wrap(x : AnyV | AnyValue) : AnyValue
      x.is_a?(AnyValue) ? x : AnyValue.new(x)
    end

    # Boxes a raw value deeply (arrays/hashes get boxed element-wise).
    def self.wrap_deep(x : AnyV | AnyValue) : AnyValue
      case v = x
      when Array
        AnyValue.new(v.map { |e| wrap_deep(e) })
      when Hash
        h = {} of String => AnyValue
        v.each { |k, e| h[k] = wrap_deep(e) }
        AnyValue.new(h)
      else
        wrap(x)
      end
    end

    def self.pair(a : AnyV, b : AnyV) : AnyValue
      AnyValue.new([wrap(a), wrap(b)])
    end
  end

  # A Python tuple value (produced by dictsort/items); stringifies with
  # parentheses and supports iteration/unpacking/indexing like an array.
  class TupleValue
    getter items : Array(AnyValue)

    def initialize(@items)
    end
  end

  # Base class for an opaque, caller-supplied context handed to registered
  # filters, tests, and functions. Hosts that need controller-side state
  # (variable scope, role paths, plugin runners) subclass this and read it
  # back from `ctx.host_context` inside their registrations.
  abstract class HostContext
  end

  # Supplies variables on demand, for hosts whose variable scope is large or
  # whose values need host-side preparation before the engine can use them.
  # A context consults its resolver for a name that no scope defines, before
  # falling back to globals. Returning nil leaves the name to the globals and
  # then to the engine's undefined value.
  abstract class VariableResolver
    abstract def resolve(name : String) : AnyValue?
  end

  # Marker for undefined variables, mirroring Jinja's Undefined behavior:
  # stringifies to "", is falsy, fails `is none`, and raises on operations.
  class Undefined
    property name : String?
    # Ansible's own Undefined is CHAINABLE: reaching an attribute or item of
    # an undefined value yields another undefined instead of raising, so
    # `x | default(other.thing.y)` stays lazy when `x` is defined. Jinja2's
    # own default is not chainable and raises on the spot.
    property chainable : Bool

    def initialize(@name : String? = nil, @chainable : Bool = false)
    end

    def strict? : Bool
      false
    end

    def ==(other : Undefined) : Bool
      true
    end

    def ==(other) : Bool
      false
    end
  end

  class StrictUndefined < Undefined
    def initialize(@name : String? = nil, @chainable : Bool = false)
      super(@name, @chainable)
    end

    def strict? : Bool
      true
    end
  end

  # Ansible's strict undefined: raises when an undefined value is USED, and
  # chains through attribute/subscript access on the way there.
  def self.ansible_strict_undefined : StrictUndefined
    StrictUndefined.new(nil, chainable: true)
  end

  # The message real Jinja2/Ansible reports names the variable that was
  # missing; fall back to a generic word when the name is unknown.
  def self.undefined_message(value : Undefined) : String
    "'#{value.name || "missing"}' is undefined"
  end

  # Lazily-evaluated filter results (map/select/selectattr and friends);
  # iterable like an array but has no length, matching Python generators.
  class GeneratorValue
    getter items : Array(AnyValue)
    getter fail : String?

    def initialize(@items, @fail = nil)
    end

    def materialize : Array(AnyValue)
      if f = @fail
        raise TemplateError.new(f, 0)
      end
      @items
    end
  end

  # Loop assignment target: a plain name or a nested tuple pattern like
  # (a, (b, c)).
  class TargetSpec
    property name : String
    property children : Array(TargetSpec)?

    def initialize(@name, @children = nil)
    end
  end

  class BigIntValue
    getter value : String

    def self.parse(value : String) : Int64 | BigIntValue
      value.to_i64? || new(value)
    end

    def initialize(@value : String)
      unless @value.matches?(/\A-?(0|[1-9]\d*)\z/)
        raise ArgumentError.new("invalid big integer: #{@value}")
      end
    end

    def to_s : String
      @value
    end

    def to_f64 : Float64
      @value.to_f64
    end

    def negative? : Bool
      @value.starts_with?('-')
    end

    def zero? : Bool
      @value == "0"
    end

    def digits : String
      @value.lstrip('-')
    end

    def negated : BigIntValue
      BigIntValue.new(negative? ? digits : "-#{digits}")
    end

    def absolute : BigIntValue
      BigIntValue.new(digits)
    end
  end

  # Anything a filter/test/global function may return.
  alias AnyV = Nil | Bool | Int64 | Float64 | String | BigIntValue | Array(AnyValue) |
               Hash(String, AnyValue) | Callable | Markup | LoopObject | LoopCallable | Undefined | TupleValue | GeneratorValue |
               HostObject

  # A host-defined value type (a date, a duration, ...) taking part in
  # templates through Python-style hooks. Every hook has a default that
  # means "not supported", so a host implements only what its type does.
  abstract class HostObject
    # Python's str(): what `{{ value }}` renders.
    abstract def to_s(io : IO) : Nil

    # Python's repr(), used inside list/dict output. Defaults to str().
    def repr : String
      to_s
    end

    # Attribute or method lookup (`value.days`, `value.strftime(...)`);
    # nil when the object has no such attribute.
    def get_attr(name : String) : AnyValue?
      nil
    end

    # A binary arithmetic operator with *other*. *reflected* is true when
    # this object is the right-hand operand (Python's __radd__ and
    # friends). Nil means unsupported for that operand.
    def binary_op(op : String, other : AnyValue, reflected : Bool) : AnyValue?
      nil
    end

    # Ordering against *other* (-1, 0, 1), or nil when incomparable.
    def compare(other : AnyValue) : Int32?
      nil
    end

    def truthy? : Bool
      true
    end

    # How the value crosses into JSON (tojson, host conversions).
    def to_json_any : JSON::Any
      JSON::Any.new(to_s)
    end
  end

  # Marker for callable values (macros and host-provided functions).
  abstract class Callable
    abstract def call(args : Array(AnyValue), kwargs : Hash(String, AnyValue), ctx : Context) : AnyValue
  end

  module Nodes
    abstract class Node
      property line : Int32

      def initialize(@line : Int32)
      end
    end

    # --- template-level nodes -------------------------------------------------

    class TemplateNode < Node
      property body : Array(Node)

      def initialize(@body : Array(Node), line : Int32)
        super(line)
      end
    end

    class TextNode < Node
      property text : String

      def initialize(@text : String, line : Int32)
        super(line)
      end
    end

    class OutputNode < Node
      property expr : ExprNode

      def initialize(@expr : ExprNode, line : Int32)
        super(line)
      end
    end

    class IfNode < Node
      property branches : Array(Tuple(ExprNode, Array(Node)))
      property orelse : Array(Node)?

      def initialize(@branches, @orelse, line : Int32)
        super(line)
      end
    end

    class ForNode < Node
      property targets : Array(TargetSpec)
      property iter : ExprNode
      property body : Array(Node)
      property orelse : Array(Node)?
      property test : ExprNode? # {% for x in y if cond %}
      property recursive : Bool

      def initialize(@targets, @iter, @body, @orelse, @test, @recursive, line : Int32)
        super(line)
      end
    end

    class SetNode < Node
      property targets : Array(String)
      property expr : ExprNode
      property attr_target : ExprNode? # {% set ns.attr = x %}
      property body : Array(Nodes::Node)? # {% set x %}...{% endset %}
      property filter_name : String?
      property filter_args : Array(ExprNode)
      property filter_kwargs : Array(Tuple(String, ExprNode))

      def initialize(@targets, @expr, @attr_target, line : Int32)
        super(line)
        @filter_args = [] of ExprNode
        @filter_kwargs = [] of Tuple(String, ExprNode)
      end
    end

    class BlockNode < Node
      property name : String
      property body : Array(Node)

      def initialize(@name, @body, line : Int32)
        super(line)
      end
    end

    class MacroNode < Node
      property name : String
      property params : Array(Tuple(String, ExprNode?)) # name + default
      property body : Array(Node)

      def initialize(@name, @params, @body, line : Int32)
        super(line)
      end
    end

    class CallNode < Node
      property macro_expr : ExprNode
      property args : Array(ExprNode)
      property kwargs : Array(Tuple(String, ExprNode))
      property body : Array(Node)?
      property call_params : Array(String)

      def initialize(@macro_expr, @args, @kwargs, @body, line : Int32)
        super(line)
        @call_params = [] of String
      end
    end

    class FilterBlockNode < Node
      property filter : ExprNode # FilterExpr
      property body : Array(Node)

      def initialize(@filter, @body, line : Int32)
        super(line)
      end
    end

    class WithNode < Node
      property bindings : Array(Tuple(String, ExprNode))
      property body : Array(Node)

      def initialize(@bindings, @body, line : Int32)
        super(line)
      end
    end

    class IncludeNode < Node
      property template : ExprNode
      property ignore_missing : Bool
      property with_context : Bool

      def initialize(@template, @ignore_missing, @with_context, line : Int32)
        super(line)
      end
    end

    class ExtendsNode < Node
      property template : ExprNode

      def initialize(@template, line : Int32)
        super(line)
      end
    end

    class ImportNode < Node
      property template : ExprNode
      property names : Array(Tuple(String, String)) # (source name, bound alias)
      property context : Bool
      property from_import : Bool

      def initialize(@template, @names, @context, @from_import = false, line : Int32 = 0)
        super(line)
      end
    end

    class DoNode < Node
      property expr : ExprNode

      def initialize(@expr, line : Int32)
        super(line)
      end
    end

    class AutoescapeNode < Node
      property enabled : Bool
      property body : Array(Node)

      def initialize(@enabled, @body, line : Int32)
        super(line)
      end
    end

    # --- expression nodes ------------------------------------------------------

    abstract class ExprNode < Node
    end

    class ConstNode < ExprNode
      property value : AnyV

      def initialize(@value, line : Int32)
        super(line)
      end
    end

    class NameNode < ExprNode
      property name : String

      def initialize(@name, line : Int32)
        super(line)
      end
    end

    class ListExprNode < ExprNode
      property items : Array(ExprNode)

      def initialize(@items, line : Int32)
        super(line)
      end
    end

    class TupleExprNode < ExprNode
      property items : Array(ExprNode)

      def initialize(@items, line : Int32)
        super(line)
      end
    end

    class DictExprNode < ExprNode
      property keys : Array(ExprNode)
      property values : Array(ExprNode)

      def initialize(@keys, @values, line : Int32)
        super(line)
      end
    end

    class BinOpNode < ExprNode
      property op : String
      property left : ExprNode
      property right : ExprNode

      def initialize(@op, @left, @right, line : Int32)
        super(line)
      end
    end

    class UnaryOpNode < ExprNode
      property op : String
      property operand : ExprNode

      def initialize(@op, @operand, line : Int32)
        super(line)
      end
    end

    class CompareNode < ExprNode
      property left : ExprNode
      property ops : Array(String)
      property comparators : Array(ExprNode)

      def initialize(@left, @ops, @comparators, line : Int32)
        super(line)
      end
    end

    class InTestNode < ExprNode # handled as a comparison op, kept for clarity
    end

    class FilterNode < ExprNode
      property name : String
      property args : Array(ExprNode)
      property kwargs : Array(Tuple(String, ExprNode))
      property target : ExprNode

      def initialize(@name, @args, @kwargs, @target, line : Int32)
        super(line)
      end
    end

    class TestNode < ExprNode # `x is divisibleby 3`
      property name : String
      property args : Array(ExprNode)
      property kwargs : Array(Tuple(String, ExprNode))
      property target : ExprNode
      property negated : Bool

      def initialize(@name, @args, @kwargs, @target, @negated, line : Int32)
        super(line)
      end
    end

    class GetattrNode < ExprNode
      property obj : ExprNode
      property attr : String

      def initialize(@obj, @attr, line : Int32)
        super(line)
      end
    end

    class GetitemNode < ExprNode
      property obj : ExprNode
      property key : ExprNode

      def initialize(@obj, @key, line : Int32)
        super(line)
      end
    end

    class SliceNode < ExprNode
      property obj : ExprNode
      property start : ExprNode?
      property stop : ExprNode?
      property step : ExprNode?

      def initialize(@obj, @start, @stop, @step, line : Int32)
        super(line)
      end
    end

    class CallExprNode < ExprNode
      property func : ExprNode
      property args : Array(ExprNode)
      property kwargs : Array(Tuple(String, ExprNode))
      property varargs_name : String? # macro call with body: {% call(x) m() %}

      def initialize(@func, @args, @kwargs, line : Int32)
        super(line)
      end
    end

    class CondExprNode < ExprNode
      property test : ExprNode
      property truthy : ExprNode
      property falsy : ExprNode?

      def initialize(@test, @truthy, @falsy, line : Int32)
        super(line)
      end
    end

    class ConcatNode < ExprNode
      property parts : Array(ExprNode)

      def initialize(@parts, line : Int32)
        super(line)
      end
    end
  end

  alias ExprNode = Nodes::ExprNode
  alias Node = Nodes::Node
end
