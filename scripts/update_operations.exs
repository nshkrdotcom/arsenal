#!/usr/bin/env elixir

# Script to update existing operations to use compatibility mode
# Run with: elixir scripts/update_operations.exs

defmodule UpdateOperations do
  @operations_dir "lib/arsenal/operations"
  
  def run do
    IO.puts("Updating Arsenal operations to use compatibility mode...")
    
    files = find_operation_files(@operations_dir)
    IO.puts("Found #{length(files)} operation files")
    
    Enum.each(files, &update_file/1)
    
    IO.puts("\nDone! All operations updated.")
  end
  
  defp find_operation_files(dir) do
    Path.wildcard("#{dir}/**/*.ex")
    |> Enum.filter(fn file ->
      content = File.read!(file)
      String.contains?(content, "use Arsenal.Operation")
    end)
  end
  
  defp update_file(file) do
    content = File.read!(file)
    
    # Replace "use Arsenal.Operation" with "use Arsenal.Operation, compat: true"
    new_content = String.replace(
      content,
      "use Arsenal.Operation",
      "use Arsenal.Operation, compat: true"
    )
    
    if content != new_content do
      File.write!(file, new_content)
      IO.puts("✓ Updated #{file}")
    else
      IO.puts("- Skipped #{file} (already updated)")
    end
  end
end

UpdateOperations.run()