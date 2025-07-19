defmodule Arsenal.Operation.Validator do
  @moduledoc """
  Parameter validation for Arsenal operations based on schema definitions.
  """

  @type schema :: map()
  @type params :: map()
  @type validation_result :: {:ok, params()} | {:error, map()}

  @doc """
  Validates parameters against a schema definition.

  ## Schema Format

  Each parameter in the schema is defined with these options:
  - `:type` - The expected type (:string, :integer, :float, :boolean, :atom, :pid, :map, :list)
  - `:required` - Whether the parameter is required (default: false)
  - `:default` - Default value if not provided
  - `:in` - List of allowed values
  - `:min` - Minimum value (for numbers) or length (for strings/lists)
  - `:max` - Maximum value (for numbers) or length (for strings/lists)
  - `:format` - Regex pattern for strings
  - `:custom` - Custom validation function

  ## Examples

      iex> schema = %{
      ...>   name: [type: :string, required: true],
      ...>   age: [type: :integer, min: 0, max: 150],
      ...>   role: [type: :atom, in: [:admin, :user, :guest], default: :user]
      ...> }
      iex> Arsenal.Operation.Validator.validate(%{name: "John", age: 30}, schema)
      {:ok, %{name: "John", age: 30, role: :user}}
  """
  @spec validate(params(), schema()) :: validation_result()
  def validate(params, schema) do
    params = apply_defaults(params, schema)

    schema
    |> Enum.reduce({:ok, %{}}, fn {key, rules}, acc ->
      validate_param(acc, key, Map.get(params, key), rules)
    end)
    |> check_unknown_params(params, schema)
  end

  defp apply_defaults(params, schema) do
    Enum.reduce(schema, params, fn {key, rules}, acc ->
      if Map.has_key?(acc, key) do
        acc
      else
        case Keyword.get(rules, :default) do
          nil -> acc
          default -> Map.put(acc, key, default)
        end
      end
    end)
  end

  defp validate_param({:error, _} = error, _key, _value, _rules), do: error

  defp validate_param({:ok, acc}, key, value, rules) do
    with :ok <- check_required(value, rules),
         {:ok, typed_value} <- check_type(value, rules),
         :ok <- check_constraints(typed_value, rules),
         :ok <- run_custom_validation(typed_value, rules) do
      {:ok, Map.put(acc, key, typed_value)}
    else
      {:error, reason} ->
        {:error, %{key => reason}}
    end
  end

  defp check_required(nil, rules) do
    if Keyword.get(rules, :required, false) do
      {:error, "is required"}
    else
      :ok
    end
  end

  defp check_required(_value, _rules), do: :ok

  defp check_type(nil, _rules), do: {:ok, nil}

  defp check_type(value, rules) do
    expected_type = Keyword.get(rules, :type, :any)

    case validate_type(value, expected_type) do
      {:ok, typed_value} -> {:ok, typed_value}
      :error -> {:error, "must be a #{expected_type}"}
    end
  end

  defp validate_type(value, :any), do: {:ok, value}
  defp validate_type(value, :string) when is_binary(value), do: {:ok, value}
  defp validate_type(value, :integer) when is_integer(value), do: {:ok, value}
  defp validate_type(value, :float) when is_float(value), do: {:ok, value}
  defp validate_type(value, :number) when is_number(value), do: {:ok, value}
  defp validate_type(value, :boolean) when is_boolean(value), do: {:ok, value}
  defp validate_type(value, :atom) when is_atom(value), do: {:ok, value}
  defp validate_type(value, :map) when is_map(value), do: {:ok, value}
  defp validate_type(value, :list) when is_list(value), do: {:ok, value}

  defp validate_type(value, :pid) when is_binary(value) do
    case parse_pid(value) do
      {:ok, pid} -> {:ok, pid}
      :error -> :error
    end
  end

  defp validate_type(value, :pid) when is_pid(value), do: {:ok, value}

  defp validate_type(value, :atom) when is_binary(value) do
    {:ok, String.to_atom(value)}
  end

  defp validate_type(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp validate_type(value, :float) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> :error
    end
  end

  defp validate_type(_value, _type), do: :error

  defp check_constraints(nil, _rules), do: :ok

  defp check_constraints(value, rules) do
    with :ok <- check_inclusion(value, rules),
         :ok <- check_min_max(value, rules),
         :ok <- check_format(value, rules) do
      :ok
    end
  end

  defp check_inclusion(value, rules) do
    case Keyword.get(rules, :in) do
      nil ->
        :ok

      allowed ->
        if value in allowed do
          :ok
        else
          {:error, "must be one of: #{inspect(allowed)}"}
        end
    end
  end

  defp check_min_max(value, rules) when is_number(value) do
    min = Keyword.get(rules, :min)
    max = Keyword.get(rules, :max)

    cond do
      min && value < min -> {:error, "must be at least #{min}"}
      max && value > max -> {:error, "must be at most #{max}"}
      true -> :ok
    end
  end

  defp check_min_max(value, rules) when is_binary(value) or is_list(value) do
    length = if is_binary(value), do: String.length(value), else: length(value)
    min = Keyword.get(rules, :min)
    max = Keyword.get(rules, :max)

    cond do
      min && length < min -> {:error, "must have at least #{min} characters/items"}
      max && length > max -> {:error, "must have at most #{max} characters/items"}
      true -> :ok
    end
  end

  defp check_min_max(_value, _rules), do: :ok

  defp check_format(value, rules) when is_binary(value) do
    case Keyword.get(rules, :format) do
      nil ->
        :ok

      regex ->
        if Regex.match?(regex, value) do
          :ok
        else
          {:error, "has invalid format"}
        end
    end
  end

  defp check_format(_value, _rules), do: :ok

  defp run_custom_validation(value, rules) do
    case Keyword.get(rules, :custom) do
      nil -> :ok
      fun when is_function(fun, 1) -> fun.(value)
      _ -> :ok
    end
  end

  defp check_unknown_params({:error, _} = error, _params, _schema), do: error

  defp check_unknown_params({:ok, validated}, params, schema) do
    param_keys = Map.keys(params)
    schema_keys = Map.keys(schema)
    unknown_keys = param_keys -- schema_keys

    if unknown_keys == [] do
      {:ok, validated}
    else
      {:error, %{unknown_params: unknown_keys}}
    end
  end

  defp parse_pid(string) when is_binary(string) do
    case Regex.run(~r/<(\d+)\.(\d+)\.(\d+)>/, string) do
      [_, _node, _id, _serial] ->
        pid_string = "#PID" <> string

        try do
          pid = :erlang.list_to_pid(String.to_charlist(pid_string))
          {:ok, pid}
        rescue
          _ -> :error
        end

      _ ->
        :error
    end
  end
end
