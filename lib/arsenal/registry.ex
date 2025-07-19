defmodule Arsenal.Registry do
  @moduledoc """
  Central registry for all Arsenal operations with discovery and introspection capabilities.

  This module manages the registration, discovery, and execution of Arsenal operations.
  It provides a unified interface for accessing operations by name or category, and
  handles operation metadata, validation, and execution context.
  """

  use GenServer
  require Logger

  @table_name :arsenal_operations
  @type operation_info :: %{
          module: module(),
          name: atom(),
          category: atom(),
          description: String.t(),
          schema: map(),
          metadata: map(),
          rest_config: map()
        }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get all registered operations with their metadata.
  """
  def list_operations(category \\ nil) do
    GenServer.call(__MODULE__, {:list_operations, category})
  end

  @doc """
  Get operation by name.
  """
  def get_operation(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:get_operation, name})
  end

  @doc """
  Register a new operation module.
  """
  def register_operation(module) when is_atom(module) do
    GenServer.call(__MODULE__, {:register_operation, module})
  end

  @doc """
  Unregister an operation by name.
  """
  def unregister_operation(name) when is_atom(name) do
    GenServer.call(__MODULE__, {:unregister_operation, name})
  end

  @doc """
  Search operations by query string.
  """
  def search_operations(query) when is_binary(query) do
    GenServer.call(__MODULE__, {:search_operations, query})
  end

  @doc """
  Validate operation parameters without executing.
  """
  def validate_operation_params(name, params) do
    GenServer.call(__MODULE__, {:validate_params, name, params})
  end

  @doc """
  Execute an operation with the given parameters and context.
  """
  def execute_operation(name, params, context \\ %{}) do
    GenServer.call(__MODULE__, {:execute_operation, name, params, context})
  end

  @doc """
  Discover and register all operations in a given namespace.
  This is useful for automatically finding all operations in your application.
  """
  def discover_operations(namespace_prefix) when is_binary(namespace_prefix) do
    GenServer.call(__MODULE__, {:discover_operations, namespace_prefix})
  end

  def init(_opts) do
    :ets.new(@table_name, [:named_table, :public, :set, {:read_concurrency, true}])
    {:ok, %{}}
  end

  # Server Callbacks

  def handle_call({:list_operations, category}, _from, state) do
    operations =
      @table_name
      |> :ets.tab2list()
      |> Enum.map(fn {_name, info} -> info end)
      |> filter_by_category(category)

    {:reply, operations, state}
  end

  def handle_call({:get_operation, name}, _from, state) do
    case :ets.lookup(@table_name, name) do
      [{^name, info}] ->
        {:reply, {:ok, info}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:register_operation, module}, _from, state) do
    case build_operation_info(module) do
      {:ok, info} ->
        :ets.insert(@table_name, {info.name, info})
        Logger.info("Registered Arsenal operation: #{info.name} (#{module})")
        {:reply, {:ok, info}, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:unregister_operation, name}, _from, state) do
    case :ets.lookup(@table_name, name) do
      [{^name, _info}] ->
        :ets.delete(@table_name, name)
        Logger.info("Unregistered Arsenal operation: #{name}")
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:search_operations, query}, _from, state) do
    query_lower = String.downcase(query)

    operations =
      @table_name
      |> :ets.tab2list()
      |> Enum.map(fn {_name, info} -> info end)
      |> Enum.filter(fn info ->
        String.contains?(String.downcase(info.description), query_lower) or
          String.contains?(String.downcase(to_string(info.name)), query_lower) or
          String.contains?(String.downcase(to_string(info.category)), query_lower)
      end)

    {:reply, operations, state}
  end

  def handle_call({:validate_params, name, params}, _from, state) do
    case :ets.lookup(@table_name, name) do
      [{^name, info}] ->
        result = info.module.validate_params(params)
        {:reply, result, state}

      [] ->
        {:reply, {:error, :operation_not_found}, state}
    end
  end

  def handle_call({:execute_operation, name, params, context}, _from, state) do
    with {:ok, info} <- get_operation_info(name),
         {:ok, validated_params} <- info.module.validate_params(params),
         :ok <- info.module.authorize(validated_params, context) do
      start_time = System.monotonic_time()
      result = info.module.execute(validated_params)
      duration = System.monotonic_time() - start_time

      metadata =
        Map.merge(info.metadata, %{
          duration: System.convert_time_unit(duration, :native, :microsecond),
          operation: name,
          category: info.category
        })

      info.module.emit_telemetry(result, metadata)

      {:reply, result, state}
    else
      {:error, :not_found} ->
        {:reply, {:error, :operation_not_found}, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:discover_operations, namespace_prefix}, _from, state) do
    modules = discover_modules(namespace_prefix)

    results =
      Enum.map(modules, fn module ->
        case build_operation_info(module) do
          {:ok, info} ->
            :ets.insert(@table_name, {info.name, info})
            {:ok, module}

          error ->
            error
        end
      end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("Discovered #{successful} operations, #{failed} failed")
    {:reply, {:ok, %{successful: successful, failed: failed, results: results}}, state}
  end

  # Private helpers

  defp build_operation_info(module) do
    try do
      Code.ensure_loaded!(module)

      if function_exported?(module, :name, 0) and
           function_exported?(module, :category, 0) and
           function_exported?(module, :execute, 1) do
        info = %{
          module: module,
          name: module.name(),
          category: module.category(),
          description: module.description(),
          schema: module.params_schema(),
          metadata: module.metadata(),
          rest_config: module.rest_config()
        }

        {:ok, info}
      else
        {:error, {:invalid_operation, :missing_callbacks}}
      end
    rescue
      error ->
        {:error, {:module_error, error}}
    end
  end

  defp get_operation_info(name) do
    case :ets.lookup(@table_name, name) do
      [{^name, info}] -> {:ok, info}
      [] -> {:error, :not_found}
    end
  end

  defp filter_by_category(operations, nil), do: operations

  defp filter_by_category(operations, category) do
    Enum.filter(operations, fn op -> op.category == category end)
  end

  defp discover_modules(namespace_prefix) do
    # List all loaded modules and filter by prefix
    :code.all_loaded()
    |> Enum.map(fn {module, _} -> module end)
    |> Enum.filter(fn module ->
      String.starts_with?(to_string(module), namespace_prefix)
    end)
    |> Enum.filter(fn module ->
      # Check if it's an operation module
      Code.ensure_loaded?(module) and
        function_exported?(module, :name, 0) and
        function_exported?(module, :execute, 1)
    end)
  end
end
