defmodule Mix.Tasks.Arsenal.Gen.Operation do
  @moduledoc """
  Generates a new Arsenal operation module from a template.

  ## Usage

      mix arsenal.gen.operation ModuleName category operation_name

  ## Examples

      mix arsenal.gen.operation MyApp.Operations.StartWorker process start_worker
      mix arsenal.gen.operation Arsenal.Operations.RestartNode distributed restart_node

  This will create:
  - The operation module at the specified path
  - A test file for the operation

  ## Options

    * `--no-tests` - do not generate tests for the operation
    * `--path` - specify a custom path for the operation file
  """

  @shortdoc "Generates a new Arsenal operation"

  use Mix.Task

  @template """
  defmodule <%= module %> do
    @moduledoc \"\"\"
    <%= description %>
    
    This operation belongs to the <%= category %> category.
    \"\"\"
    
    use Arsenal.Operation
    
    @impl true
    def name(), do: :<%= operation_name %>
    
    @impl true
    def category(), do: :<%= category %>
    
    @impl true
    def description(), do: "<%= description %>"
    
    @impl true
    def params_schema() do
      %{
        # Define your parameters here
        # example_param: [type: :string, required: true],
        # optional_param: [type: :integer, default: 10, min: 1, max: 100]
      }
    end
    
    @impl true
    def metadata() do
      %{
        # Add operation metadata here
        # requires_authentication: true,
        # minimum_role: :operator,
        # idempotent: true,
        # timeout: 30_000
      }
    end
    
    @impl true
    def rest_config() do
      %{
        method: :post,
        path: "/api/v1/<%= path_segment %>",
        summary: description(),
        parameters: params_schema(),
        responses: %{
          200 => %{description: "Operation completed successfully"},
          400 => %{description: "Invalid parameters"},
          500 => %{description: "Internal server error"}
        }
      }
    end
    
    @impl true
    def execute(params) do
      # TODO: Implement your operation logic here
      {:ok, %{status: "not_implemented", params: params}}
    end
    
    # Optional: Override default validation if needed
    # @impl true
    # def validate_params(params) do
    #   # Custom validation logic
    #   super(params)
    # end
    
    # Optional: Override authorization if needed
    # @impl true
    # def authorize(params, context) do
    #   # Custom authorization logic
    #   super(params, context)
    # end
  end
  """

  @test_template """
  defmodule <%= module %>Test do
    use ExUnit.Case, async: true
    
    alias <%= module %>
    
    describe "operation definition" do
      test "has correct name" do
        assert <%= module %>.name() == :<%= operation_name %>
      end
      
      test "has correct category" do
        assert <%= module %>.category() == :<%= category %>
      end
      
      test "has valid description" do
        description = <%= module %>.description()
        assert is_binary(description)
        assert String.length(description) > 0
      end
      
      test "has valid params schema" do
        schema = <%= module %>.params_schema()
        assert is_map(schema)
      end
      
      test "has valid REST config" do
        config = <%= module %>.rest_config()
        assert config.method in [:get, :post, :put, :patch, :delete]
        assert is_binary(config.path)
        assert is_map(config.responses)
      end
    end
    
    describe "parameter validation" do
      test "validates empty params" do
        assert {:ok, _} = <%= module %>.validate_params(%{})
      end
      
      # TODO: Add more validation tests based on your params_schema
    end
    
    describe "execution" do
      test "executes with valid params" do
        params = %{}
        assert {:ok, result} = <%= module %>.execute(params)
        assert is_map(result)
      end
      
      # TODO: Add more execution tests
    end
    
    describe "authorization" do
      test "authorizes by default" do
        assert :ok = <%= module %>.authorize(%{}, %{})
      end
      
      # TODO: Add authorization tests if you override the default
    end
  end
  """

  def run(args) do
    {opts, args} =
      OptionParser.parse!(args,
        strict: [no_tests: :boolean, path: :string]
      )

    case args do
      [module_name, category, operation_name] ->
        generate_operation(module_name, category, operation_name, opts)

      _ ->
        raise """
        Invalid arguments. Usage:
        mix arsenal.gen.operation ModuleName category operation_name

        Example:
        mix arsenal.gen.operation MyApp.Operations.StartWorker process start_worker
        """
    end
  end

  defp generate_operation(module_name, category, operation_name, opts) do
    module = Module.concat([module_name])

    binding = [
      module: module,
      category: category,
      operation_name: operation_name,
      description: humanize_operation_name(operation_name),
      path_segment: path_segment_from_category(category, operation_name)
    ]

    # Generate operation file
    operation_path = opts[:path] || module_path(module)
    create_file(operation_path, @template, binding)

    # Generate test file unless --no-tests
    unless opts[:no_tests] do
      test_path = test_path(module)
      create_file(test_path, @test_template, binding)
    end

    IO.puts("""

    Operation generated successfully!

    Next steps:
    1. Implement the execute/1 function in #{operation_path}
    2. Define your parameters in params_schema/0
    3. Update the REST config if needed
    4. Write tests in #{test_path(module)}
    5. Register the operation:
       
       Arsenal.Registry.register_operation(#{module})
    """)
  end

  defp module_path(module) do
    path =
      module
      |> Module.split()
      |> Enum.map(&Macro.underscore/1)
      |> Path.join()

    "lib/#{path}.ex"
  end

  defp test_path(module) do
    path =
      module
      |> Module.split()
      |> Enum.map(&Macro.underscore/1)
      |> Path.join()

    "test/#{path}_test.exs"
  end

  defp create_file(path, template, binding) do
    content = EEx.eval_string(template, binding)

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    if File.exists?(path) do
      IO.puts("File #{path} already exists. Overwrite? [Yn] ")

      if IO.gets("") |> String.trim() |> String.downcase() != "n" do
        File.write!(path, content)
        IO.puts("* updating #{path}")
      else
        IO.puts("* skipping #{path}")
      end
    else
      File.write!(path, content)
      IO.puts("* creating #{path}")
    end
  end

  defp humanize_operation_name(operation_name) do
    operation_name
    |> to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp path_segment_from_category(category, operation_name) do
    operation_part =
      operation_name
      |> to_string()
      |> String.replace("_", "-")

    case category do
      "process" -> "processes/#{operation_part}"
      "supervisor" -> "supervisors/#{operation_part}"
      "distributed" -> "cluster/#{operation_part}"
      "sandbox" -> "sandboxes/#{operation_part}"
      "system" -> "system/#{operation_part}"
      _ -> "operations/#{operation_part}"
    end
  end
end
