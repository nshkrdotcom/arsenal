defmodule Arsenal.Startup do
  @moduledoc """
  Startup module for registering all Arsenal operations.
  """

  require Logger

  def register_all_operations do
    Logger.info("Discovering and registering Arsenal operations...")

    # Discover all operation modules
    operations = discover_operation_modules()

    results =
      Enum.map(operations, fn module ->
        case Arsenal.Registry.register_operation(module) do
          {:ok, info} ->
            Logger.info("Registered: #{info.name}")
            {:ok, module}

          {:error, reason} = error ->
            Logger.error("Failed to register #{inspect(module)}: #{inspect(reason)}")
            error
        end
      end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("Registration complete: #{successful} successful, #{failed} failed")

    {:ok, %{successful: successful, failed: failed, results: results}}
  end

  defp discover_operation_modules do
    # Ensure all Arsenal.Operations modules are loaded
    {:ok, modules} = :application.get_key(:arsenal, :modules)

    modules
    |> Enum.filter(fn module ->
      # Check if it's an Arsenal operation module
      module_str = to_string(module)

      String.starts_with?(module_str, "Elixir.Arsenal.Operations.") and
        Code.ensure_loaded?(module) and
        function_exported?(module, :name, 0) and
        function_exported?(module, :execute, 1)
    end)
  end
end
