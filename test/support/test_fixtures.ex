defmodule SnakeBridge.TestFixtures do
  @moduledoc """
  Shared test fixtures for SnakeBridge test suite.
  """

  @doc """
  Sample Python class descriptor for testing.
  """
  def sample_class_descriptor do
    %{
      name: "Predict",
      python_path: "dspy.Predict",
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
  """
  def sample_config do
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
          python_path: "dspy.Predict",
          elixir_module: TestApp.Predict,
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
          python_path: "dspy.settings.configure",
          elixir_name: :configure,
          args: %{lm: {:optional, :any}}
        }
      ]
    }
  end

  @doc """
  Sample introspection response from Python worker.
  """
  def sample_introspection_response do
    %{
      "library_version" => "2.5.0",
      "classes" => %{
        "Predict" => sample_class_descriptor()
      },
      "functions" => %{
        "configure" => sample_function_descriptor()
      },
      "descriptor_hash" => :crypto.hash(:sha256, "sample") |> Base.encode16(case: :lower),
      "cache_timestamp" => System.system_time(:second)
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
