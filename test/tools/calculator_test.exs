defmodule LangChain.Tools.CalculatorTest do
  alias LangChain.Chains.LLMChain
  use LangChain.BaseCase

  doctest LangChain.Tools.Calculator
  alias LangChain.Tools.Calculator
  alias LangChain.Function
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Message.ToolCall
  alias LangChain.Message.ToolResult

  import ExUnit.CaptureIO

  describe "new/0" do
    test "defines the function correctly" do
      assert {:ok, %Function{} = function} = Calculator.new()
      assert function.name == "calculator"
      assert function.description == "Perform basic math calculations or expressions"
      assert function.function != nil

      assert function.parameters_schema == %{
               type: "object",
               properties: %{
                 expression: %{type: "string", description: "A simple mathematical expression"}
               },
               required: ["expression"]
             }
    end

    test "assigned function can be executed" do
      {:ok, calc} = Calculator.new()
      assert "3" == calc.function.(%{"expression" => "1 + 2"}, nil)
    end
  end

  describe "new!/0" do
    test "returns the function" do
      assert %Function{name: "calculator"} = Calculator.new!()
    end
  end

  describe "execute/2" do
    test "evaluates the expression returning the result" do
      assert "14" == Calculator.execute(%{"expression" => "1 + 2 + 3 + (2 * 4)"}, nil)
    end

    test "returns an error when evaluation fails" do
      {result, _} =
        with_io(:standard_error, fn ->
          Calculator.execute(%{"expression" => "cow + dog"}, nil)
        end)

      assert "ERROR" == result
    end
  end

  describe "live test" do
    @tag live_call: true, live_open_ai: true
    test "performs repeated calls until complete with a live LLM" do
      test_pid = self()

      callback = fn %Message{} = msg ->
        send(test_pid, {:callback_msg, msg})
      end

      {:ok, updated_chain, %Message{} = message} =
        LLMChain.new!(%{
          llm: ChatOpenAI.new!(%{seed: 0, temperature: 0, stream: false}),
          verbose: true
        })
        |> LLMChain.add_message(
          Message.new_user!("Answer the following math question: What is 100 + 300 - 200?")
        )
        |> LLMChain.add_tools(Calculator.new!())
        |> LLMChain.run(while_needs_response: true, callback_fn: callback)

      assert updated_chain.last_message == message
      assert message.role == :assistant

      assert message.content =~ "100 + 300 - 200"
      assert message.content =~ "is 200"

      # assert received multiple messages as callbacks
      assert_received {:callback_msg, message}
      assert message.role == :assistant
      assert [%ToolCall{name: "calculator", arguments: %{"expression" => _}}] = message.tool_calls

      # the function result message
      assert_received {:callback_msg, message}
      assert message.role == :tool
      assert [%ToolResult{content: "200"}] = message.tool_results

      assert_received {:callback_msg, message}
      assert message.role == :assistant

      assert message.content =~ "200"

      assert updated_chain.last_message == message
    end
  end
end
