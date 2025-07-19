defmodule Arsenal.Operation do
  @moduledoc """
  Behaviour definition for Arsenal operations.

  All operations in the Arsenal system must implement this behaviour to ensure
  consistent interfaces and enable automatic registration, discovery, and execution.

  This behaviour combines the previous REST-focused design with a more comprehensive
  operation framework that supports multiple execution contexts.
  """

  @type params :: map()
  @type result :: {:ok, any()} | {:error, term()}
  @type metadata :: map()
  @type context :: map()

  @doc """
  Returns the unique name of the operation as an atom.
  """
  @callback name() :: atom()

  @doc """
  Returns the category this operation belongs to.

  Common categories include:
  - :process
  - :supervisor
  - :system
  - :distributed
  - :sandbox
  - :tracing
  """
  @callback category() :: atom()

  @doc """
  Returns a human-readable description of what this operation does.
  """
  @callback description() :: String.t()

  @doc """
  Returns the parameter schema for this operation.

  The schema is a map where keys are parameter names and values are
  keyword lists with validation rules:

  ## Example:
      %{
        pid: [type: :pid, required: true],
        timeout: [type: :integer, default: 5000],
        options: [type: :map, default: %{}]
      }
  """
  @callback params_schema() :: map()

  @doc """
  Executes the operation with the given parameters.

  This is the main implementation of the operation logic.
  """
  @callback execute(params()) :: result()

  @doc """
  Returns metadata about the operation.

  Metadata can include:
  - :requires_authentication
  - :minimum_role
  - :rate_limit
  - :timeout
  - :idempotent
  """
  @callback metadata() :: metadata()

  @doc """
  Returns the REST endpoint configuration for this operation.

  ## Return format:
      %{
        method: :get | :post | :put | :delete | :patch,
        path: "/api/v1/path/with/:params",
        summary: "Human readable description",
        parameters: params_schema(),
        responses: %{
          200 => %{description: "Success", schema: %{type: :object}},
          400 => %{description: "Bad Request"},
          500 => %{description: "Internal Server Error"}
        }
      }
  """
  @callback rest_config() :: map()

  @doc """
  Validates the parameters for this operation.

  This callback is optional. If not implemented, default validation
  based on params_schema() will be used.
  """
  @callback validate_params(params()) :: {:ok, params()} | {:error, term()}

  @doc """
  Checks if the operation is authorized in the given context.

  This callback is optional. If not implemented, authorization will
  be handled by the framework based on metadata.
  """
  @callback authorize(params(), context()) :: :ok | {:error, :unauthorized}

  @doc """
  Transforms the operation result for JSON response.
  """
  @callback format_response(result :: term()) :: map()

  @doc """
  Emits telemetry events for the operation result.

  This callback is optional. If not implemented, default telemetry
  will be emitted by the framework.
  """
  @callback emit_telemetry(result(), metadata()) :: :ok

  @optional_callbacks [validate_params: 1, authorize: 2, format_response: 1, emit_telemetry: 2]

  @doc """
  Helper macro to use the Arsenal.Operation behaviour with default implementations.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Arsenal.Operation

      def metadata(), do: %{}

      def rest_config() do
        %{
          method: :post,
          path: "/api/v1/operations/#{name()}/execute",
          summary: description(),
          parameters: params_schema(),
          responses: %{
            200 => %{description: "Success"},
            400 => %{description: "Bad Request"},
            500 => %{description: "Internal Server Error"}
          }
        }
      end

      def validate_params(params) do
        Arsenal.Operation.Validator.validate(params, params_schema())
      end

      def authorize(_params, _context), do: :ok

      def format_response({:ok, result}), do: %{data: result, success: true}
      def format_response({:error, reason}), do: %{error: reason, success: false}

      def emit_telemetry(result, metadata) do
        :telemetry.execute(
          [:arsenal, :operation, String.to_atom(to_string(name()))],
          %{duration: metadata[:duration] || 0},
          %{
            operation: name(),
            category: category(),
            success: match?({:ok, _}, result),
            metadata: metadata
          }
        )
      end

      defoverridable metadata: 0,
                     rest_config: 0,
                     validate_params: 1,
                     authorize: 2,
                     format_response: 1,
                     emit_telemetry: 2
    end
  end
end
