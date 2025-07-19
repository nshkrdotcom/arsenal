defmodule Arsenal.ErrorHandler do
  @moduledoc """
  Centralized error handling and recovery for Arsenal operations.

  This module provides consistent error handling, classification, and recovery
  strategies for all Arsenal operations. It ensures that errors are properly
  formatted, logged, and that the system remains in a consistent state.
  """

  require Logger

  @type error_class :: :validation | :authorization | :execution | :system | :not_found
  @type error_info :: %{
          class: error_class(),
          message: String.t(),
          details: map(),
          operation: atom() | nil,
          timestamp: DateTime.t()
        }

  @doc """
  Wraps an operation execution with comprehensive error handling.

  ## Example

      Arsenal.ErrorHandler.wrap_operation(:list_processes, params, fn ->
        # operation logic here
      end)
  """
  def wrap_operation(operation_name, params, fun) when is_function(fun, 0) do
    start_time = System.monotonic_time()

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time

      log_operation_success(operation_name, params, duration)
      result
    rescue
      e in [ArgumentError, KeyError] ->
        handle_validation_error(operation_name, e, __STACKTRACE__)

      e in [ErlangError] ->
        handle_erlang_error(operation_name, e, __STACKTRACE__)

      e ->
        handle_generic_error(operation_name, e, __STACKTRACE__)
    catch
      :exit, reason ->
        handle_exit(operation_name, reason)

      :throw, value ->
        handle_throw(operation_name, value)
    end
  end

  @doc """
  Classifies an error into one of the predefined error classes.
  """
  @spec classify_error(term()) :: error_class()
  def classify_error({:error, :not_found}), do: :not_found
  def classify_error({:error, :unauthorized}), do: :authorization
  def classify_error({:error, :invalid_params}), do: :validation
  def classify_error({:error, {:validation, _}}), do: :validation
  def classify_error({:error, {:noproc, _}}), do: :execution
  def classify_error({:error, {:nodedown, _}}), do: :system
  def classify_error({:error, :timeout}), do: :system
  def classify_error(_), do: :execution

  @doc """
  Formats an error for API response.
  """
  @spec format_error(term(), atom() | nil) :: map()
  def format_error(error, operation_name \\ nil) do
    error_info = build_error_info(error, operation_name)

    %{
      error: %{
        class: error_info.class,
        message: error_info.message,
        details: error_info.details,
        operation: error_info.operation,
        timestamp: error_info.timestamp
      }
    }
  end

  @doc """
  Handles validation errors specifically.
  """
  def handle_validation_error(errors) when is_map(errors) do
    {:error, format_validation_errors(errors)}
  end

  @doc """
  Attempts to recover from certain types of errors.
  """
  def attempt_recovery(error, operation_name, params, retry_count \\ 0)

  def attempt_recovery({:error, :timeout}, operation_name, _params, retry_count)
      when retry_count < 3 do
    Logger.warning("Operation #{operation_name} timed out, retrying (#{retry_count + 1}/3)")
    :timer.sleep(1000 * (retry_count + 1))
    {:retry, retry_count + 1}
  end

  def attempt_recovery({:error, {:nodedown, node}}, operation_name, _params, retry_count)
      when retry_count < 2 do
    Logger.warning("Node #{node} is down for operation #{operation_name}, retrying")
    :timer.sleep(2000)
    {:retry, retry_count + 1}
  end

  def attempt_recovery(error, _operation_name, _params, _retry_count) do
    {:error, error}
  end

  # Private functions

  defp handle_validation_error(operation_name, exception, stacktrace) do
    Logger.error("""
    Validation error in operation #{operation_name}:
    #{Exception.message(exception)}
    #{Exception.format_stacktrace(stacktrace)}
    """)

    {:error,
     %{
       class: :validation,
       message: Exception.message(exception),
       operation: operation_name
     }}
  end

  defp handle_erlang_error(operation_name, %ErlangError{original: original}, stacktrace) do
    {class, message} = classify_erlang_error(original)

    Logger.error("""
    Erlang error in operation #{operation_name}:
    Class: #{class}
    Message: #{message}
    Original: #{inspect(original)}
    #{Exception.format_stacktrace(stacktrace)}
    """)

    {:error,
     %{
       class: class,
       message: message,
       details: %{original: inspect(original)},
       operation: operation_name
     }}
  end

  defp handle_generic_error(operation_name, exception, stacktrace) do
    Logger.error("""
    Unexpected error in operation #{operation_name}:
    #{inspect(exception)}
    #{Exception.format_stacktrace(stacktrace)}
    """)

    {:error,
     %{
       class: :system,
       message: "An unexpected error occurred",
       details: %{
         exception: inspect(exception),
         message: Exception.message(exception)
       },
       operation: operation_name
     }}
  end

  defp handle_exit(operation_name, reason) do
    Logger.error("Process exit in operation #{operation_name}: #{inspect(reason)}")

    {:error,
     %{
       class: :system,
       message: "Process exited unexpectedly",
       details: %{reason: inspect(reason)},
       operation: operation_name
     }}
  end

  defp handle_throw(operation_name, value) do
    Logger.warning("Throw in operation #{operation_name}: #{inspect(value)}")

    {:error,
     %{
       class: :execution,
       message: "Operation threw a value",
       details: %{value: inspect(value)},
       operation: operation_name
     }}
  end

  defp classify_erlang_error({:noproc, _pid}) do
    {:execution, "Process not found"}
  end

  defp classify_erlang_error({:nodedown, node}) do
    {:system, "Node #{node} is down"}
  end

  defp classify_erlang_error({:badrpc, reason}) do
    {:system, "RPC failed: #{inspect(reason)}"}
  end

  defp classify_erlang_error({:badarg, _}) do
    {:validation, "Invalid argument"}
  end

  defp classify_erlang_error({:system_limit, limit}) do
    {:system, "System limit reached: #{limit}"}
  end

  defp classify_erlang_error(error) do
    {:execution, "Erlang error: #{inspect(error)}"}
  end

  defp build_error_info(error, operation_name) do
    %{
      class: classify_error(error),
      message: extract_error_message(error),
      details: extract_error_details(error),
      operation: operation_name,
      timestamp: DateTime.utc_now()
    }
  end

  defp extract_error_message({:error, message}) when is_binary(message), do: message
  defp extract_error_message({:error, atom}) when is_atom(atom), do: to_string(atom)
  defp extract_error_message({:error, {_type, message}}), do: to_string(message)

  defp extract_error_message({:error, map}) when is_map(map) do
    Map.get(map, :message, "Operation failed")
  end

  defp extract_error_message(_), do: "Unknown error"

  defp extract_error_details({:error, %{} = details}), do: details
  defp extract_error_details({:error, {type, details}}), do: %{type: type, details: details}
  defp extract_error_details({:error, _}), do: %{}
  defp extract_error_details(_), do: %{}

  defp format_validation_errors(errors) when is_map(errors) do
    %{
      class: :validation,
      message: "Validation failed",
      details: %{
        errors: errors
      }
    }
  end

  defp log_operation_success(operation_name, params, duration) do
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    Logger.debug("""
    Operation completed successfully:
    Operation: #{operation_name}
    Duration: #{duration_ms}ms
    Params: #{inspect(params, limit: :infinity, printable_limit: :infinity)}
    """)
  end

  @doc """
  Creates a standardized error response for HTTP APIs.
  """
  def api_error_response(error, status_code \\ 400) do
    %{
      status: status_code,
      body: format_error(error),
      headers: [{"content-type", "application/json"}]
    }
  end

  @doc """
  Extracts user-friendly error messages from various error formats.
  """
  def user_friendly_message(error) do
    case classify_error(error) do
      :validation ->
        "The provided data is invalid. Please check your input and try again."

      :authorization ->
        "You don't have permission to perform this operation."

      :not_found ->
        "The requested resource could not be found."

      :system ->
        "A system error occurred. Please try again later."

      :execution ->
        "The operation could not be completed. Please try again."
    end
  end
end
