defmodule Arsenal.Operation.ValidatorTest do
  use ExUnit.Case, async: true

  alias Arsenal.Operation.Validator

  describe "type validation" do
    test "validates string types" do
      schema = %{name: [type: :string]}
      assert {:ok, %{name: "test"}} = Validator.validate(%{name: "test"}, schema)

      assert {:error, %{name: "must be a string"}} =
               Validator.validate(%{name: 123}, schema)
    end

    test "validates integer types" do
      schema = %{age: [type: :integer]}
      assert {:ok, %{age: 25}} = Validator.validate(%{age: 25}, schema)
      assert {:ok, %{age: 25}} = Validator.validate(%{age: "25"}, schema)

      assert {:error, %{age: "must be a integer"}} =
               Validator.validate(%{age: "invalid"}, schema)
    end

    test "validates float types" do
      schema = %{price: [type: :float]}
      assert {:ok, %{price: 19.99}} = Validator.validate(%{price: 19.99}, schema)
      assert {:ok, %{price: 19.99}} = Validator.validate(%{price: "19.99"}, schema)

      assert {:error, %{price: "must be a float"}} =
               Validator.validate(%{price: "invalid"}, schema)
    end

    test "validates boolean types" do
      schema = %{active: [type: :boolean]}
      assert {:ok, %{active: true}} = Validator.validate(%{active: true}, schema)
      assert {:ok, %{active: false}} = Validator.validate(%{active: false}, schema)

      assert {:error, %{active: "must be a boolean"}} =
               Validator.validate(%{active: "true"}, schema)
    end

    test "validates atom types" do
      schema = %{status: [type: :atom]}
      assert {:ok, %{status: :active}} = Validator.validate(%{status: :active}, schema)
      assert {:ok, %{status: :active}} = Validator.validate(%{status: "active"}, schema)
    end

    test "validates map types" do
      schema = %{config: [type: :map]}

      assert {:ok, %{config: %{key: "value"}}} =
               Validator.validate(%{config: %{key: "value"}}, schema)

      assert {:error, %{config: "must be a map"}} =
               Validator.validate(%{config: "invalid"}, schema)
    end

    test "validates list types" do
      schema = %{tags: [type: :list]}
      assert {:ok, %{tags: ["a", "b"]}} = Validator.validate(%{tags: ["a", "b"]}, schema)

      assert {:error, %{tags: "must be a list"}} =
               Validator.validate(%{tags: "invalid"}, schema)
    end

    test "validates pid types" do
      schema = %{process: [type: :pid]}
      pid = self()
      assert {:ok, %{process: ^pid}} = Validator.validate(%{process: pid}, schema)
    end
  end

  describe "required validation" do
    test "validates required fields" do
      schema = %{name: [type: :string, required: true]}
      assert {:error, %{name: "is required"}} = Validator.validate(%{}, schema)
      assert {:ok, %{name: "test"}} = Validator.validate(%{name: "test"}, schema)
    end

    test "optional fields can be nil" do
      schema = %{name: [type: :string, required: false]}
      assert {:ok, %{}} = Validator.validate(%{}, schema)
    end
  end

  describe "default values" do
    test "applies default values" do
      schema = %{
        count: [type: :integer, default: 10],
        name: [type: :string, default: "anonymous"]
      }

      assert {:ok, %{count: 10, name: "anonymous"}} = Validator.validate(%{}, schema)

      assert {:ok, %{count: 5, name: "anonymous"}} =
               Validator.validate(%{count: 5}, schema)
    end
  end

  describe "constraint validation" do
    test "validates inclusion constraints" do
      schema = %{role: [type: :atom, in: [:admin, :user, :guest]]}
      assert {:ok, %{role: :admin}} = Validator.validate(%{role: :admin}, schema)

      assert {:error, %{role: "must be one of: [:admin, :user, :guest]"}} =
               Validator.validate(%{role: :other}, schema)
    end

    test "validates min/max for numbers" do
      schema = %{age: [type: :integer, min: 18, max: 100]}
      assert {:ok, %{age: 25}} = Validator.validate(%{age: 25}, schema)

      assert {:error, %{age: "must be at least 18"}} =
               Validator.validate(%{age: 10}, schema)

      assert {:error, %{age: "must be at most 100"}} =
               Validator.validate(%{age: 150}, schema)
    end

    test "validates min/max for strings" do
      schema = %{name: [type: :string, min: 3, max: 10]}
      assert {:ok, %{name: "test"}} = Validator.validate(%{name: "test"}, schema)

      assert {:error, %{name: "must have at least 3 characters/items"}} =
               Validator.validate(%{name: "ab"}, schema)

      assert {:error, %{name: "must have at most 10 characters/items"}} =
               Validator.validate(%{name: "verylongname"}, schema)
    end

    test "validates format with regex" do
      schema = %{email: [type: :string, format: ~r/^[^\s]+@[^\s]+$/]}

      assert {:ok, %{email: "test@example.com"}} =
               Validator.validate(%{email: "test@example.com"}, schema)

      assert {:error, %{email: "has invalid format"}} =
               Validator.validate(%{email: "invalid"}, schema)
    end
  end

  describe "custom validation" do
    test "runs custom validation functions" do
      schema = %{
        password: [
          type: :string,
          custom: fn pass ->
            if String.length(pass) >= 8 do
              :ok
            else
              {:error, "must be at least 8 characters"}
            end
          end
        ]
      }

      assert {:ok, %{password: "longpassword"}} =
               Validator.validate(%{password: "longpassword"}, schema)

      assert {:error, %{password: "must be at least 8 characters"}} =
               Validator.validate(%{password: "short"}, schema)
    end
  end

  describe "unknown parameters" do
    test "detects unknown parameters" do
      schema = %{name: [type: :string]}

      assert {:error, %{unknown_params: [:extra]}} =
               Validator.validate(%{name: "test", extra: "value"}, schema)
    end
  end

  describe "complex validation" do
    test "validates nested structures" do
      schema = %{
        user: [type: :map, required: true],
        tags: [type: :list, default: []],
        count: [type: :integer, min: 0, max: 100, default: 10]
      }

      params = %{
        user: %{name: "John", age: 30},
        tags: ["elixir", "phoenix"]
      }

      assert {:ok, validated} = Validator.validate(params, schema)
      assert validated.user == %{name: "John", age: 30}
      assert validated.tags == ["elixir", "phoenix"]
      assert validated.count == 10
    end
  end
end
