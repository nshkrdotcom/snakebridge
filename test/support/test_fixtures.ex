defmodule SnakeBridge.TestFixtures do
  @moduledoc """
  Shared test fixtures for SnakeBridge test suite.
  """

  @doc """
  Generate a unique module suffix for tests to avoid module redefinition warnings.
  Uses a combination of microseconds and random number.
  """
  def unique_module_suffix do
    timestamp = System.system_time(:microsecond)
    random = :rand.uniform(999)
    "T#{timestamp}_#{random}"
  end

  @doc """
  Sample Python class descriptor for testing.
  Accepts optional module_suffix to create unique module names.
  """
  def sample_class_descriptor(module_suffix \\ nil) do
    suffix = if module_suffix, do: "_#{module_suffix}", else: ""

    %{
      name: "Predict#{suffix}",
      python_path: "dspy.Predict#{suffix}",
      docstring: "Basic prediction module without intermediate reasoning.",
      constructor: %{
        parameters: [
          %{
            name: "signature",
            type: %{kind: "primitive", primitive_type: "str"},
            required: true,
            kind: "positional_or_keyword"
          }
        ],
        return_type: %{kind: "primitive", primitive_type: "none"}
      },
      methods: [
        %{
          name: "__call__",
          docstring: "Execute prediction",
          parameters: [],
          return_type: %{
            kind: "dict",
            key_type: %{kind: "primitive", primitive_type: "str"},
            value_type: %{kind: "primitive", primitive_type: "any"}
          },
          supports_streaming: false,
          is_async: false
        }
      ],
      properties: [],
      base_classes: []
    }
  end

  @doc """
  Sample function descriptor for testing.
  """
  def sample_function_descriptor do
    %{
      name: "configure",
      python_path: "dspy.settings.configure",
      docstring: "Configure global DSPy settings",
      parameters: [
        %{
          name: "lm",
          type: %{kind: "primitive", primitive_type: "any"},
          required: false,
          kind: "keyword"
        }
      ],
      return_type: %{kind: "primitive", primitive_type: "none"},
      supports_streaming: false,
      is_pure: false
    }
  end

  @doc """
  Sample SnakeBridge configuration for testing.
  Accepts optional module_suffix to create unique module names (e.g., "Test1" -> TestApp.PredictTest1).
  """
  def sample_config(module_suffix \\ nil) do
    elixir_module =
      if module_suffix do
        String.to_atom("Elixir.TestApp.Predict#{module_suffix}")
      else
        TestApp.Predict
      end

    python_path_suffix = if module_suffix, do: "_#{module_suffix}", else: ""

    %SnakeBridge.Config{
      python_module: "dspy",
      version: "2.5.0",
      introspection: %{
        enabled: true,
        cache_path: "test/fixtures/cache/dspy.json",
        discovery_depth: 2,
        submodules: ["teleprompt"]
      },
      classes: [
        %{
          python_path: "dspy.Predict#{python_path_suffix}",
          elixir_module: elixir_module,
          constructor: %{
            args: %{signature: {:required, :string}},
            session_aware: true
          },
          methods: [
            %{name: "__call__", elixir_name: :call, streaming: false}
          ]
        }
      ],
      functions: [
        %{
          name: "configure",
          python_path: "dspy.settings.configure",
          elixir_name: :configure,
          args: %{lm: {:optional, :any}}
        }
      ]
    }
  end

  @doc """
  Sample introspection response from Python worker.
  Accepts optional module_suffix to create unique module names.
  """
  def sample_introspection_response(module_suffix \\ nil) do
    descriptor = sample_class_descriptor(module_suffix)

    %{
      "library_version" => "2.5.0",
      "classes" => %{
        descriptor.name => descriptor
      },
      "functions" => %{
        "configure" => sample_function_descriptor()
      },
      "descriptor_hash" => :crypto.hash(:sha256, "sample") |> Base.encode16(case: :lower),
      "cache_timestamp" => System.system_time(:second)
    }
  end

  @doc """
  Sample function module descriptor for testing.
  """
  def sample_function_module_descriptor do
    %{
      name: "JsonFunctions",
      python_path: "json",
      docstring: "Python's built-in JSON encoder/decoder",
      elixir_module: Json,
      functions: [
        %{
          name: "dumps",
          python_path: "json.dumps",
          elixir_name: :dumps,
          docstring: "Serialize object to JSON",
          parameters: [
            %{name: "obj", required: true, type: %{kind: "primitive", primitive_type: "any"}}
          ]
        },
        %{
          name: "loads",
          python_path: "json.loads",
          elixir_name: :loads,
          docstring: "Deserialize JSON to object",
          parameters: [
            %{name: "s", required: true, type: %{kind: "primitive", primitive_type: "str"}}
          ]
        }
      ]
    }
  end

  @doc """
  Sample type descriptors for various Python types.
  """
  def sample_type_descriptors do
    %{
      int: %{kind: "primitive", primitive_type: "int"},
      str: %{kind: "primitive", primitive_type: "str"},
      float: %{kind: "primitive", primitive_type: "float"},
      bool: %{kind: "primitive", primitive_type: "bool"},
      list_int: %{kind: "list", element_type: %{kind: "primitive", primitive_type: "int"}},
      dict_str_any: %{
        kind: "dict",
        key_type: %{kind: "primitive", primitive_type: "str"},
        value_type: %{kind: "primitive", primitive_type: "any"}
      },
      union_int_str: %{
        kind: "union",
        union_types: [
          %{kind: "primitive", primitive_type: "int"},
          %{kind: "primitive", primitive_type: "str"}
        ]
      },
      optional_str: %{
        kind: "union",
        union_types: [
          %{kind: "primitive", primitive_type: "str"},
          %{kind: "primitive", primitive_type: "none"}
        ]
      }
    }
  end
end
