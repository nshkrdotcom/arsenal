# Ensure Arsenal application is started before tests
Application.ensure_all_started(:arsenal)

# Configure logger to reduce noise during tests
require Logger
Logger.configure(level: :warning)

ExUnit.start()

# Reset logger level after ExUnit starts to allow capture_log to work properly
Logger.configure(level: :info)
