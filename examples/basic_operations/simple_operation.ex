defmodule Examples.BasicOperations.SimpleOperation do
  @moduledoc """
  A simple example operation that demonstrates the basic Arsenal.Operation behavior.
  
  This operation calculates the factorial of a number to showcase:
  - Parameter validation
  - Basic execution logic
  - Response formatting
  - Error handling
  """
  
  use Arsenal.Operation
  
  @impl true
  def name(), do: :factorial
  
  @impl true
  def category(), do: :math
  
  @impl true
  def description(), do: "Calculate the factorial of a number"
  
  @impl true
  def params_schema() do
    %{
      number: [type: :integer, required: true, minimum: 0, maximum: 20]
    }
  end
  
  @impl true
  def metadata() do
    %{
      requires_authentication: false,
      idempotent: true,
      timeout: 1_000,
      rate_limit: {100, :minute}
    }
  end
  
  @impl true
  def rest_config() do
    %{
      method: :post,
      path: "/api/v1/math/factorial",
      summary: "Calculate factorial",
      parameters: [
        %{
          name: :number,
          type: :integer,
          location: :body,
          required: true,
          description: "Number to calculate factorial for (0-20)",
          minimum: 0,
          maximum: 20
        }
      ],
      responses: %{
        200 => %{
          description: "Factorial calculated successfully",
          schema: %{
            type: :object,
            properties: %{
              number: %{type: :integer},
              factorial: %{type: :integer},
              calculated_at: %{type: :string, format: :datetime}
            }
          }
        },
        400 => %{description: "Invalid number provided"},
        422 => %{description: "Number out of range"}
      }
    }
  end
  
  @impl true
  def validate_params(%{"number" => number}) when is_integer(number) do
    cond do
      number < 0 ->
        {:error, {:validation_error, "Number must be non-negative"}}
      
      number > 20 ->
        {:error, {:validation_error, "Number must be 20 or less to prevent overflow"}}
      
      true ->
        {:ok, %{number: number}}
    end
  end
  
  def validate_params(%{"number" => number}) when is_binary(number) do
    case Integer.parse(number) do
      {int_number, ""} -> validate_params(%{"number" => int_number})
      _ -> {:error, {:validation_error, "Number must be a valid integer"}}
    end
  end
  
  def validate_params(_params) do
    {:error, {:validation_error, "Missing required parameter 'number'"}}
  end
  
  @impl true
  def execute(%{number: number}) do
    try do
      result = factorial(number)
      
      {:ok, %{
        number: number,
        factorial: result,
        calculated_at: DateTime.utc_now()
      }}
    rescue
      error ->
        {:error, {:execution_error, "Failed to calculate factorial: #{inspect(error)}"}}
    end
  end
  
  @impl true
  def format_response(%{number: number, factorial: result, calculated_at: timestamp}) do
    %{
      status: "success",
      data: %{
        input: number,
        result: result,
        metadata: %{
          calculated_at: DateTime.to_iso8601(timestamp),
          operation: "factorial"
        }
      }
    }
  end
  
  # Private helper function
  defp factorial(0), do: 1
  defp factorial(n) when n > 0, do: n * factorial(n - 1)
end