#!/usr/bin/env elixir

# Standalone script to run all Arsenal examples
# Usage: elixir examples/run_all_demos.exs

# Add the lib directory to the code path
Code.prepend_path("lib")

defmodule AllDemosRunner do
  def run do
    IO.puts("🎯 Arsenal Complete Demo Suite")
    IO.puts("=" <> String.duplicate("=", 35))
    IO.puts("\nThis will run all Arsenal examples to showcase the full functionality.")
    IO.puts("Each demo is self-contained and demonstrates different aspects of Arsenal.\n")
    
    demos = [
      {"Basic Operations", "examples/run_basic_operations.exs", "Basic operation patterns, validation, and execution"},
      {"Analytics & Monitoring", "examples/run_analytics_demo.exs", "System monitoring, health checks, and analytics"},
      {"Process Management", "examples/run_process_demo.exs", "Process inspection, control, and management"}
    ]
    
    Enum.with_index(demos, 1)
    |> Enum.each(fn {{name, script, description}, index} ->
      IO.puts("#{index}. #{name}")
      IO.puts("   #{description}")
      IO.puts("   Running: #{script}")
      IO.puts("   " <> String.duplicate("-", 50))
      
      case run_demo_script(script) do
        :ok ->
          IO.puts("   ✅ Demo completed successfully")
        
        {:error, reason} ->
          IO.puts("   ❌ Demo failed: #{reason}")
      end
      
      if index < length(demos) do
        IO.puts("\n" <> String.duplicate("=", 60) <> "\n")
        Process.sleep(1000)  # Brief pause between demos
      end
    end)
    
    IO.puts("\n🎉 All demos completed!")
    IO.puts("\nNext steps:")
    IO.puts("• Explore the examples/ directory for detailed code")
    IO.puts("• Read the README files in each subdirectory")
    IO.puts("• Try running individual scripts: elixir examples/run_basic_operations.exs")
    IO.puts("• Start an iex session and experiment with the APIs")
    IO.puts("• Integrate Arsenal into your own applications")
  end
  
  defp run_demo_script(script_path) do
    try do
      # Use Code.eval_file to run the script in the current process
      # This allows sharing of started processes between demos
      {_result, _bindings} = Code.eval_file(script_path)
      :ok
    rescue
      error ->
        {:error, "#{error.__struct__}: #{Exception.message(error)}"}
    catch
      :exit, reason ->
        {:error, "Process exited: #{inspect(reason)}"}
      
      :throw, value ->
        {:error, "Thrown value: #{inspect(value)}"}
    end
  end
end

# Show usage if --help is passed
case System.argv() do
  ["--help"] ->
    IO.puts("Arsenal Demo Runner")
    IO.puts("==================")
    IO.puts("")
    IO.puts("Usage:")
    IO.puts("  elixir examples/run_all_demos.exs          # Run all demos")
    IO.puts("  elixir examples/run_basic_operations.exs   # Basic operations only")
    IO.puts("  elixir examples/run_analytics_demo.exs     # Analytics only")
    IO.puts("  elixir examples/run_process_demo.exs       # Process management only")
    IO.puts("")
    IO.puts("Each demo is self-contained and showcases different Arsenal capabilities.")
    IO.puts("The demos will start Arsenal automatically and demonstrate real functionality.")
    
  _ ->
    # Run all demos
    AllDemosRunner.run()
end