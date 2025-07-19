defmodule Arsenal.Adapter do
  @moduledoc """
  Behavior for creating web framework adapters for Arsenal.

  This allows Arsenal to be integrated with any web framework
  by implementing this behavior.
  """

  @doc """
  Extracts the HTTP method from the framework-specific request object.

  Should return one of: :get, :post, :put, :patch, :delete
  """
  @callback extract_method(request :: any()) :: atom()

  @doc """
  Extracts the request path from the framework-specific request object.

  Should return the path as a string, e.g., "/api/v1/users/123"
  """
  @callback extract_path(request :: any()) :: String.t()

  @doc """
  Extracts all parameters from the request (path params, query params, body params).

  Should return a map with string keys.
  """
  @callback extract_params(request :: any()) :: map()

  @doc """
  Sends a successful response with the given data.

  The adapter should handle JSON encoding and set appropriate headers.
  """
  @callback send_response(request :: any(), status :: integer(), body :: map()) :: any()

  @doc """
  Sends an error response.

  The adapter should format the error appropriately for the framework.
  """
  @callback send_error(request :: any(), status :: integer(), error :: any()) :: any()

  @doc """
  Optional callback to modify the request before processing.

  This can be used for authentication, logging, etc.
  """
  @callback before_process(request :: any()) :: {:ok, any()} | {:error, any()}

  @doc """
  Optional callback to modify the response after processing.

  This can be used for adding headers, logging, etc.
  """
  @callback after_process(request :: any(), response :: any()) :: any()

  @optional_callbacks [before_process: 1, after_process: 2]

  @doc """
  Main entry point for processing requests through Arsenal.

  This function uses the adapter callbacks to:
  1. Extract request information
  2. Find matching operation
  3. Execute operation
  4. Send response
  """
  def process_request(adapter, request) do
    with {:ok, request} <- maybe_before_process(adapter, request),
         method <- adapter.extract_method(request),
         path <- adapter.extract_path(request),
         params <- adapter.extract_params(request),
         {:ok, operation} <- find_operation(method, path),
         {:ok, result} <- Arsenal.execute_operation(operation.module, params) do
      response = operation.module.format_response(result)
      response = maybe_after_process(adapter, request, response)
      adapter.send_response(request, 200, response)
    else
      {:error, :operation_not_found} ->
        adapter.send_error(request, 404, %{
          error: %{
            code: "OPERATION_NOT_FOUND",
            message:
              "No operation found for #{adapter.extract_method(request)} #{adapter.extract_path(request)}"
          }
        })

      {:error, validation_error} when is_binary(validation_error) ->
        adapter.send_error(request, 400, %{
          error: %{
            code: "VALIDATION_ERROR",
            message: validation_error
          }
        })

      {:error, error} ->
        adapter.send_error(request, 500, %{
          error: %{
            code: "INTERNAL_ERROR",
            message: "An internal error occurred",
            details: inspect(error)
          }
        })
    end
  end

  defp maybe_before_process(adapter, request) do
    if function_exported?(adapter, :before_process, 1) do
      adapter.before_process(request)
    else
      {:ok, request}
    end
  end

  defp maybe_after_process(adapter, request, response) do
    if function_exported?(adapter, :after_process, 2) do
      adapter.after_process(request, response)
    else
      response
    end
  end

  defp find_operation(method, path) do
    # Find operation that matches the method and path
    operations = Arsenal.list_operations()

    Enum.find_value(operations, {:error, :operation_not_found}, fn op ->
      if op.method == method && path_matches?(path, op.path) do
        {:ok, op}
      else
        nil
      end
    end)
  end

  defp path_matches?(request_path, pattern_path) do
    # Convert pattern like "/api/v1/users/:id" to regex
    pattern =
      pattern_path
      |> String.split("/")
      |> Enum.map(fn
        ":" <> _param -> "([^/]+)"
        segment -> Regex.escape(segment)
      end)
      |> Enum.join("/")

    regex = ~r/^#{pattern}$/
    Regex.match?(regex, request_path)
  end
end
