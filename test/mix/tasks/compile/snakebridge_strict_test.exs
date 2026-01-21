defmodule Mix.Tasks.Compile.SnakebridgeStrictTest do
  use ExUnit.Case

  alias Mix.Tasks.Compile.Snakebridge

  describe "strict mode verification" do
    @describetag :tmp_dir
    test "fails when generated file is missing", %{tmp_dir: tmp_dir} do
      config = %SnakeBridge.Config{
        libraries: [
          %SnakeBridge.Config.Library{
            name: :testlib,
            python_name: "testlib",
            module_name: Testlib
          }
        ],
        generated_dir: Path.join(tmp_dir, "generated"),
        generated_layout: :single,
        metadata_dir: Path.join(tmp_dir, "metadata"),
        strict: true
      }

      # Create manifest but NOT the generated file
      File.mkdir_p!(config.metadata_dir)
      manifest = %{"version" => "0.7.0", "symbols" => %{}, "classes" => %{}}
      File.write!(Path.join(config.metadata_dir, "manifest.json"), Jason.encode!(manifest))

      assert_raise SnakeBridge.CompileError, ~r/Generated files missing/, fn ->
        Snakebridge.verify_generated_files_exist!(config)
      end
    end

    test "fails when expected function missing from generated file", %{tmp_dir: tmp_dir} do
      config = %SnakeBridge.Config{
        libraries: [
          %SnakeBridge.Config.Library{
            name: :testlib,
            python_name: "testlib",
            module_name: Testlib
          }
        ],
        generated_dir: Path.join(tmp_dir, "generated"),
        generated_layout: :single,
        metadata_dir: Path.join(tmp_dir, "metadata"),
        strict: true
      }

      # Create generated file WITHOUT the expected function
      File.mkdir_p!(config.generated_dir)

      File.write!(
        Path.join(config.generated_dir, "testlib.ex"),
        "defmodule Testlib do\nend"
      )

      # Create manifest WITH the function
      manifest = %{
        "version" => "0.7.0",
        "symbols" => %{
          "Testlib.compute/1" => %{
            "name" => "compute",
            "python_module" => "testlib",
            "module" => "Testlib"
          }
        },
        "classes" => %{}
      }

      File.mkdir_p!(config.metadata_dir)
      File.write!(Path.join(config.metadata_dir, "manifest.json"), Jason.encode!(manifest))

      assert_raise SnakeBridge.CompileError, ~r/Missing functions/, fn ->
        Snakebridge.verify_symbols_present!(config, manifest)
      end
    end

    test "passes when all symbols present in generated file", %{tmp_dir: tmp_dir} do
      config = %SnakeBridge.Config{
        libraries: [
          %SnakeBridge.Config.Library{
            name: :testlib,
            python_name: "testlib",
            module_name: Testlib
          }
        ],
        generated_dir: Path.join(tmp_dir, "generated"),
        generated_layout: :single,
        metadata_dir: Path.join(tmp_dir, "metadata"),
        strict: true
      }

      # Create generated file WITH the expected function
      File.mkdir_p!(config.generated_dir)

      File.write!(
        Path.join(config.generated_dir, "testlib.ex"),
        """
        defmodule Testlib do
          def compute(x, opts \\\\ []) do
            SnakeBridge.Runtime.call(__MODULE__, :compute, [x], opts)
          end
        end
        """
      )

      # Create manifest WITH the function
      manifest = %{
        "version" => "0.7.0",
        "symbols" => %{
          "Testlib.compute/1" => %{
            "name" => "compute",
            "python_module" => "testlib",
            "module" => "Testlib"
          }
        },
        "classes" => %{}
      }

      File.mkdir_p!(config.metadata_dir)
      File.write!(Path.join(config.metadata_dir, "manifest.json"), Jason.encode!(manifest))

      # Should not raise
      assert :ok == Snakebridge.verify_generated_files_exist!(config)
      assert :ok == Snakebridge.verify_symbols_present!(config, manifest)
    end

    test "fails when expected class module is missing", %{tmp_dir: tmp_dir} do
      config = %SnakeBridge.Config{
        libraries: [
          %SnakeBridge.Config.Library{
            name: :testlib,
            python_name: "testlib",
            module_name: Testlib
          }
        ],
        generated_dir: Path.join(tmp_dir, "generated"),
        generated_layout: :single,
        metadata_dir: Path.join(tmp_dir, "metadata"),
        strict: true
      }

      File.mkdir_p!(config.generated_dir)

      File.write!(
        Path.join(config.generated_dir, "testlib.ex"),
        """
        defmodule Testlib do
          def compute(x, opts \\\\ []) do
            SnakeBridge.Runtime.call(__MODULE__, :compute, [x], opts)
          end
        end
        """
      )

      manifest = %{
        "version" => "0.7.0",
        "symbols" => %{},
        "classes" => %{
          "Testlib.Widget" => %{
            "module" => "Testlib.Widget",
            "class" => "Widget",
            "python_module" => "testlib",
            "methods" => [%{"name" => "__init__", "parameters" => []}],
            "attributes" => ["size"]
          }
        }
      }

      assert_raise SnakeBridge.CompileError, ~r/Missing classes/, fn ->
        Snakebridge.verify_symbols_present!(config, manifest)
      end
    end

    test "fails when expected class members are missing", %{tmp_dir: tmp_dir} do
      config = %SnakeBridge.Config{
        libraries: [
          %SnakeBridge.Config.Library{
            name: :testlib,
            python_name: "testlib",
            module_name: Testlib
          }
        ],
        generated_dir: Path.join(tmp_dir, "generated"),
        generated_layout: :single,
        metadata_dir: Path.join(tmp_dir, "metadata"),
        strict: true
      }

      File.mkdir_p!(config.generated_dir)

      File.write!(
        Path.join(config.generated_dir, "testlib.ex"),
        """
        defmodule Testlib do
          defmodule Widget do
            def new(opts \\\\ []), do: :ok
          end
        end
        """
      )

      manifest = %{
        "version" => "0.7.0",
        "symbols" => %{},
        "classes" => %{
          "Testlib.Widget" => %{
            "module" => "Testlib.Widget",
            "class" => "Widget",
            "python_module" => "testlib",
            "methods" => [%{"name" => "__init__", "parameters" => []}, %{"name" => "scale"}],
            "attributes" => ["size"]
          }
        }
      }

      assert_raise SnakeBridge.CompileError, ~r/Missing class members/, fn ->
        Snakebridge.verify_symbols_present!(config, manifest)
      end
    end

    test "passes when class modules and members are present", %{tmp_dir: tmp_dir} do
      config = %SnakeBridge.Config{
        libraries: [
          %SnakeBridge.Config.Library{
            name: :testlib,
            python_name: "testlib",
            module_name: Testlib
          }
        ],
        generated_dir: Path.join(tmp_dir, "generated"),
        generated_layout: :single,
        metadata_dir: Path.join(tmp_dir, "metadata"),
        strict: true
      }

      File.mkdir_p!(config.generated_dir)

      File.write!(
        Path.join(config.generated_dir, "testlib.ex"),
        """
        defmodule Testlib do
          defmodule Widget do
            def new(opts \\\\ []), do: :ok
            def scale(ref, opts \\\\ []), do: {:ok, ref}
            def size(ref), do: {:ok, ref}
          end
        end
        """
      )

      manifest = %{
        "version" => "0.7.0",
        "symbols" => %{},
        "classes" => %{
          "Testlib.Widget" => %{
            "module" => "Testlib.Widget",
            "class" => "Widget",
            "python_module" => "testlib",
            "methods" => [%{"name" => "__init__", "parameters" => []}, %{"name" => "scale"}],
            "attributes" => ["size"]
          }
        }
      }

      assert :ok == Snakebridge.verify_symbols_present!(config, manifest)
    end
  end

  describe "strict mode verification (split layout)" do
    @describetag :tmp_dir
    test "fails when split layout files are missing", %{tmp_dir: tmp_dir} do
      config = %SnakeBridge.Config{
        libraries: [
          %SnakeBridge.Config.Library{
            name: :testlib,
            python_name: "testlib",
            module_name: Testlib
          }
        ],
        generated_dir: Path.join(tmp_dir, "generated"),
        generated_layout: :split,
        metadata_dir: Path.join(tmp_dir, "metadata"),
        strict: true
      }

      manifest = %{
        "version" => "0.7.0",
        "symbols" => %{
          "Testlib.Sub.compute/1" => %{
            "name" => "compute",
            "python_module" => "testlib.sub",
            "module" => "Testlib.Sub"
          }
        },
        "classes" => %{}
      }

      assert_raise SnakeBridge.CompileError, ~r/Generated files missing/, fn ->
        Snakebridge.verify_generated_files_exist!(config, manifest)
      end
    end

    test "passes when symbols are present across split layout files", %{tmp_dir: tmp_dir} do
      config = %SnakeBridge.Config{
        libraries: [
          %SnakeBridge.Config.Library{
            name: :testlib,
            python_name: "testlib",
            module_name: Testlib
          }
        ],
        generated_dir: Path.join(tmp_dir, "generated"),
        generated_layout: :split,
        metadata_dir: Path.join(tmp_dir, "metadata"),
        strict: true
      }

      File.mkdir_p!(Path.join(config.generated_dir, "testlib"))
      File.mkdir_p!(Path.join(config.generated_dir, "testlib/sub"))

      File.write!(
        Path.join(config.generated_dir, "testlib/__init__.ex"),
        """
        defmodule Testlib do
          @moduledoc false
        end
        """
      )

      File.write!(
        Path.join(config.generated_dir, "testlib/sub/__init__.ex"),
        """
        defmodule Testlib.Sub do
          def compute(x, opts \\\\ []) do
            SnakeBridge.Runtime.call(__MODULE__, :compute, [x], opts)
          end
        end
        """
      )

      File.write!(
        Path.join(config.generated_dir, "testlib/widget.ex"),
        """
        defmodule Testlib.Widget do
          def new(opts \\\\ []), do: :ok
          def scale(ref, opts \\\\ []), do: {:ok, ref}
          def size(ref), do: {:ok, ref}
        end
        """
      )

      manifest = %{
        "version" => "0.7.0",
        "symbols" => %{
          "Testlib.Sub.compute/1" => %{
            "name" => "compute",
            "python_module" => "testlib.sub",
            "module" => "Testlib.Sub"
          }
        },
        "classes" => %{
          "Testlib.Widget" => %{
            "module" => "Testlib.Widget",
            "class" => "Widget",
            "python_module" => "testlib",
            "methods" => [%{"name" => "__init__", "parameters" => []}, %{"name" => "scale"}],
            "attributes" => ["size"]
          }
        }
      }

      assert :ok == Snakebridge.verify_generated_files_exist!(config, manifest)
      assert :ok == Snakebridge.verify_symbols_present!(config, manifest)
    end
  end
end
