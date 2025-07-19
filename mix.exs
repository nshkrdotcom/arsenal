defmodule Arsenal.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/arsenal"

  def project do
    [
      app: :arsenal,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :eex],
      mod: {Arsenal, []}
    ]
  end

  defp deps do
    [
      # Documentation
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},

      # JSON encoding (optional - users can provide their own)
      {:jason, "~> 1.4", optional: true},

      # Telemetry for metrics
      {:telemetry, "~> 1.0"},

      # Code analysis
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # Testing
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:supertester, github: "nshkrdotcom/supertester", only: :test}
    ]
  end

  defp description do
    """
    A metaprogramming framework for building REST APIs from OTP operations with automatic endpoint generation, parameter validation, and OpenAPI documentation.
    """
  end

  defp package do
    [
      name: "arsenal",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/arsenal"
      },
      maintainers: ["NSHKr <ZeroTrust@NSHkr.com>"],
      files: ~w(lib assets .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      exclude_patterns: ["docs/**"]
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "Arsenal",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"],
      assets: %{"assets" => "assets"},
      logo: "assets/arsenal-logo.svg",
      groups_for_modules: [
        Core: [
          Arsenal,
          Arsenal.Operation,
          Arsenal.Registry
        ],
        "Example Operations": [
          Arsenal.Operations.GetProcessInfo,
          Arsenal.Operations.ListProcesses
        ]
      ]
    ]
  end
end
