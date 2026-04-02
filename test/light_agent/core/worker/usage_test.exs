defmodule LightAgent.Core.Worker.UsageTest do
  use ExUnit.Case, async: true

  alias LightAgent.Core.Worker.Usage

  describe "extract_usage/1" do
    test "extracts usage from response with all fields" do
      response = %{
        "usage" => %{
          "prompt_tokens" => 100,
          "completion_tokens" => 50,
          "total_tokens" => 150
        }
      }

      usage = Usage.extract_usage(response)

      assert usage.prompt_tokens == 100
      assert usage.completion_tokens == 50
      assert usage.total_tokens == 150
    end

    test "calculates total_tokens when not provided" do
      response = %{
        "usage" => %{
          "prompt_tokens" => 100,
          "completion_tokens" => 50
        }
      }

      usage = Usage.extract_usage(response)

      assert usage.total_tokens == 150
    end

    test "returns nil for response without usage" do
      response = %{"choices" => []}

      assert Usage.extract_usage(response) == nil
    end

    test "handles float token values" do
      response = %{
        "usage" => %{
          "prompt_tokens" => 100.5,
          "completion_tokens" => 50.7
        }
      }

      usage = Usage.extract_usage(response)

      assert usage.prompt_tokens == 100
      assert usage.completion_tokens == 50
    end

    test "handles string token values" do
      response = %{
        "usage" => %{
          "prompt_tokens" => "100",
          "completion_tokens" => "50"
        }
      }

      usage = Usage.extract_usage(response)

      assert usage.prompt_tokens == 100
      assert usage.completion_tokens == 50
    end

    test "handles invalid string values" do
      response = %{
        "usage" => %{
          "prompt_tokens" => "invalid",
          "completion_tokens" => 50
        }
      }

      usage = Usage.extract_usage(response)

      assert usage.prompt_tokens == nil
      assert usage.completion_tokens == 50
    end
  end

  describe "update_token_usage/2" do
    test "updates token usage with new usage data" do
      current = Usage.default_token_usage_total()

      usage = %{
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150
      }

      updated = Usage.update_token_usage(current, usage)

      assert updated.prompt_tokens == 100
      assert updated.completion_tokens == 50
      assert updated.total_tokens == 150
      assert updated.steps == 1
      assert updated.missing_usage_steps == 0
    end

    test "accumulates token usage across multiple calls" do
      current = Usage.default_token_usage_total()

      usage1 = %{prompt_tokens: 100, completion_tokens: 50, total_tokens: 150}
      usage2 = %{prompt_tokens: 200, completion_tokens: 75, total_tokens: 275}

      updated =
        current
        |> Usage.update_token_usage(usage1)
        |> Usage.update_token_usage(usage2)

      assert updated.prompt_tokens == 300
      assert updated.completion_tokens == 125
      assert updated.total_tokens == 425
      assert updated.steps == 2
    end

    test "increments missing_usage_steps when usage is nil" do
      current = Usage.default_token_usage_total()

      updated = Usage.update_token_usage(current, nil)

      assert updated.prompt_tokens == 0
      assert updated.completion_tokens == 0
      assert updated.total_tokens == 0
      assert updated.steps == 1
      assert updated.missing_usage_steps == 1
    end
  end

  describe "build_step_usage/2" do
    test "builds step usage with all fields" do
      usage = %{prompt_tokens: 100, completion_tokens: 50, total_tokens: 150}

      session_total = %{
        prompt_tokens: 200,
        completion_tokens: 100,
        total_tokens: 300,
        steps: 2,
        missing_usage_steps: 0
      }

      step_usage = Usage.build_step_usage(usage, session_total)

      assert step_usage.prompt_tokens == 100
      assert step_usage.completion_tokens == 50
      assert step_usage.total_tokens == 150
      assert step_usage.session_total == session_total
    end

    test "handles nil usage" do
      session_total = %{
        prompt_tokens: 200,
        completion_tokens: 100,
        total_tokens: 300,
        steps: 2,
        missing_usage_steps: 1
      }

      step_usage = Usage.build_step_usage(nil, session_total)

      assert step_usage.prompt_tokens == nil
      assert step_usage.completion_tokens == nil
      assert step_usage.total_tokens == nil
      assert step_usage.session_total == session_total
    end
  end

  describe "default_token_usage_total/0" do
    test "creates default token usage total" do
      default = Usage.default_token_usage_total()

      assert default.prompt_tokens == 0
      assert default.completion_tokens == 0
      assert default.total_tokens == 0
      assert default.steps == 0
      assert default.missing_usage_steps == 0
    end
  end
end
