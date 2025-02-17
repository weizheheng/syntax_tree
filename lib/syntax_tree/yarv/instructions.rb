# frozen_string_literal: true

module SyntaxTree
  module YARV
    # This is an operand to various YARV instructions that represents the
    # information about a specific call site.
    class CallData
      CALL_ARGS_SPLAT = 1 << 0
      CALL_ARGS_BLOCKARG = 1 << 1
      CALL_FCALL = 1 << 2
      CALL_VCALL = 1 << 3
      CALL_ARGS_SIMPLE = 1 << 4
      CALL_BLOCKISEQ = 1 << 5
      CALL_KWARG = 1 << 6
      CALL_KW_SPLAT = 1 << 7
      CALL_TAILCALL = 1 << 8
      CALL_SUPER = 1 << 9
      CALL_ZSUPER = 1 << 10
      CALL_OPT_SEND = 1 << 11
      CALL_KW_SPLAT_MUT = 1 << 12

      attr_reader :method, :argc, :flags, :kw_arg

      def initialize(
        method,
        argc = 0,
        flags = CallData::CALL_ARGS_SIMPLE,
        kw_arg = nil
      )
        @method = method
        @argc = argc
        @flags = flags
        @kw_arg = kw_arg
      end

      def flag?(mask)
        (flags & mask) > 0
      end

      def to_h
        result = { mid: method, flag: flags, orig_argc: argc }
        result[:kw_arg] = kw_arg if kw_arg
        result
      end

      def self.from(serialized)
        new(
          serialized[:mid],
          serialized[:orig_argc],
          serialized[:flag],
          serialized[:kw_arg]
        )
      end
    end

    # A convenience method for creating a CallData object.
    def self.calldata(
      method,
      argc = 0,
      flags = CallData::CALL_ARGS_SIMPLE,
      kw_arg = nil
    )
      CallData.new(method, argc, flags, kw_arg)
    end

    # ### Summary
    #
    # `adjuststack` accepts a single integer argument and removes that many
    # elements from the top of the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # x = [true]
    # x[0] ||= nil
    # x[0]
    # ~~~
    #
    class AdjustStack
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def disasm(fmt)
        fmt.instruction("adjuststack", [fmt.object(number)])
      end

      def to_a(_iseq)
        [:adjuststack, number]
      end

      def length
        2
      end

      def pops
        number
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        vm.pop(number)
      end
    end

    # ### Summary
    #
    # `anytostring` ensures that the value on top of the stack is a string.
    #
    # It pops two values off the stack. If the first value is a string it
    # pushes it back on the stack. If the first value is not a string, it uses
    # Ruby's built in string coercion to coerce the second value to a string
    # and then pushes that back on the stack.
    #
    # This is used in conjunction with `objtostring` as a fallback for when an
    # object's `to_s` method does not return a string.
    #
    # ### Usage
    #
    # ~~~ruby
    # "#{5}"
    # ~~~
    #
    class AnyToString
      def disasm(fmt)
        fmt.instruction("anytostring")
      end

      def to_a(_iseq)
        [:anytostring]
      end

      def length
        1
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        original, value = vm.pop(2)

        if value.is_a?(String)
          vm.push(value)
        else
          vm.push("#<#{original.class.name}:0000>")
        end
      end
    end

    # ### Summary
    #
    # `branchif` has one argument: the jump index. It pops one value off the
    # stack: the jump condition.
    #
    # If the value popped off the stack is true, `branchif` jumps to
    # the jump index and continues executing there.
    #
    # ### Usage
    #
    # ~~~ruby
    # x = true
    # x ||= "foo"
    # puts x
    # ~~~
    #
    class BranchIf
      attr_reader :label

      def initialize(label)
        @label = label
      end

      def disasm(fmt)
        fmt.instruction("branchif", [fmt.label(label)])
      end

      def to_a(_iseq)
        [:branchif, label.name]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        vm.jump(label) if vm.pop
      end
    end

    # ### Summary
    #
    # `branchnil` has one argument: the jump index. It pops one value off the
    # stack: the jump condition.
    #
    # If the value popped off the stack is nil, `branchnil` jumps to
    # the jump index and continues executing there.
    #
    # ### Usage
    #
    # ~~~ruby
    # x = nil
    # if x&.to_s
    #   puts "hi"
    # end
    # ~~~
    #
    class BranchNil
      attr_reader :label

      def initialize(label)
        @label = label
      end

      def disasm(fmt)
        fmt.instruction("branchnil", [fmt.label(label)])
      end

      def to_a(_iseq)
        [:branchnil, label.name]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        vm.jump(label) if vm.pop.nil?
      end
    end

    # ### Summary
    #
    # `branchunless` has one argument: the jump index. It pops one value off
    # the stack: the jump condition.
    #
    # If the value popped off the stack is false or nil, `branchunless` jumps
    # to the jump index and continues executing there.
    #
    # ### Usage
    #
    # ~~~ruby
    # if 2 + 3
    #   puts "foo"
    # end
    # ~~~
    #
    class BranchUnless
      attr_reader :label

      def initialize(label)
        @label = label
      end

      def disasm(fmt)
        fmt.instruction("branchunless", [fmt.label(label)])
      end

      def to_a(_iseq)
        [:branchunless, label.name]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        vm.jump(label) unless vm.pop
      end
    end

    # ### Summary
    #
    # `checkkeyword` checks if a keyword was passed at the callsite that
    # called into the method represented by the instruction sequence. It has
    # two arguments: the index of the local variable that stores the keywords
    # metadata and the index of the keyword within that metadata. It pushes
    # a boolean onto the stack indicating whether or not the keyword was
    # given.
    #
    # ### Usage
    #
    # ~~~ruby
    # def evaluate(value: rand)
    #   value
    # end
    #
    # evaluate(value: 3)
    # ~~~
    #
    class CheckKeyword
      attr_reader :keyword_bits_index, :keyword_index

      def initialize(keyword_bits_index, keyword_index)
        @keyword_bits_index = keyword_bits_index
        @keyword_index = keyword_index
      end

      def disasm(fmt)
        fmt.instruction(
          "checkkeyword",
          [fmt.object(keyword_bits_index), fmt.object(keyword_index)]
        )
      end

      def to_a(iseq)
        [
          :checkkeyword,
          iseq.local_table.offset(keyword_bits_index),
          keyword_index
        ]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.local_get(keyword_bits_index, 0)[keyword_index])
      end
    end

    # ### Summary
    #
    # `checkmatch` checks if the current pattern matches the current value. It
    # pops the target and the pattern off the stack and pushes a boolean onto
    # the stack if it matches or not.
    #
    # ### Usage
    #
    # ~~~ruby
    # foo in Foo
    # ~~~
    #
    class CheckMatch
      TYPE_WHEN = 1
      TYPE_CASE = 2
      TYPE_RESCUE = 3

      attr_reader :type

      def initialize(type)
        @type = type
      end

      def disasm(fmt)
        fmt.instruction("checkmatch", [fmt.object(type)])
      end

      def to_a(_iseq)
        [:checkmatch, type]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        raise NotImplementedError, "checkmatch"
      end
    end

    # ### Summary
    #
    # `checktype` checks if the value on top of the stack is of a certain type.
    # The type is the only argument. It pops the value off the stack and pushes
    # a boolean onto the stack indicating whether or not the value is of the
    # given type.
    #
    # ### Usage
    #
    # ~~~ruby
    # foo in [bar]
    # ~~~
    #
    class CheckType
      TYPE_OBJECT = 0x01
      TYPE_CLASS = 0x02
      TYPE_MODULE = 0x03
      TYPE_FLOAT = 0x04
      TYPE_STRING = 0x05
      TYPE_REGEXP = 0x06
      TYPE_ARRAY = 0x07
      TYPE_HASH = 0x08
      TYPE_STRUCT = 0x09
      TYPE_BIGNUM = 0x0a
      TYPE_FILE = 0x0b
      TYPE_DATA = 0x0c
      TYPE_MATCH = 0x0d
      TYPE_COMPLEX = 0x0e
      TYPE_RATIONAL = 0x0f
      TYPE_NIL = 0x11
      TYPE_TRUE = 0x12
      TYPE_FALSE = 0x13
      TYPE_SYMBOL = 0x14
      TYPE_FIXNUM = 0x15
      TYPE_UNDEF = 0x16

      attr_reader :type

      def initialize(type)
        @type = type
      end

      def disasm(fmt)
        name =
          case type
          when TYPE_OBJECT
            "T_OBJECT"
          when TYPE_CLASS
            "T_CLASS"
          when TYPE_MODULE
            "T_MODULE"
          when TYPE_FLOAT
            "T_FLOAT"
          when TYPE_STRING
            "T_STRING"
          when TYPE_REGEXP
            "T_REGEXP"
          when TYPE_ARRAY
            "T_ARRAY"
          when TYPE_HASH
            "T_HASH"
          when TYPE_STRUCT
            "T_STRUCT"
          when TYPE_BIGNUM
            "T_BIGNUM"
          when TYPE_FILE
            "T_FILE"
          when TYPE_DATA
            "T_DATA"
          when TYPE_MATCH
            "T_MATCH"
          when TYPE_COMPLEX
            "T_COMPLEX"
          when TYPE_RATIONAL
            "T_RATIONAL"
          when TYPE_NIL
            "T_NIL"
          when TYPE_TRUE
            "T_TRUE"
          when TYPE_FALSE
            "T_FALSE"
          when TYPE_SYMBOL
            "T_SYMBOL"
          when TYPE_FIXNUM
            "T_FIXNUM"
          when TYPE_UNDEF
            "T_UNDEF"
          end

        fmt.instruction("checktype", [name])
      end

      def to_a(_iseq)
        [:checktype, type]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        # TODO: This is incorrect. The instruction only pushes a single value
        # onto the stack. However, if this is set to 1, we no longer match the
        # output of RubyVM::InstructionSequence. So leaving this here until we
        # can investigate further.
        2
      end

      def canonical
        self
      end

      def call(vm)
        object = vm.pop
        result =
          case type
          when TYPE_OBJECT
            raise NotImplementedError, "checktype TYPE_OBJECT"
          when TYPE_CLASS
            object.is_a?(Class)
          when TYPE_MODULE
            object.is_a?(Module)
          when TYPE_FLOAT
            object.is_a?(Float)
          when TYPE_STRING
            object.is_a?(String)
          when TYPE_REGEXP
            object.is_a?(Regexp)
          when TYPE_ARRAY
            object.is_a?(Array)
          when TYPE_HASH
            object.is_a?(Hash)
          when TYPE_STRUCT
            object.is_a?(Struct)
          when TYPE_BIGNUM
            raise NotImplementedError, "checktype TYPE_BIGNUM"
          when TYPE_FILE
            object.is_a?(File)
          when TYPE_DATA
            raise NotImplementedError, "checktype TYPE_DATA"
          when TYPE_MATCH
            raise NotImplementedError, "checktype TYPE_MATCH"
          when TYPE_COMPLEX
            object.is_a?(Complex)
          when TYPE_RATIONAL
            object.is_a?(Rational)
          when TYPE_NIL
            object.nil?
          when TYPE_TRUE
            object == true
          when TYPE_FALSE
            object == false
          when TYPE_SYMBOL
            object.is_a?(Symbol)
          when TYPE_FIXNUM
            object.is_a?(Integer)
          when TYPE_UNDEF
            raise NotImplementedError, "checktype TYPE_UNDEF"
          end

        vm.push(result)
      end
    end

    # ### Summary
    #
    # `concatarray` concatenates the two Arrays on top of the stack.
    #
    # It coerces the two objects at the top of the stack into Arrays by
    # calling `to_a` if necessary, and makes sure to `dup` the first Array if
    # it was already an Array, to avoid mutating it when concatenating.
    #
    # ### Usage
    #
    # ~~~ruby
    # [1, *2]
    # ~~~
    #
    class ConcatArray
      def disasm(fmt)
        fmt.instruction("concatarray")
      end

      def to_a(_iseq)
        [:concatarray]
      end

      def length
        1
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        left, right = vm.pop(2)
        vm.push([*left, *right])
      end
    end

    # ### Summary
    #
    # `concatstrings` pops a number of strings from the stack joins them
    # together into a single string and pushes that string back on the stack.
    #
    # This does no coercion and so is always used in conjunction with
    # `objtostring` and `anytostring` to ensure the stack contents are always
    # strings.
    #
    # ### Usage
    #
    # ~~~ruby
    # "#{5}"
    # ~~~
    #
    class ConcatStrings
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def disasm(fmt)
        fmt.instruction("concatstrings", [fmt.object(number)])
      end

      def to_a(_iseq)
        [:concatstrings, number]
      end

      def length
        2
      end

      def pops
        number
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.pop(number).join)
      end
    end

    # ### Summary
    #
    # `defineclass` defines a class. First it pops the superclass off the
    # stack, then it pops the object off the stack that the class should be
    # defined under. It has three arguments: the name of the constant, the
    # instruction sequence associated with the class, and various flags that
    # indicate if it is a singleton class, a module, or a regular class.
    #
    # ### Usage
    #
    # ~~~ruby
    # class Foo
    # end
    # ~~~
    #
    class DefineClass
      TYPE_CLASS = 0
      TYPE_SINGLETON_CLASS = 1
      TYPE_MODULE = 2
      FLAG_SCOPED = 8
      FLAG_HAS_SUPERCLASS = 16

      attr_reader :name, :class_iseq, :flags

      def initialize(name, class_iseq, flags)
        @name = name
        @class_iseq = class_iseq
        @flags = flags
      end

      def disasm(fmt)
        fmt.enqueue(class_iseq)
        fmt.instruction(
          "defineclass",
          [fmt.object(name), class_iseq.name, fmt.object(flags)]
        )
      end

      def to_a(_iseq)
        [:defineclass, name, class_iseq.to_a, flags]
      end

      def length
        4
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        object, superclass = vm.pop(2)
        iseq = class_iseq

        clazz = Class.new(superclass || Object)
        vm.push(vm.run_class_frame(iseq, clazz))

        object.const_set(name, clazz)
      end
    end

    # ### Summary
    #
    # `defined` checks if the top value of the stack is defined. If it is, it
    # pushes its value onto the stack. Otherwise it pushes `nil`.
    #
    # ### Usage
    #
    # ~~~ruby
    # defined?(x)
    # ~~~
    #
    class Defined
      TYPE_NIL = 1
      TYPE_IVAR = 2
      TYPE_LVAR = 3
      TYPE_GVAR = 4
      TYPE_CVAR = 5
      TYPE_CONST = 6
      TYPE_METHOD = 7
      TYPE_YIELD = 8
      TYPE_ZSUPER = 9
      TYPE_SELF = 10
      TYPE_TRUE = 11
      TYPE_FALSE = 12
      TYPE_ASGN = 13
      TYPE_EXPR = 14
      TYPE_REF = 15
      TYPE_FUNC = 16
      TYPE_CONST_FROM = 17

      attr_reader :type, :name, :message

      def initialize(type, name, message)
        @type = type
        @name = name
        @message = message
      end

      def disasm(fmt)
        type_name =
          case type
          when TYPE_NIL
            "nil"
          when TYPE_IVAR
            "ivar"
          when TYPE_LVAR
            "lvar"
          when TYPE_GVAR
            "gvar"
          when TYPE_CVAR
            "cvar"
          when TYPE_CONST
            "const"
          when TYPE_METHOD
            "method"
          when TYPE_YIELD
            "yield"
          when TYPE_ZSUPER
            "zsuper"
          when TYPE_SELF
            "self"
          when TYPE_TRUE
            "true"
          when TYPE_FALSE
            "false"
          when TYPE_ASGN
            "asgn"
          when TYPE_EXPR
            "expr"
          when TYPE_REF
            "ref"
          when TYPE_FUNC
            "func"
          when TYPE_CONST_FROM
            "constant-from"
          end

        fmt.instruction(
          "defined",
          [type_name, fmt.object(name), fmt.object(message)]
        )
      end

      def to_a(_iseq)
        [:defined, type, name, message]
      end

      def length
        4
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        object = vm.pop

        result =
          case type
          when TYPE_NIL, TYPE_SELF, TYPE_TRUE, TYPE_FALSE, TYPE_ASGN, TYPE_EXPR
            message
          when TYPE_IVAR
            message if vm._self.instance_variable_defined?(name)
          when TYPE_LVAR
            raise NotImplementedError, "defined TYPE_LVAR"
          when TYPE_GVAR
            message if global_variables.include?(name)
          when TYPE_CVAR
            clazz = vm._self
            clazz = clazz.singleton_class unless clazz.is_a?(Module)
            message if clazz.class_variable_defined?(name)
          when TYPE_CONST
            raise NotImplementedError, "defined TYPE_CONST"
          when TYPE_METHOD
            raise NotImplementedError, "defined TYPE_METHOD"
          when TYPE_YIELD
            raise NotImplementedError, "defined TYPE_YIELD"
          when TYPE_ZSUPER
            raise NotImplementedError, "defined TYPE_ZSUPER"
          when TYPE_REF
            raise NotImplementedError, "defined TYPE_REF"
          when TYPE_FUNC
            message if object.respond_to?(name, true)
          when TYPE_CONST_FROM
            raise NotImplementedError, "defined TYPE_CONST_FROM"
          end

        vm.push(result)
      end
    end

    # ### Summary
    #
    # `definemethod` defines a method on the class of the current value of
    # `self`. It accepts two arguments. The first is the name of the method
    # being defined. The second is the instruction sequence representing the
    # body of the method.
    #
    # ### Usage
    #
    # ~~~ruby
    # def value = "value"
    # ~~~
    #
    class DefineMethod
      attr_reader :method_name, :method_iseq

      def initialize(method_name, method_iseq)
        @method_name = method_name
        @method_iseq = method_iseq
      end

      def disasm(fmt)
        fmt.enqueue(method_iseq)
        fmt.instruction(
          "definemethod",
          [fmt.object(method_name), method_iseq.name]
        )
      end

      def to_a(_iseq)
        [:definemethod, method_name, method_iseq.to_a]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        name = method_name
        iseq = method_iseq

        vm
          ._self
          .__send__(:define_method, name) do |*args, **kwargs, &block|
            vm.run_method_frame(name, iseq, self, *args, **kwargs, &block)
          end
      end
    end

    # ### Summary
    #
    # `definesmethod` defines a method on the singleton class of the current
    # value of `self`. It accepts two arguments. The first is the name of the
    # method being defined. The second is the instruction sequence representing
    # the body of the method. It pops the object off the stack that the method
    # should be defined on.
    #
    # ### Usage
    #
    # ~~~ruby
    # def self.value = "value"
    # ~~~
    #
    class DefineSMethod
      attr_reader :method_name, :method_iseq

      def initialize(method_name, method_iseq)
        @method_name = method_name
        @method_iseq = method_iseq
      end

      def disasm(fmt)
        fmt.enqueue(method_iseq)
        fmt.instruction(
          "definesmethod",
          [fmt.object(method_name), method_iseq.name]
        )
      end

      def to_a(_iseq)
        [:definesmethod, method_name, method_iseq.to_a]
      end

      def length
        3
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        name = method_name
        iseq = method_iseq

        vm
          ._self
          .__send__(:define_singleton_method, name) do |*args, **kwargs, &block|
            vm.run_method_frame(name, iseq, self, *args, **kwargs, &block)
          end
      end
    end

    # ### Summary
    #
    # `dup` copies the top value of the stack and pushes it onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # $global = 5
    # ~~~
    #
    class Dup
      def disasm(fmt)
        fmt.instruction("dup")
      end

      def to_a(_iseq)
        [:dup]
      end

      def length
        1
      end

      def pops
        1
      end

      def pushes
        2
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.stack.last.dup)
      end
    end

    # ### Summary
    #
    # `duparray` dups an Array literal and pushes it onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # [true]
    # ~~~
    #
    class DupArray
      attr_reader :object

      def initialize(object)
        @object = object
      end

      def disasm(fmt)
        fmt.instruction("duparray", [fmt.object(object)])
      end

      def to_a(_iseq)
        [:duparray, object]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(object.dup)
      end
    end

    # ### Summary
    #
    # `duphash` dups a Hash literal and pushes it onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # { a: 1 }
    # ~~~
    #
    class DupHash
      attr_reader :object

      def initialize(object)
        @object = object
      end

      def disasm(fmt)
        fmt.instruction("duphash", [fmt.object(object)])
      end

      def to_a(_iseq)
        [:duphash, object]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(object.dup)
      end
    end

    # ### Summary
    #
    # `dupn` duplicates the top `n` stack elements.
    #
    # ### Usage
    #
    # ~~~ruby
    # Object::X ||= true
    # ~~~
    #
    class DupN
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def disasm(fmt)
        fmt.instruction("dupn", [fmt.object(number)])
      end

      def to_a(_iseq)
        [:dupn, number]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        number
      end

      def canonical
        self
      end

      def call(vm)
        values = vm.pop(number)
        vm.push(*values)
        vm.push(*values)
      end
    end

    # ### Summary
    #
    # `expandarray` looks at the top of the stack, and if the value is an array
    # it replaces it on the stack with `number` elements of the array, or `nil`
    # if the elements are missing.
    #
    # ### Usage
    #
    # ~~~ruby
    # x, = [true, false, nil]
    # ~~~
    #
    class ExpandArray
      attr_reader :number, :flags

      def initialize(number, flags)
        @number = number
        @flags = flags
      end

      def disasm(fmt)
        fmt.instruction("expandarray", [fmt.object(number), fmt.object(flags)])
      end

      def to_a(_iseq)
        [:expandarray, number, flags]
      end

      def length
        3
      end

      def pops
        1
      end

      def pushes
        number
      end

      def canonical
        self
      end

      def call(vm)
        raise NotImplementedError, "expandarray"
      end
    end

    # ### Summary
    #
    # `getblockparam` is a similar instruction to `getlocal` in that it looks
    # for a local variable in the current instruction sequence's local table and
    # walks recursively up the parent instruction sequences until it finds it.
    # The local it retrieves, however, is a special block local that was passed
    # to the current method. It pushes the value of the block local onto the
    # stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # def foo(&block)
    #   block
    # end
    # ~~~
    #
    class GetBlockParam
      attr_reader :index, :level

      def initialize(index, level)
        @index = index
        @level = level
      end

      def disasm(fmt)
        fmt.instruction("getblockparam", [fmt.local(index, explicit: level)])
      end

      def to_a(iseq)
        current = iseq
        level.times { current = iseq.parent_iseq }
        [:getblockparam, current.local_table.offset(index), level]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.local_get(index, level))
      end
    end

    # ### Summary
    #
    # `getblockparamproxy` is almost the same as `getblockparam` except that it
    # pushes a proxy object onto the stack instead of the actual value of the
    # block local. This is used when a method is being called on the block
    # local.
    #
    # ### Usage
    #
    # ~~~ruby
    # def foo(&block)
    #   block.call
    # end
    # ~~~
    #
    class GetBlockParamProxy
      attr_reader :index, :level

      def initialize(index, level)
        @index = index
        @level = level
      end

      def disasm(fmt)
        fmt.instruction(
          "getblockparamproxy",
          [fmt.local(index, explicit: level)]
        )
      end

      def to_a(iseq)
        current = iseq
        level.times { current = iseq.parent_iseq }
        [:getblockparamproxy, current.local_table.offset(index), level]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.local_get(index, level))
      end
    end

    # ### Summary
    #
    # `getclassvariable` looks for a class variable in the current class and
    # pushes its value onto the stack. It uses an inline cache to reduce the
    # need to lookup the class variable in the class hierarchy every time.
    #
    # ### Usage
    #
    # ~~~ruby
    # @@class_variable
    # ~~~
    #
    class GetClassVariable
      attr_reader :name, :cache

      def initialize(name, cache)
        @name = name
        @cache = cache
      end

      def disasm(fmt)
        fmt.instruction(
          "getclassvariable",
          [fmt.object(name), fmt.inline_storage(cache)]
        )
      end

      def to_a(_iseq)
        [:getclassvariable, name, cache]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        clazz = vm._self
        clazz = clazz.class unless clazz.is_a?(Class)
        vm.push(clazz.class_variable_get(name))
      end
    end

    # ### Summary
    #
    # `getconstant` performs a constant lookup and pushes the value of the
    # constant onto the stack. It pops both the class it should look in and
    # whether or not it should look globally as well.
    #
    # ### Usage
    #
    # ~~~ruby
    # Constant
    # ~~~
    #
    class GetConstant
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def disasm(fmt)
        fmt.instruction("getconstant", [fmt.object(name)])
      end

      def to_a(_iseq)
        [:getconstant, name]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        # const_base, allow_nil =
        vm.pop(2)

        vm.frame.nesting.reverse_each do |clazz|
          if clazz.const_defined?(name)
            vm.push(clazz.const_get(name))
            return
          end
        end

        raise NameError, "uninitialized constant #{name}"
      end
    end

    # ### Summary
    #
    # `getglobal` pushes the value of a global variables onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # $$
    # ~~~
    #
    class GetGlobal
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def disasm(fmt)
        fmt.instruction("getglobal", [fmt.object(name)])
      end

      def to_a(_iseq)
        [:getglobal, name]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        # Evaluating the name of the global variable because there isn't a
        # reflection API for global variables.
        vm.push(eval(name.to_s, binding, __FILE__, __LINE__))
      end
    end

    # ### Summary
    #
    # `getinstancevariable` pushes the value of an instance variable onto the
    # stack. It uses an inline cache to avoid having to look up the instance
    # variable in the class hierarchy every time.
    #
    # This instruction has two forms, but both have the same structure. Before
    # Ruby 3.2, the inline cache corresponded to both the get and set
    # instructions and could be shared. Since Ruby 3.2, it uses object shapes
    # instead so the caches are unique per instruction.
    #
    # ### Usage
    #
    # ~~~ruby
    # @instance_variable
    # ~~~
    #
    class GetInstanceVariable
      attr_reader :name, :cache

      def initialize(name, cache)
        @name = name
        @cache = cache
      end

      def disasm(fmt)
        fmt.instruction(
          "getinstancevariable",
          [fmt.object(name), fmt.inline_storage(cache)]
        )
      end

      def to_a(_iseq)
        [:getinstancevariable, name, cache]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        method = Object.instance_method(:instance_variable_get)
        vm.push(method.bind(vm._self).call(name))
      end
    end

    # ### Summary
    #
    # `getlocal` fetches the value of a local variable from a frame determined
    # by the level and index arguments. The level is the number of frames back
    # to look and the index is the index in the local table. It pushes the value
    # it finds onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # value = 5
    # tap { tap { value } }
    # ~~~
    #
    class GetLocal
      attr_reader :index, :level

      def initialize(index, level)
        @index = index
        @level = level
      end

      def disasm(fmt)
        fmt.instruction("getlocal", [fmt.local(index, explicit: level)])
      end

      def to_a(iseq)
        current = iseq
        level.times { current = current.parent_iseq }
        [:getlocal, current.local_table.offset(index), level]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.local_get(index, level))
      end
    end

    # ### Summary
    #
    # `getlocal_WC_0` is a specialized version of the `getlocal` instruction. It
    # fetches the value of a local variable from the current frame determined by
    # the index given as its only argument.
    #
    # ### Usage
    #
    # ~~~ruby
    # value = 5
    # value
    # ~~~
    #
    class GetLocalWC0
      attr_reader :index

      def initialize(index)
        @index = index
      end

      def disasm(fmt)
        fmt.instruction("getlocal_WC_0", [fmt.local(index, implicit: 0)])
      end

      def to_a(iseq)
        [:getlocal_WC_0, iseq.local_table.offset(index)]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        GetLocal.new(index, 0)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `getlocal_WC_1` is a specialized version of the `getlocal` instruction. It
    # fetches the value of a local variable from the parent frame determined by
    # the index given as its only argument.
    #
    # ### Usage
    #
    # ~~~ruby
    # value = 5
    # self.then { value }
    # ~~~
    #
    class GetLocalWC1
      attr_reader :index

      def initialize(index)
        @index = index
      end

      def disasm(fmt)
        fmt.instruction("getlocal_WC_1", [fmt.local(index, implicit: 1)])
      end

      def to_a(iseq)
        [:getlocal_WC_1, iseq.parent_iseq.local_table.offset(index)]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        GetLocal.new(index, 1)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `getspecial` pushes the value of a special local variable onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # 1 if (a == 1) .. (b == 2)
    # ~~~
    #
    class GetSpecial
      SVAR_LASTLINE = 0 # $_
      SVAR_BACKREF = 1 # $~
      SVAR_FLIPFLOP_START = 2 # flipflop

      attr_reader :key, :type

      def initialize(key, type)
        @key = key
        @type = type
      end

      def disasm(fmt)
        fmt.instruction("getspecial", [fmt.object(key), fmt.object(type)])
      end

      def to_a(_iseq)
        [:getspecial, key, type]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        case key
        when SVAR_LASTLINE
          raise NotImplementedError, "getspecial SVAR_LASTLINE"
        when SVAR_BACKREF
          raise NotImplementedError, "getspecial SVAR_BACKREF"
        when SVAR_FLIPFLOP_START
          vm.frame_svar.svars[SVAR_FLIPFLOP_START]
        end
      end
    end

    # ### Summary
    #
    # `intern` converts the top element of the stack to a symbol and pushes the
    # symbol onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # :"#{"foo"}"
    # ~~~
    #
    class Intern
      def disasm(fmt)
        fmt.instruction("intern")
      end

      def to_a(_iseq)
        [:intern]
      end

      def length
        1
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.pop.to_sym)
      end
    end

    # ### Summary
    #
    # `invokeblock` invokes the block given to the current method. It pops the
    # arguments for the block off the stack and pushes the result of running the
    # block onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # def foo
    #   yield
    # end
    # ~~~
    #
    class InvokeBlock
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("invokeblock", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:invokeblock, calldata.to_h]
      end

      def length
        2
      end

      def pops
        calldata.argc
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.frame_yield.block.call(*vm.pop(calldata.argc)))
      end
    end

    # ### Summary
    #
    # `invokesuper` is similar to the `send` instruction, except that it calls
    # the super method. It pops the receiver and arguments off the stack and
    # pushes the return value onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # def foo
    #   super
    # end
    # ~~~
    #
    class InvokeSuper
      attr_reader :calldata, :block_iseq

      def initialize(calldata, block_iseq)
        @calldata = calldata
        @block_iseq = block_iseq
      end

      def disasm(fmt)
        fmt.enqueue(block_iseq) if block_iseq
        fmt.instruction(
          "invokesuper",
          [fmt.calldata(calldata), block_iseq&.name || "nil"]
        )
      end

      def to_a(_iseq)
        [:invokesuper, calldata.to_h, block_iseq&.to_a]
      end

      def length
        1
      end

      def pops
        argb = (calldata.flag?(CallData::CALL_ARGS_BLOCKARG) ? 1 : 0)
        argb + calldata.argc + 1
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        block =
          if (iseq = block_iseq)
            ->(*args, **kwargs, &blk) do
              vm.run_block_frame(iseq, *args, **kwargs, &blk)
            end
          end

        keywords =
          if calldata.kw_arg
            calldata.kw_arg.zip(vm.pop(calldata.kw_arg.length)).to_h
          else
            {}
          end

        arguments = vm.pop(calldata.argc)
        receiver = vm.pop

        method = receiver.method(vm.frame.name).super_method
        vm.push(method.call(*arguments, **keywords, &block))
      end
    end

    # ### Summary
    #
    # `jump` unconditionally jumps to the label given as its only argument.
    #
    # ### Usage
    #
    # ~~~ruby
    # x = 0
    # if x == 0
    #   puts "0"
    # else
    #   puts "2"
    # end
    # ~~~
    #
    class Jump
      attr_reader :label

      def initialize(label)
        @label = label
      end

      def disasm(fmt)
        fmt.instruction("jump", [fmt.label(label)])
      end

      def to_a(_iseq)
        [:jump, label.name]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        vm.jump(label)
      end
    end

    # ### Summary
    #
    # `leave` exits the current frame.
    #
    # ### Usage
    #
    # ~~~ruby
    # ;;
    # ~~~
    #
    class Leave
      def disasm(fmt)
        fmt.instruction("leave")
      end

      def to_a(_iseq)
        [:leave]
      end

      def length
        1
      end

      def pops
        1
      end

      def pushes
        # TODO: This is wrong. It should be 1. But it's 0 for now because
        # otherwise the stack size is incorrectly calculated.
        0
      end

      def canonical
        self
      end

      def call(vm)
        vm.leave
      end
    end

    # ### Summary
    #
    # `newarray` puts a new array initialized with `number` values from the
    # stack. It pops `number` values off the stack and pushes the array onto the
    # stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # ["string"]
    # ~~~
    #
    class NewArray
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def disasm(fmt)
        fmt.instruction("newarray", [fmt.object(number)])
      end

      def to_a(_iseq)
        [:newarray, number]
      end

      def length
        2
      end

      def pops
        number
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.pop(number))
      end
    end

    # ### Summary
    #
    # `newarraykwsplat` is a specialized version of `newarray` that takes a **
    # splat argument. It pops `number` values off the stack and pushes the array
    # onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # ["string", **{ foo: "bar" }]
    # ~~~
    #
    class NewArrayKwSplat
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def disasm(fmt)
        fmt.instruction("newarraykwsplat", [fmt.object(number)])
      end

      def to_a(_iseq)
        [:newarraykwsplat, number]
      end

      def length
        2
      end

      def pops
        number
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.pop(number))
      end
    end

    # ### Summary
    #
    # `newhash` puts a new hash onto the stack, using `number` elements from the
    # stack. `number` needs to be even. It pops `number` elements off the stack
    # and pushes a hash onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # def foo(key, value)
    #   { key => value }
    # end
    # ~~~
    #
    class NewHash
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def disasm(fmt)
        fmt.instruction("newhash", [fmt.object(number)])
      end

      def to_a(_iseq)
        [:newhash, number]
      end

      def length
        2
      end

      def pops
        number
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.pop(number).each_slice(2).to_h)
      end
    end

    # ### Summary
    #
    # `newrange` creates a new range object from the top two values on the
    # stack. It pops both of them off, and then pushes on the new range. It
    # takes one argument which is 0 if the end is included or 1 if the end value
    # is excluded.
    #
    # ### Usage
    #
    # ~~~ruby
    # x = 0
    # y = 1
    # p (x..y), (x...y)
    # ~~~
    #
    class NewRange
      attr_reader :exclude_end

      def initialize(exclude_end)
        @exclude_end = exclude_end
      end

      def disasm(fmt)
        fmt.instruction("newrange", [fmt.object(exclude_end)])
      end

      def to_a(_iseq)
        [:newrange, exclude_end]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(Range.new(*vm.pop(2), exclude_end == 1))
      end
    end

    # ### Summary
    #
    # `nop` is a no-operation instruction. It is used to pad the instruction
    # sequence so there is a place for other instructions to jump to.
    #
    # ### Usage
    #
    # ~~~ruby
    # raise rescue true
    # ~~~
    #
    class Nop
      def disasm(fmt)
        fmt.instruction("nop")
      end

      def to_a(_iseq)
        [:nop]
      end

      def length
        1
      end

      def pops
        0
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
      end
    end

    # ### Summary
    #
    # `objtostring` pops a value from the stack, calls `to_s` on that value and
    # then pushes the result back to the stack.
    #
    # It has various fast paths for classes like String, Symbol, Module, Class,
    # etc. For everything else it calls `to_s`.
    #
    # ### Usage
    #
    # ~~~ruby
    # "#{5}"
    # ~~~
    #
    class ObjToString
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("objtostring", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:objtostring, calldata.to_h]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.pop.to_s)
      end
    end

    # ### Summary
    #
    # `once` is an instruction that wraps an instruction sequence and ensures
    # that is it only ever executed once for the lifetime of the program. It
    # uses a cache to ensure that it is only executed once. It pushes the result
    # of running the instruction sequence onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # END { puts "END" }
    # ~~~
    #
    class Once
      attr_reader :iseq, :cache

      def initialize(iseq, cache)
        @iseq = iseq
        @cache = cache
      end

      def disasm(fmt)
        fmt.enqueue(iseq)
        fmt.instruction("once", [iseq.name, fmt.inline_storage(cache)])
      end

      def to_a(_iseq)
        [:once, iseq.to_a, cache]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        return if @executed
        vm.push(vm.run_block_frame(iseq))
        @executed = true
      end
    end

    # ### Summary
    #
    # `opt_and` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the `&` operator is used. There is a fast path for if
    # both operands are integers. It pops both the receiver and the argument off
    # the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 2 & 3
    # ~~~
    #
    class OptAnd
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_and", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_and, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_aref` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the `[]` operator is used. There are fast paths if the
    # receiver is an integer, array, or hash.
    #
    # ### Usage
    #
    # ~~~ruby
    # 7[2]
    # ~~~
    #
    class OptAref
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_aref", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_aref, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_aref_with` is a specialization of the `opt_aref` instruction that
    # occurs when the `[]` operator is used with a string argument known at
    # compile time. There are fast paths if the receiver is a hash. It pops the
    # receiver off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # { 'test' => true }['test']
    # ~~~
    #
    class OptArefWith
      attr_reader :object, :calldata

      def initialize(object, calldata)
        @object = object
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction(
          "opt_aref_with",
          [fmt.object(object), fmt.calldata(calldata)]
        )
      end

      def to_a(_iseq)
        [:opt_aref_with, object, calldata.to_h]
      end

      def length
        3
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.pop[object])
      end
    end

    # ### Summary
    #
    # `opt_aset` is an instruction for setting the hash value by the key in
    # the `recv[obj] = set` format. It is a specialization of the
    # `opt_send_without_block` instruction. It pops the receiver, the key, and
    # the value off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # {}[:key] = value
    # ~~~
    #
    class OptAset
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_aset", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_aset, calldata.to_h]
      end

      def length
        2
      end

      def pops
        3
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_aset_with` is an instruction for setting the hash value by the known
    # string key in the `recv[obj] = set` format. It pops the receiver and the
    # value off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # {}["key"] = value
    # ~~~
    #
    class OptAsetWith
      attr_reader :object, :calldata

      def initialize(object, calldata)
        @object = object
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction(
          "opt_aset_with",
          [fmt.object(object), fmt.calldata(calldata)]
        )
      end

      def to_a(_iseq)
        [:opt_aset_with, object, calldata.to_h]
      end

      def length
        3
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        hash, value = vm.pop(2)
        vm.push(hash[object] = value)
      end
    end

    # ### Summary
    #
    # `opt_case_dispatch` is a branch instruction that moves the control flow
    # for case statements that have clauses where they can all be used as hash
    # keys for an internal hash.
    #
    # It has two arguments: the `case_dispatch_hash` and an `else_label`. It
    # pops one value off the stack: a hash key. `opt_case_dispatch` looks up the
    # key in the `case_dispatch_hash` and jumps to the corresponding label if
    # there is one. If there is no value in the `case_dispatch_hash`,
    # `opt_case_dispatch` jumps to the `else_label` index.
    #
    # ### Usage
    #
    # ~~~ruby
    # case 1
    # when 1
    #   puts "foo"
    # else
    #   puts "bar"
    # end
    # ~~~
    #
    class OptCaseDispatch
      attr_reader :case_dispatch_hash, :else_label

      def initialize(case_dispatch_hash, else_label)
        @case_dispatch_hash = case_dispatch_hash
        @else_label = else_label
      end

      def disasm(fmt)
        fmt.instruction(
          "opt_case_dispatch",
          ["<cdhash>", fmt.label(else_label)]
        )
      end

      def to_a(_iseq)
        [
          :opt_case_dispatch,
          case_dispatch_hash.flat_map { |key, value| [key, value.name] },
          else_label.name
        ]
      end

      def length
        3
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        vm.jump(case_dispatch_hash.fetch(vm.pop, else_label))
      end
    end

    # ### Summary
    #
    # `opt_div` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the `/` operator is used. There are fast paths for if
    # both operands are integers, or if both operands are floats. It pops both
    # the receiver and the argument off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 2 / 3
    # ~~~
    #
    class OptDiv
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_div", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_div, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_empty_p` is an optimization applied when the method `empty?` is
    # called. It pops the receiver off the stack and pushes on the result of the
    # method call.
    #
    # ### Usage
    #
    # ~~~ruby
    # "".empty?
    # ~~~
    #
    class OptEmptyP
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_empty_p", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_empty_p, calldata.to_h]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_eq` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the == operator is used. Fast paths exist when both
    # operands are integers, floats, symbols or strings. It pops both the
    # receiver and the argument off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 2 == 2
    # ~~~
    #
    class OptEq
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_eq", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_eq, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_ge` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the >= operator is used. Fast paths exist when both
    # operands are integers or floats. It pops both the receiver and the
    # argument off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 4 >= 3
    # ~~~
    #
    class OptGE
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_ge", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_ge, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_getconstant_path` performs a constant lookup on a chain of constant
    # names. It accepts as its argument an array of constant names, and pushes
    # the value of the constant onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # ::Object
    # ~~~
    #
    class OptGetConstantPath
      attr_reader :names

      def initialize(names)
        @names = names
      end

      def disasm(fmt)
        cache = "<ic:0 #{names.join("::")}>"
        fmt.instruction("opt_getconstant_path", [cache])
      end

      def to_a(_iseq)
        [:opt_getconstant_path, names]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        current = vm._self
        current = current.class unless current.is_a?(Class)

        names.each do |name|
          current = name == :"" ? Object : current.const_get(name)
        end

        vm.push(current)
      end
    end

    # ### Summary
    #
    # `opt_gt` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the > operator is used. Fast paths exist when both
    # operands are integers or floats. It pops both the receiver and the
    # argument off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 4 > 3
    # ~~~
    #
    class OptGT
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_gt", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_gt, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_le` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the <= operator is used. Fast paths exist when both
    # operands are integers or floats. It pops both the receiver and the
    # argument off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 3 <= 4
    # ~~~
    #
    class OptLE
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_le", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_le, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_length` is a specialization of `opt_send_without_block`, when the
    # `length` method is called. There are fast paths when the receiver is
    # either a string, hash, or array. It pops the receiver off the stack and
    # pushes on the result of the method call.
    #
    # ### Usage
    #
    # ~~~ruby
    # "".length
    # ~~~
    #
    class OptLength
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_length", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_length, calldata.to_h]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_lt` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the < operator is used. Fast paths exist when both
    # operands are integers or floats. It pops both the receiver and the
    # argument off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 3 < 4
    # ~~~
    #
    class OptLT
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_lt", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_lt, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_ltlt` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the `<<` operator is used. Fast paths exists when the
    # receiver is either a String or an Array. It pops both the receiver and the
    # argument off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # "" << 2
    # ~~~
    #
    class OptLTLT
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_ltlt", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_ltlt, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_minus` is a specialization of the `opt_send_without_block`
    # instruction that occurs when the `-` operator is used. There are fast
    # paths for if both operands are integers or if both operands are floats. It
    # pops both the receiver and the argument off the stack and pushes on the
    # result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 3 - 2
    # ~~~
    #
    class OptMinus
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_minus", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_minus, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_mod` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the `%` operator is used. There are fast paths for if
    # both operands are integers or if both operands are floats. It pops both
    # the receiver and the argument off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 4 % 2
    # ~~~
    #
    class OptMod
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_mod", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_mod, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_mult` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the `*` operator is used. There are fast paths for if
    # both operands are integers or floats. It pops both the receiver and the
    # argument off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 3 * 2
    # ~~~
    #
    class OptMult
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_mult", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_mult, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_neq` is an optimization that tests whether two values at the top of
    # the stack are not equal by testing their equality and calling the `!` on
    # the result. This allows `opt_neq` to use the fast paths optimized in
    # `opt_eq` when both operands are Integers, Floats, Symbols, or Strings. It
    # pops both the receiver and the argument off the stack and pushes on the
    # result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 2 != 2
    # ~~~
    #
    class OptNEq
      attr_reader :eq_calldata, :neq_calldata

      def initialize(eq_calldata, neq_calldata)
        @eq_calldata = eq_calldata
        @neq_calldata = neq_calldata
      end

      def disasm(fmt)
        fmt.instruction(
          "opt_neq",
          [fmt.calldata(eq_calldata), fmt.calldata(neq_calldata)]
        )
      end

      def to_a(_iseq)
        [:opt_neq, eq_calldata.to_h, neq_calldata.to_h]
      end

      def length
        3
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        receiver, argument = vm.pop(2)
        vm.push(receiver != argument)
      end
    end

    # ### Summary
    #
    # `opt_newarray_max` is a specialization that occurs when the `max` method
    # is called on an array literal. It pops the values of the array off the
    # stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # [a, b, c].max
    # ~~~
    #
    class OptNewArrayMax
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def disasm(fmt)
        fmt.instruction("opt_newarray_max", [fmt.object(number)])
      end

      def to_a(_iseq)
        [:opt_newarray_max, number]
      end

      def length
        2
      end

      def pops
        number
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.pop(number).max)
      end
    end

    # ### Summary
    #
    # `opt_newarray_min` is a specialization that occurs when the `min` method
    # is called on an array literal. It pops the values of the array off the
    # stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # [a, b, c].min
    # ~~~
    #
    class OptNewArrayMin
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def disasm(fmt)
        fmt.instruction("opt_newarray_min", [fmt.object(number)])
      end

      def to_a(_iseq)
        [:opt_newarray_min, number]
      end

      def length
        2
      end

      def pops
        number
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.pop(number).min)
      end
    end

    # ### Summary
    #
    # `opt_nil_p` is an optimization applied when the method `nil?` is called.
    # It returns true immediately when the receiver is `nil` and defers to the
    # `nil?` method in other cases. It pops the receiver off the stack and
    # pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # "".nil?
    # ~~~
    #
    class OptNilP
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_nil_p", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_nil_p, calldata.to_h]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_not` negates the value on top of the stack by calling the `!` method
    # on it. It pops the receiver off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # !true
    # ~~~
    #
    class OptNot
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_not", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_not, calldata.to_h]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_or` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the `|` operator is used. There is a fast path for if
    # both operands are integers. It pops both the receiver and the argument off
    # the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 2 | 3
    # ~~~
    #
    class OptOr
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_or", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_or, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_plus` is a specialization of the `opt_send_without_block` instruction
    # that occurs when the `+` operator is used. There are fast paths for if
    # both operands are integers, floats, strings, or arrays. It pops both the
    # receiver and the argument off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # 2 + 3
    # ~~~
    #
    class OptPlus
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_plus", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_plus, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_regexpmatch2` is a specialization of the `opt_send_without_block`
    # instruction that occurs when the `=~` operator is used. It pops both the
    # receiver and the argument off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # /a/ =~ "a"
    # ~~~
    #
    class OptRegExpMatch2
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_regexpmatch2", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_regexpmatch2, calldata.to_h]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_send_without_block` is a specialization of the send instruction that
    # occurs when a method is being called without a block. It pops the receiver
    # and the arguments off the stack and pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # puts "Hello, world!"
    # ~~~
    #
    class OptSendWithoutBlock
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_send_without_block", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_send_without_block, calldata.to_h]
      end

      def length
        2
      end

      def pops
        1 + calldata.argc
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_size` is a specialization of `opt_send_without_block`, when the
    # `size` method is called. There are fast paths when the receiver is either
    # a string, hash, or array. It pops the receiver off the stack and pushes on
    # the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # "".size
    # ~~~
    #
    class OptSize
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_size", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_size, calldata.to_h]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `opt_str_freeze` pushes a frozen known string value with no interpolation
    # onto the stack using the #freeze method. If the method gets overridden,
    # this will fall back to a send.
    #
    # ### Usage
    #
    # ~~~ruby
    # "hello".freeze
    # ~~~
    #
    class OptStrFreeze
      attr_reader :object, :calldata

      def initialize(object, calldata)
        @object = object
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction(
          "opt_str_freeze",
          [fmt.object(object), fmt.calldata(calldata)]
        )
      end

      def to_a(_iseq)
        [:opt_str_freeze, object, calldata.to_h]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(object.freeze)
      end
    end

    # ### Summary
    #
    # `opt_str_uminus` pushes a frozen known string value with no interpolation
    # onto the stack. If the method gets overridden, this will fall back to a
    # send.
    #
    # ### Usage
    #
    # ~~~ruby
    # -"string"
    # ~~~
    #
    class OptStrUMinus
      attr_reader :object, :calldata

      def initialize(object, calldata)
        @object = object
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction(
          "opt_str_uminus",
          [fmt.object(object), fmt.calldata(calldata)]
        )
      end

      def to_a(_iseq)
        [:opt_str_uminus, object, calldata.to_h]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(-object)
      end
    end

    # ### Summary
    #
    # `opt_succ` is a specialization of the `opt_send_without_block` instruction
    # when the method being called is `succ`. Fast paths exist when the receiver
    # is either a String or a Fixnum. It pops the receiver off the stack and
    # pushes on the result.
    #
    # ### Usage
    #
    # ~~~ruby
    # "".succ
    # ~~~
    #
    class OptSucc
      attr_reader :calldata

      def initialize(calldata)
        @calldata = calldata
      end

      def disasm(fmt)
        fmt.instruction("opt_succ", [fmt.calldata(calldata)])
      end

      def to_a(_iseq)
        [:opt_succ, calldata.to_h]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        Send.new(calldata, nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `pop` pops the top value off the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # a ||= 2
    # ~~~
    #
    class Pop
      def disasm(fmt)
        fmt.instruction("pop")
      end

      def to_a(_iseq)
        [:pop]
      end

      def length
        1
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        vm.pop
      end
    end

    # ### Summary
    #
    # `putnil` pushes a global nil object onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # nil
    # ~~~
    #
    class PutNil
      def disasm(fmt)
        fmt.instruction("putnil")
      end

      def to_a(_iseq)
        [:putnil]
      end

      def length
        1
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        PutObject.new(nil)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `putobject` pushes a known value onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # 5
    # ~~~
    #
    class PutObject
      attr_reader :object

      def initialize(object)
        @object = object
      end

      def disasm(fmt)
        fmt.instruction("putobject", [fmt.object(object)])
      end

      def to_a(_iseq)
        [:putobject, object]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(object)
      end
    end

    # ### Summary
    #
    # `putobject_INT2FIX_0_` pushes 0 on the stack. It is a specialized
    # instruction resulting from the operand unification optimization. It is
    # equivalent to `putobject 0`.
    #
    # ### Usage
    #
    # ~~~ruby
    # 0
    # ~~~
    #
    class PutObjectInt2Fix0
      def disasm(fmt)
        fmt.instruction("putobject_INT2FIX_0_")
      end

      def to_a(_iseq)
        [:putobject_INT2FIX_0_]
      end

      def length
        1
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        PutObject.new(0)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `putobject_INT2FIX_1_` pushes 1 on the stack. It is a specialized
    # instruction resulting from the operand unification optimization. It is
    # equivalent to `putobject 1`.
    #
    # ### Usage
    #
    # ~~~ruby
    # 1
    # ~~~
    #
    class PutObjectInt2Fix1
      def disasm(fmt)
        fmt.instruction("putobject_INT2FIX_1_")
      end

      def to_a(_iseq)
        [:putobject_INT2FIX_1_]
      end

      def length
        1
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        PutObject.new(1)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `putself` pushes the current value of self onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # puts "Hello, world!"
    # ~~~
    #
    class PutSelf
      def disasm(fmt)
        fmt.instruction("putself")
      end

      def to_a(_iseq)
        [:putself]
      end

      def length
        1
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm._self)
      end
    end

    # ### Summary
    #
    # `putspecialobject` pushes one of three special objects onto the stack.
    # These are either the VM core special object, the class base special
    # object, or the constant base special object.
    #
    # ### Usage
    #
    # ~~~ruby
    # alias foo bar
    # ~~~
    #
    class PutSpecialObject
      OBJECT_VMCORE = 1
      OBJECT_CBASE = 2
      OBJECT_CONST_BASE = 3

      attr_reader :object

      def initialize(object)
        @object = object
      end

      def disasm(fmt)
        fmt.instruction("putspecialobject", [fmt.object(object)])
      end

      def to_a(_iseq)
        [:putspecialobject, object]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        case object
        when OBJECT_VMCORE
          vm.push(vm.frozen_core)
        when OBJECT_CBASE
          value = vm._self
          value = value.singleton_class unless value.is_a?(Class)
          vm.push(value)
        when OBJECT_CONST_BASE
          vm.push(vm.const_base)
        end
      end
    end

    # ### Summary
    #
    # `putstring` pushes an unfrozen string literal onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # "foo"
    # ~~~
    #
    class PutString
      attr_reader :object

      def initialize(object)
        @object = object
      end

      def disasm(fmt)
        fmt.instruction("putstring", [fmt.object(object)])
      end

      def to_a(_iseq)
        [:putstring, object]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(object.dup)
      end
    end

    # ### Summary
    #
    # `send` invokes a method with an optional block. It pops its receiver and
    # the arguments for the method off the stack and pushes the return value
    # onto the stack. It has two arguments: the calldata for the call site and
    # the optional block instruction sequence.
    #
    # ### Usage
    #
    # ~~~ruby
    # "hello".tap { |i| p i }
    # ~~~
    #
    class Send
      attr_reader :calldata, :block_iseq

      def initialize(calldata, block_iseq)
        @calldata = calldata
        @block_iseq = block_iseq
      end

      def disasm(fmt)
        fmt.enqueue(block_iseq) if block_iseq
        fmt.instruction(
          "send",
          [fmt.calldata(calldata), block_iseq&.name || "nil"]
        )
      end

      def to_a(_iseq)
        [:send, calldata.to_h, block_iseq&.to_a]
      end

      def length
        3
      end

      def pops
        argb = (calldata.flag?(CallData::CALL_ARGS_BLOCKARG) ? 1 : 0)
        argb + calldata.argc + 1
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        block =
          if (iseq = block_iseq)
            ->(*args, **kwargs, &blk) do
              vm.run_block_frame(iseq, *args, **kwargs, &blk)
            end
          end

        keywords =
          if calldata.kw_arg
            calldata.kw_arg.zip(vm.pop(calldata.kw_arg.length)).to_h
          else
            {}
          end

        arguments = vm.pop(calldata.argc)
        receiver = vm.pop

        vm.push(
          receiver.__send__(calldata.method, *arguments, **keywords, &block)
        )
      end
    end

    # ### Summary
    #
    # `setblockparam` sets the value of a block local variable on a frame
    # determined by the level and index arguments. The level is the number of
    # frames back to look and the index is the index in the local table. It pops
    # the value it is setting off the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # def foo(&bar)
    #   bar = baz
    # end
    # ~~~
    #
    class SetBlockParam
      attr_reader :index, :level

      def initialize(index, level)
        @index = index
        @level = level
      end

      def disasm(fmt)
        fmt.instruction("setblockparam", [fmt.local(index, explicit: level)])
      end

      def to_a(iseq)
        current = iseq
        level.times { current = current.parent_iseq }
        [:setblockparam, current.local_table.offset(index), level]
      end

      def length
        3
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        vm.local_set(index, level, vm.pop)
      end
    end

    # ### Summary
    #
    # `setclassvariable` looks for a class variable in the current class and
    # sets its value to the value it pops off the top of the stack. It uses an
    # inline cache to reduce the need to lookup the class variable in the class
    # hierarchy every time.
    #
    # ### Usage
    #
    # ~~~ruby
    # @@class_variable = 1
    # ~~~
    #
    class SetClassVariable
      attr_reader :name, :cache

      def initialize(name, cache)
        @name = name
        @cache = cache
      end

      def disasm(fmt)
        fmt.instruction(
          "setclassvariable",
          [fmt.object(name), fmt.inline_storage(cache)]
        )
      end

      def to_a(_iseq)
        [:setclassvariable, name, cache]
      end

      def length
        3
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        clazz = vm._self
        clazz = clazz.class unless clazz.is_a?(Class)
        clazz.class_variable_set(name, vm.pop)
      end
    end

    # ### Summary
    #
    # `setconstant` pops two values off the stack: the value to set the
    # constant to and the constant base to set it in.
    #
    # ### Usage
    #
    # ~~~ruby
    # Constant = 1
    # ~~~
    #
    class SetConstant
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def disasm(fmt)
        fmt.instruction("setconstant", [fmt.object(name)])
      end

      def to_a(_iseq)
        [:setconstant, name]
      end

      def length
        2
      end

      def pops
        2
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        value, parent = vm.pop(2)
        parent.const_set(name, value)
      end
    end

    # ### Summary
    #
    # `setglobal` sets the value of a global variable to a value popped off the
    # top of the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # $global = 5
    # ~~~
    #
    class SetGlobal
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def disasm(fmt)
        fmt.instruction("setglobal", [fmt.object(name)])
      end

      def to_a(_iseq)
        [:setglobal, name]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        # Evaluating the name of the global variable because there isn't a
        # reflection API for global variables.
        eval("#{name} = vm.pop", binding, __FILE__, __LINE__)
      end
    end

    # ### Summary
    #
    # `setinstancevariable` pops a value off the top of the stack and then sets
    # the instance variable associated with the instruction to that value.
    #
    # This instruction has two forms, but both have the same structure. Before
    # Ruby 3.2, the inline cache corresponded to both the get and set
    # instructions and could be shared. Since Ruby 3.2, it uses object shapes
    # instead so the caches are unique per instruction.
    #
    # ### Usage
    #
    # ~~~ruby
    # @instance_variable = 1
    # ~~~
    #
    class SetInstanceVariable
      attr_reader :name, :cache

      def initialize(name, cache)
        @name = name
        @cache = cache
      end

      def disasm(fmt)
        fmt.instruction(
          "setinstancevariable",
          [fmt.object(name), fmt.inline_storage(cache)]
        )
      end

      def to_a(_iseq)
        [:setinstancevariable, name, cache]
      end

      def length
        3
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        method = Object.instance_method(:instance_variable_set)
        method.bind(vm._self).call(name, vm.pop)
      end
    end

    # ### Summary
    #
    # `setlocal` sets the value of a local variable on a frame determined by the
    # level and index arguments. The level is the number of frames back to
    # look and the index is the index in the local table. It pops the value it
    # is setting off the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # value = 5
    # tap { tap { value = 10 } }
    # ~~~
    #
    class SetLocal
      attr_reader :index, :level

      def initialize(index, level)
        @index = index
        @level = level
      end

      def disasm(fmt)
        fmt.instruction("setlocal", [fmt.local(index, explicit: level)])
      end

      def to_a(iseq)
        current = iseq
        level.times { current = current.parent_iseq }
        [:setlocal, current.local_table.offset(index), level]
      end

      def length
        3
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        vm.local_set(index, level, vm.pop)
      end
    end

    # ### Summary
    #
    # `setlocal_WC_0` is a specialized version of the `setlocal` instruction. It
    # sets the value of a local variable on the current frame to the value at
    # the top of the stack as determined by the index given as its only
    # argument.
    #
    # ### Usage
    #
    # ~~~ruby
    # value = 5
    # ~~~
    #
    class SetLocalWC0
      attr_reader :index

      def initialize(index)
        @index = index
      end

      def disasm(fmt)
        fmt.instruction("setlocal_WC_0", [fmt.local(index, implicit: 0)])
      end

      def to_a(iseq)
        [:setlocal_WC_0, iseq.local_table.offset(index)]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        SetLocal.new(index, 0)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `setlocal_WC_1` is a specialized version of the `setlocal` instruction. It
    # sets the value of a local variable on the parent frame to the value at the
    # top of the stack as determined by the index given as its only argument.
    #
    # ### Usage
    #
    # ~~~ruby
    # value = 5
    # self.then { value = 10 }
    # ~~~
    #
    class SetLocalWC1
      attr_reader :index

      def initialize(index)
        @index = index
      end

      def disasm(fmt)
        fmt.instruction("setlocal_WC_1", [fmt.local(index, implicit: 1)])
      end

      def to_a(iseq)
        [:setlocal_WC_1, iseq.parent_iseq.local_table.offset(index)]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        SetLocal.new(index, 1)
      end

      def call(vm)
        canonical.call(vm)
      end
    end

    # ### Summary
    #
    # `setn` sets a value in the stack to a value popped off the top of the
    # stack. It then pushes that value onto the top of the stack as well.
    #
    # ### Usage
    #
    # ~~~ruby
    # {}[:key] = 'val'
    # ~~~
    #
    class SetN
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def disasm(fmt)
        fmt.instruction("setn", [fmt.object(number)])
      end

      def to_a(_iseq)
        [:setn, number]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.stack[-number - 1] = vm.stack.last
      end
    end

    # ### Summary
    #
    # `setspecial` pops a value off the top of the stack and sets a special
    # local variable to that value. The special local variable is determined by
    # the key given as its only argument.
    #
    # ### Usage
    #
    # ~~~ruby
    # baz if (foo == 1) .. (bar == 1)
    # ~~~
    #
    class SetSpecial
      attr_reader :key

      def initialize(key)
        @key = key
      end

      def disasm(fmt)
        fmt.instruction("setspecial", [fmt.object(key)])
      end

      def to_a(_iseq)
        [:setspecial, key]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        0
      end

      def canonical
        self
      end

      def call(vm)
        case key
        when GetSpecial::SVAR_LASTLINE
          raise NotImplementedError, "svar SVAR_LASTLINE"
        when GetSpecial::SVAR_BACKREF
          raise NotImplementedError, "setspecial SVAR_BACKREF"
        when GetSpecial::SVAR_FLIPFLOP_START
          vm.frame_svar.svars[GetSpecial::SVAR_FLIPFLOP_START]
        end
      end
    end

    # ### Summary
    #
    # `splatarray` coerces the array object at the top of the stack into Array
    # by calling `to_a`. It pushes a duplicate of the array if there is a flag,
    # and the original array if there isn't one.
    #
    # ### Usage
    #
    # ~~~ruby
    # x = *(5)
    # ~~~
    #
    class SplatArray
      attr_reader :flag

      def initialize(flag)
        @flag = flag
      end

      def disasm(fmt)
        fmt.instruction("splatarray", [fmt.object(flag)])
      end

      def to_a(_iseq)
        [:splatarray, flag]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(*vm.pop)
      end
    end

    # ### Summary
    #
    # `swap` swaps the top two elements in the stack.
    #
    # ### TracePoint
    #
    # `swap` does not dispatch any events.
    #
    # ### Usage
    #
    # ~~~ruby
    # !!defined?([[]])
    # ~~~
    #
    class Swap
      def disasm(fmt)
        fmt.instruction("swap")
      end

      def to_a(_iseq)
        [:swap]
      end

      def length
        1
      end

      def pops
        2
      end

      def pushes
        2
      end

      def canonical
        self
      end

      def call(vm)
        left, right = vm.pop(2)
        vm.push(right, left)
      end
    end

    # ### Summary
    #
    # `throw` pops a value off the top of the stack and throws it. It is caught
    # using the instruction sequence's (or an ancestor's) catch table. It pushes
    # on the result of throwing the value.
    #
    # ### Usage
    #
    # ~~~ruby
    # [1, 2, 3].map { break 2 }
    # ~~~
    #
    class Throw
      TAG_NONE = 0x0
      TAG_RETURN = 0x1
      TAG_BREAK = 0x2
      TAG_NEXT = 0x3
      TAG_RETRY = 0x4
      TAG_REDO = 0x5
      TAG_RAISE = 0x6
      TAG_THROW = 0x7
      TAG_FATAL = 0x8

      attr_reader :type

      def initialize(type)
        @type = type
      end

      def disasm(fmt)
        fmt.instruction("throw", [fmt.object(type)])
      end

      def to_a(_iseq)
        [:throw, type]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        raise NotImplementedError, "throw"
      end
    end

    # ### Summary
    #
    # `topn` pushes a single value onto the stack that is a copy of the value
    # within the stack that is `number` of slots down from the top.
    #
    # ### Usage
    #
    # ~~~ruby
    # case 3
    # when 1..5
    #   puts "foo"
    # end
    # ~~~
    #
    class TopN
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def disasm(fmt)
        fmt.instruction("topn", [fmt.object(number)])
      end

      def to_a(_iseq)
        [:topn, number]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(vm.stack[-number - 1])
      end
    end

    # ### Summary
    #
    # `toregexp` pops a number of values off the stack, combines them into a new
    # regular expression, and pushes the new regular expression onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # /foo #{bar}/
    # ~~~
    #
    class ToRegExp
      attr_reader :options, :length

      def initialize(options, length)
        @options = options
        @length = length
      end

      def disasm(fmt)
        fmt.instruction("toregexp", [fmt.object(options), fmt.object(length)])
      end

      def to_a(_iseq)
        [:toregexp, options, length]
      end

      def pops
        length
      end

      def pushes
        1
      end

      def canonical
        self
      end

      def call(vm)
        vm.push(Regexp.new(vm.pop(length).join, options))
      end
    end
  end
end
