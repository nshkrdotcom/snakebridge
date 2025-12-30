defmodule SnakeBridge.Generator.DottedLibraryTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Generator

  test "submodules drop the full dotted library prefix and keep library metadata" do
    library = %SnakeBridge.Config.Library{
      name: :torch_nn,
      python_name: "torch.nn",
      module_name: Torch.NN,
      version: "~> 2.0"
    }

    functions = [
      %{
        "name" => "relu",
        "python_module" => "torch.nn.functional",
        "parameters" => []
      }
    ]

    source = Generator.render_library(library, functions, [], version: "3.0.0")

    assert source =~ "defmodule Torch.NN do"
    assert source =~ "defmodule Functional do"
    assert source =~ "def __snakebridge_python_name__, do: \"torch.nn.functional\""
    assert source =~ "def __snakebridge_library__, do: \"torch.nn\""
    refute source =~ "defmodule Nn.Functional"
  end
end
