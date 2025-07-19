defmodule Arsenal.OperationTest do
  use ExUnit.Case, async: true

  defmodule TestOperation do
    use Arsenal.Operation

    def name(), do: :test_operation
    def category(), do: :test
    def description(), do: "A test operation"

    def params_schema() do
      %{
        name: [type: :string, required: true],
        count: [type: :integer, default: 1, min: 0, max: 100]
      }
    end

    def execute(%{name: name, count: count}) do
      {:ok, %{greeting: "Hello #{name}!", count: count}}
    end
  end

  defmodule CustomValidationOperation do
    use Arsenal.Operation

    def name(), do: :custom_validation
    def category(), do: :test
    def description(), do: "Operation with custom validation"

    def params_schema() do
      %{email: [type: :string, required: true]}
    end

    def validate_params(%{email: email} = params) do
      if String.contains?(email, "@") do
        {:ok, params}
      else
        {:error, %{email: "must be a valid email"}}
      end
    end

    def execute(params), do: {:ok, params}
  end

  defmodule AuthorizedOperation do
    use Arsenal.Operation

    def name(), do: :authorized_op
    def category(), do: :test
    def description(), do: "Operation requiring authorization"

    def params_schema(), do: %{}

    def metadata() do
      %{requires_authentication: true, minimum_role: :admin}
    end

    def authorize(_params, %{role: role}) do
      if role == :admin do
        :ok
      else
        {:error, :unauthorized}
      end
    end

    def execute(_params), do: {:ok, %{status: "executed"}}
  end

  describe "Arsenal.Operation behaviour" do
    test "provides default implementations" do
      assert TestOperation.metadata() == %{}

      assert {:ok, %{name: "test", count: 1}} =
               TestOperation.validate_params(%{name: "test"})

      assert TestOperation.authorize(%{}, %{}) == :ok
    end

    test "generates correct REST config" do
      config = TestOperation.rest_config()
      assert config.method == :post
      assert config.path == "/api/v1/operations/test_operation/execute"
      assert config.summary == "A test operation"
      assert config.parameters == TestOperation.params_schema()
    end

    test "formats responses correctly" do
      assert TestOperation.format_response({:ok, %{data: "test"}}) ==
               %{data: %{data: "test"}, success: true}

      assert TestOperation.format_response({:error, "failed"}) ==
               %{error: "failed", success: false}
    end

    test "custom validation can override default" do
      assert {:ok, %{email: "test@example.com"}} =
               CustomValidationOperation.validate_params(%{email: "test@example.com"})

      assert {:error, %{email: "must be a valid email"}} =
               CustomValidationOperation.validate_params(%{email: "invalid"})
    end

    test "authorization can be customized" do
      assert AuthorizedOperation.authorize(%{}, %{role: :admin}) == :ok
      assert AuthorizedOperation.authorize(%{}, %{role: :user}) == {:error, :unauthorized}
    end
  end
end
