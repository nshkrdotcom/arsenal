defmodule Arsenal.OperationCompat do
  @moduledoc """
  Compatibility module for operations using the old Arsenal.Operation behaviour.

  This module provides default implementations for the new required callbacks
  to allow existing operations to continue working while they are migrated.
  """

  defmacro __using__(_opts) do
    quote do
      # If these functions aren't defined, provide defaults
      unless Module.defines?(__MODULE__, {:name, 0}) do
        def name() do
          __MODULE__
          |> Module.split()
          |> List.last()
          |> Macro.underscore()
          |> String.to_atom()
        end
      end

      unless Module.defines?(__MODULE__, {:category, 0}) do
        def category() do
          # Try to infer category from module name
          case Module.split(__MODULE__) do
            ["Arsenal", "Operations", "Distributed" | _] ->
              :distributed

            ["Arsenal", "Operations", category | _] ->
              category |> Macro.underscore() |> String.to_atom()

            _ ->
              :general
          end
        end
      end

      unless Module.defines?(__MODULE__, {:description, 0}) do
        def description() do
          case rest_config() do
            %{summary: summary} -> summary
            _ -> "Operation #{name()}"
          end
        end
      end

      unless Module.defines?(__MODULE__, {:params_schema, 0}) do
        def params_schema() do
          # Extract from rest_config if available
          case rest_config() do
            %{parameters: params} when is_list(params) ->
              Enum.reduce(params, %{}, fn param, acc ->
                Map.put(acc, param.name,
                  type: param.type,
                  required: Map.get(param, :required, false)
                )
              end)

            _ ->
              %{}
          end
        end
      end

      unless Module.defines?(__MODULE__, {:metadata, 0}) do
        def metadata(), do: %{}
      end
    end
  end
end
