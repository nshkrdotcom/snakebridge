defmodule SignatureShowcaseExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :signature_showcase_example,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:snakebridge] ++ Mix.compilers()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:snakebridge, path: "../..", libraries: libraries()}
    ]
  end

  defp libraries do
    base = [
      signature_showcase: [
        version: :stdlib,
        python_name: "signature_showcase",
        module_name: SignatureShowcase,
        include: ["optional_args", "keyword_only", "variadic", "class"]
      ],
      math: [
        version: :stdlib,
        python_name: "math",
        module_name: Math,
        include: ["sqrt"]
      ]
    ]

    if System.get_env("SNAKEBRIDGE_EXAMPLE_NUMPY") == "1" do
      base ++
        [
          numpy: [
            version: :stdlib,
            python_name: "numpy",
            module_name: Numpy,
            include: ["sqrt"]
          ]
        ]
    else
      base
    end
  end
end
