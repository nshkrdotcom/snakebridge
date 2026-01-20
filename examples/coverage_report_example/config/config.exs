import Config

config :snakebridge,
  verbose: false,
  strict: false,
  coverage_report: [output_dir: "coverage_reports"],
  docs: [source: :python, cache_enabled: false]

config :logger,
  level: :warning

config :snakepit,
  auto_install_python_deps: true
