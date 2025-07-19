defmodule Arsenal.Registry do
  @moduledoc """
  Registry for discovering and managing arsenal operations.

  This module automatically discovers all modules implementing the Operation behavior
  and provides metadata for REST API generation.
  """

  use GenServer
  require Logger

  @table_name :arsenal_operations

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get all registered operations with their metadata.
  """
  def list_operations do
    GenServer.call(__MODULE__, :list_operations)
  end

  @doc """
  Get operation by module name.
  """
  def get_operation(module) when is_atom(module) do
    GenServer.call(__MODULE__, {:get_operation, module})
  end

  @doc """
  Register a new operation module.
  """
  def register_operation(module) when is_atom(module) do
    GenServer.call(__MODULE__, {:register_operation, module})
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

  def handle_call(:list_operations, _from, state) do
    operations =
      @table_name
      |> :ets.tab2list()
      |> Enum.map(fn {module, config} -> Map.put(config, :module, module) end)

    {:reply, operations, state}
  end

  def handle_call({:get_operation, module}, _from, state) do
    case :ets.lookup(@table_name, module) do
      [{^module, config}] ->
        {:reply, {:ok, config}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:register_operation, module}, _from, state) do
    case register_operation_module(module) do
      {:ok, config} ->
        :ets.insert(@table_name, {module, config})
        {:reply, {:ok, config}, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:discover_operations, namespace_prefix}, _from, state) do
    # This would be implemented by the application using Arsenal
    # to discover operations based on their module naming convention
    Logger.info("Operation discovery requested for namespace: #{namespace_prefix}")
    {:reply, {:ok, []}, state}
  end

  defp register_operation_module(module) do
    try do
      # Ensure module is loaded
      Code.ensure_loaded(module)

      # Check if module implements the Operation behavior
      if function_exported?(module, :rest_config, 0) do
        config = module.rest_config()

        # Validate config structure
        case validate_rest_config(config) do
          :ok ->
            Logger.debug("Registered Arsenal operation: #{module}")
            {:ok, Map.put(config, :module, module)}

          error ->
            error
        end
      else
        {:error, :not_an_operation}
      end
    rescue
      error ->
        {:error, {:module_error, error}}
    end
  end

  defp validate_rest_config(config) do
    required_keys = [:method, :path, :summary]

    case Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      true -> :ok
      false -> {:error, {:invalid_config, :missing_required_keys}}
    end
  end
end
