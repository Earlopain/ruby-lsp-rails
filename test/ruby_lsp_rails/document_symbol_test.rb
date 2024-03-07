# typed: true
# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Rails
    class DocumentSymbolTest < ActiveSupport::TestCase
      setup do
        @message_queue = Thread::Queue.new
      end

      def teardown
        T.must(@message_queue).close
      end

      test "recognizes Rails Active Support test cases" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class Test < ActiveSupport::TestCase
            test "an example" do
              # test body
            end
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("Test", response[0].name)
        assert_equal(1, response[0].children.size)
        assert_equal("an example", response[0].children[0].name)
      end

      test "recognizes Rails Active Support test cases using minitest/spec" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class Test < ActiveSupport::TestCase
            it "an example" do
              # test body
            end
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("Test", response[0].name)
        assert_equal(1, response[0].children.size)
        assert_equal("an example", response[0].children[0].name)
      end

      test "recognizes multiline escaped strings" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class Test < ActiveSupport::TestCase
            test "an example" \
              "multiline" do
              # test body
            end
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("Test", response[0].name)
        assert_equal(1, response[0].children.size)
        assert_equal("an examplemultiline", response[0].children[0].name)
      end

      test "ignores unnamed tests (empty string)" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class Test < ActiveSupport::TestCase
            test "" do
              # test body
            end
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("Test", response[0].name)
        assert_empty(response[0].children)
      end

      test "ignores tests with interpolation in their names" do
        # Note that we need to quote the heredoc RUBY marker to prevent interpolation when defining the test.
        response = generate_document_symbols_for_source(<<~RUBY)
          class Test < ActiveSupport::TestCase
            test "before \#{1 + 1} after" do
              # test body
            end
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("Test", response[0].name)
        assert_empty(response[0].children)
      end

      test "ignores tests with a non-string name argument" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class Test < ActiveSupport::TestCase
            test foo do
              # test body
            end
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("Test", response[0].name)
        assert_empty(response[0].children)
      end

      test "ignores test cases without a name" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class Test < ActiveSupport::TestCase
            test do
              # test body
            end
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("Test", response[0].name)
        assert_empty(response[0].children)
      end

      test "recognizes plain test cases" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class Test < ActiveSupport::TestCase
            def test_example
              # test body
            end
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("Test", response[0].name)
        assert_equal(1, response[0].children.size)
        assert_equal("test_example", response[0].children[0].name)
      end

      test "assigns the correct hierarchy to test structure" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class Test < ActiveSupport::TestCase
            test "an example" do
              # test body
            end

            class NestedTest < ActiveSupport::TestCase
              test "other" do
                # other test body
              end
            end

            test "back to the same level" do
              # test body
            end
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("Test", response[0].name)
        assert_equal(3, response[0].children.size)
        assert_equal("an example", response[0].children[0].name)
        nexted_test = response[0].children[1]
        assert_equal("NestedTest", nexted_test.name)
        assert_equal(1, nexted_test.children.size)
        assert_equal("other", nexted_test.children[0].name)

        assert_equal("back to the same level", response[0].children[2].name)
      end

      test "correctly handles model callbacks with multiple Prism::StringNode arguments" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class FooModel < ApplicationRecord
            before_save "foo_method", "bar_method", on: :update
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("FooModel", response[0].name)
        assert_equal(2, response[0].children.size)
        assert_equal("before_save(foo_method)", response[0].children[0].name)
        assert_equal("before_save(bar_method)", response[0].children[1].name)
      end

      test "correctly handles controller callback with block" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class FooController < ApplicationController
            before_action do
              # block body
            end
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("FooController", response[0].name)
        assert_equal(1, response[0].children.size)
        assert_equal("before_action(<anonymous>)", response[0].children[0].name)
      end

      test "correctly handles job callback with Prism::SymbolNode argument" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class FooJob < ApplicationJob
            before_perform :foo_method
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("FooJob", response[0].name)
        assert_equal(1, response[0].children.size)
        assert_equal("before_perform(foo_method)", response[0].children[0].name)
      end

      test "correctly handles model callback with Prism::LambdaNode argument" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class FooModel < ApplicationRecord
            before_save -> () {}
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("FooModel", response[0].name)
        assert_equal(1, response[0].children.size)
        assert_equal("before_save(<anonymous>)", response[0].children[0].name)
      end

      test "correctly handles job callbacks with Prism::CallNode argument" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class FooJob < ApplicationJob
            before_perform FooClass.new(foo_arg)
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("FooJob", response[0].name)
        assert_equal(1, response[0].children.size)
        assert_equal("before_perform(FooClass)", response[0].children[0].name)
      end

      test "correctly handles controller callbacks with Prism::ConstantReadNode argument" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class FooController < ApplicationController
            before_action FooClass
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("FooController", response[0].name)
        assert_equal(1, response[0].children.size)
        assert_equal("before_action(FooClass)", response[0].children[0].name)
      end

      test "correctly handles model callbacks with Prism::ConstantPathNode argument" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class FooModel < ApplicationRecord
            before_save Foo::BarClass
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("FooModel", response[0].name)
        assert_equal(1, response[0].children.size)
        assert_equal("before_save(Foo::BarClass)", response[0].children[0].name)
      end

      test "correctly handles job callbacks with all argument types" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class FooJob < ApplicationJob
            before_perform "foo_arg", :bar_arg, -> () {}, Foo::BazClass.new("blah"), FooClass, Foo::BarClass
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("FooJob", response[0].name)
        assert_equal(6, response[0].children.size)
        assert_equal("before_perform(foo_arg)", response[0].children[0].name)
        assert_equal("before_perform(bar_arg)", response[0].children[1].name)
        assert_equal("before_perform(<anonymous>)", response[0].children[2].name)
        assert_equal("before_perform(Foo::BazClass)", response[0].children[3].name)
        assert_equal("before_perform(FooClass)", response[0].children[4].name)
        assert_equal("before_perform(Foo::BarClass)", response[0].children[5].name)
      end

      test "ignore unrecognized callback" do
        response = generate_document_symbols_for_source(<<~RUBY)
          class FooJob < ApplicationJob
            unrecognized_callback :foo_method
          end
        RUBY

        assert_equal(1, response.size)
        assert_equal("FooJob", response[0].name)
        assert_empty(response[0].children)
      end

      private

      def generate_document_symbols_for_source(source)
        uri = URI("file:///fake.rb")
        store = RubyLsp::Store.new
        store.set(uri: uri, source: source, version: 1)

        capture_subprocess_io do
          RubyLsp::Executor.new(store, @message_queue).execute({
            method: "initialized",
            params: {},
          })
        end

        response = RubyLsp::Executor.new(store, @message_queue).execute({
          method: "textDocument/documentSymbol",
          params: { textDocument: { uri: uri }, position: { line: 0, character: 0 } },
        })

        assert_nil(response.error)

        response.response
      end
    end
  end
end
