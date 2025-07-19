# Configure ExUnit
ExUnit.configure(exclude: [:pending], capture_log: true)

# Ensure Arsenal application is started before tests
Application.ensure_all_started(:arsenal)

ExUnit.start()
