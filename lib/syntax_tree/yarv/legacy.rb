# frozen_string_literal: true

module SyntaxTree
  module YARV
    # This module contains the instructions that used to be a part of YARV but
    # have been replaced or removed in more recent versions.
    module Legacy
      # ### Summary
      #
      # `getclassvariable` looks for a class variable in the current class and
      # pushes its value onto the stack.
      #
      # This version of the `getclassvariable` instruction is no longer used
      # since in Ruby 3.0 it gained an inline cache.`
      #
      # ### Usage
      #
      # ~~~ruby
      # @@class_variable
      # ~~~
      #
      class GetClassVariable
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def disasm(fmt)
          fmt.instruction("getclassvariable", [fmt.object(name)])
        end

        def to_a(_iseq)
          [:getclassvariable, name]
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
      end

      # ### Summary
      #
      # `opt_getinlinecache` is a wrapper around a series of `putobject` and
      # `getconstant` instructions that allows skipping past them if the inline
      # cache is currently set. It pushes the value of the cache onto the stack
      # if it is set, otherwise it pushes `nil`.
      #
      # This instruction is no longer used since in Ruby 3.2 it was replaced by
      # the consolidated `opt_getconstant_path` instruction.
      #
      # ### Usage
      #
      # ~~~ruby
      # Constant
      # ~~~
      #
      class OptGetInlineCache
        attr_reader :label, :cache

        def initialize(label, cache)
          @label = label
          @cache = cache
        end

        def disasm(fmt)
          fmt.instruction(
            "opt_getinlinecache",
            [fmt.label(label), fmt.inline_storage(cache)]
          )
        end

        def to_a(_iseq)
          [:opt_getinlinecache, label.name, cache]
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

        def call(vm)
          vm.push(nil)
        end
      end

      # ### Summary
      #
      # `opt_setinlinecache` sets an inline cache for a constant lookup. It pops
      # the value it should set off the top of the stack. It then pushes that
      # value back onto the top of the stack.
      #
      # This instruction is no longer used since in Ruby 3.2 it was replaced by
      # the consolidated `opt_getconstant_path` instruction.
      #
      # ### Usage
      #
      # ~~~ruby
      # Constant
      # ~~~
      #
      class OptSetInlineCache
        attr_reader :cache

        def initialize(cache)
          @cache = cache
        end

        def disasm(fmt)
          fmt.instruction("opt_setinlinecache", [fmt.inline_storage(cache)])
        end

        def to_a(_iseq)
          [:opt_setinlinecache, cache]
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

        def call(vm)
          vm.push(vm.pop)
        end
      end

      # ### Summary
      #
      # `setclassvariable` looks for a class variable in the current class and
      # sets its value to the value it pops off the top of the stack.
      #
      # This version of the `setclassvariable` instruction is no longer used
      # since in Ruby 3.0 it gained an inline cache.
      #
      # ### Usage
      #
      # ~~~ruby
      # @@class_variable = 1
      # ~~~
      #
      class SetClassVariable
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def disasm(fmt)
          fmt.instruction("setclassvariable", [fmt.object(name)])
        end

        def to_a(_iseq)
          [:setclassvariable, name]
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
      end
    end
  end
end
