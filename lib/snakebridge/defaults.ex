defmodule SnakeBridge.Defaults do
  @moduledoc """
  Centralized defaults for all configurable values in SnakeBridge.

  All values can be overridden via `Application.get_env(:snakebridge, key)`.

  ## Configuration Options

  ### Introspection

  - `:introspector_timeout` - Timeout in ms for introspecting Python modules (default: `30_000`)
  - `:introspector_max_concurrency` - Max concurrent introspection tasks (default: `System.schedulers_online()`)

  ### Wheel Selector (PyTorch/CUDA)

  - `:pytorch_index_base_url` - Base URL for PyTorch wheel index (default: `"https://download.pytorch.org/whl/"`)
  - `:cuda_thresholds` - CUDA version to variant mapping (default: `[{"cu124", 124}, {"cu121", 120}, {"cu118", 117}]`)

  ### Session Lifecycle

  - `:session_max_refs` - Maximum refs per session (default: `10_000`)
  - `:session_ttl_seconds` - Session time-to-live in seconds (default: `3600`)

  ### Code Generation

  - `:variadic_max_arity` - Max arity for variadic wrappers (default: `8`)
  - `:generated_dir` - Directory for generated code (default: `"lib/snakebridge_generated"`)
  - `:metadata_dir` - Directory for metadata files (default: `".snakebridge"`)

  ### Protocol

  - `:protocol_version` - Wire protocol version (default: `1`)
  - `:min_supported_version` - Minimum supported protocol version (default: `1`)

  ### Runtime Timeouts

  Runtime timeout configuration is nested under the `:runtime` key:

  - `:timeout_profile` - Default profile for calls (default: `:default` for calls, `:streaming` for streams)
  - `:default_timeout` - Default unary call timeout in ms (default: `120_000`)
  - `:default_stream_timeout` - Default stream timeout in ms (default: `1_800_000`)
  - `:library_profiles` - Map of library names to profiles (default: `%{}`)
  - `:profiles` - Map of profile names to timeout settings

  Built-in profiles:
  - `:default` - 120s timeout for regular calls
  - `:streaming` - 120s timeout, 30min stream_timeout
  - `:ml_inference` - 10min timeout for ML/LLM workloads
  - `:batch_job` - infinity timeout for long-running jobs

  ## Example Configuration

      config :snakebridge,
        introspector_timeout: 60_000,
        pytorch_index_base_url: "https://my-mirror.example.com/pytorch/",
        cuda_thresholds: [
          {"cu126", 126},
          {"cu124", 124},
          {"cu121", 120},
          {"cu118", 117}
        ],
        session_max_refs: 50_000,
        session_ttl_seconds: 7200,
        runtime: [
          timeout_profile: :default,
          library_profiles: %{
            "transformers" => :ml_inference,
            "torch" => :batch_job
          },
          profiles: %{
            default: [timeout: 120_000],
            ml_inference: [timeout: 600_000, stream_timeout: 1_800_000],
            batch_job: [timeout: :infinity, stream_timeout: :infinity]
          }
        ]
  """

  # Introspection
  def introspector_timeout, do: get(:introspector_timeout, 30_000)

  def introspector_max_concurrency,
    do: get(:introspector_max_concurrency, System.schedulers_online())

  # Wheel selector
  def pytorch_index_base_url,
    do: get(:pytorch_index_base_url, "https://download.pytorch.org/whl/")

  def cuda_thresholds do
    get(:cuda_thresholds, [
      {"cu124", 124},
      {"cu121", 120},
      {"cu118", 117}
    ])
  end

  # Session context
  def session_max_refs, do: get(:session_max_refs, 10_000)
  def session_ttl_seconds, do: get(:session_ttl_seconds, 3600)

  # Protocol
  def protocol_version, do: get(:protocol_version, 1)
  def min_supported_version, do: get(:min_supported_version, 1)

  # Code generation
  def variadic_max_arity, do: get(:variadic_max_arity, 8)
  def generated_dir, do: get(:generated_dir, "lib/snakebridge_generated")
  def generated_layout, do: get(:generated_layout, :split)
  def metadata_dir, do: get(:metadata_dir, ".snakebridge")

  # ============================================================================
  # Runtime Timeout Configuration
  # ============================================================================

  @default_runtime_profiles %{
    default: [timeout: 120_000],
    streaming: [timeout: 120_000, stream_timeout: 1_800_000],
    ml_inference: [timeout: 600_000, stream_timeout: 1_800_000],
    batch_job: [timeout: :infinity, stream_timeout: :infinity]
  }

  @doc """
  Returns the runtime configuration keyword list.
  """
  @spec runtime_config() :: keyword()
  def runtime_config, do: Application.get_env(:snakebridge, :runtime, [])

  @doc """
  Returns the timeout profile for a given call kind.

  Call kinds:
  - `:call` - Regular function calls (default: `:default`)
  - `:stream` - Streaming calls (default: `:streaming`)
  """
  @spec runtime_timeout_profile(atom()) :: atom()
  def runtime_timeout_profile(call_kind \\ :call) do
    runtime_config()
    |> Keyword.get(:timeout_profile, default_timeout_profile(call_kind))
  end

  @doc """
  Returns configured library-to-profile mappings.

  Example:
      config :snakebridge, runtime: [
        library_profiles: %{
          "transformers" => :ml_inference,
          "torch" => :batch_job
        }
      ]
  """
  @spec runtime_library_profiles() :: map()
  def runtime_library_profiles do
    runtime_config() |> Keyword.get(:library_profiles, %{})
  end

  @doc """
  Returns all timeout profiles.

  Default profiles:
  - `:default` - 120s timeout for regular calls
  - `:streaming` - 120s timeout, 30min stream_timeout
  - `:ml_inference` - 10min timeout for ML/LLM workloads
  - `:batch_job` - infinity timeout for long-running jobs
  """
  @spec runtime_profiles() :: map()
  def runtime_profiles do
    runtime_config() |> Keyword.get(:profiles, @default_runtime_profiles)
  end

  @doc """
  Returns the default unary call timeout in milliseconds.
  """
  @spec runtime_default_timeout() :: timeout()
  def runtime_default_timeout do
    runtime_config() |> Keyword.get(:default_timeout, 120_000)
  end

  @doc """
  Returns the default stream timeout in milliseconds.
  """
  @spec runtime_default_stream_timeout() :: timeout()
  def runtime_default_stream_timeout do
    runtime_config() |> Keyword.get(:default_stream_timeout, 1_800_000)
  end

  defp default_timeout_profile(:stream), do: :streaming
  defp default_timeout_profile(_), do: :default

  @doc """
  Returns all current configuration values as a map.
  """
  @spec all() :: map()
  def all do
    %{
      introspector_timeout: introspector_timeout(),
      introspector_max_concurrency: introspector_max_concurrency(),
      pytorch_index_base_url: pytorch_index_base_url(),
      cuda_thresholds: cuda_thresholds(),
      session_max_refs: session_max_refs(),
      session_ttl_seconds: session_ttl_seconds(),
      protocol_version: protocol_version(),
      min_supported_version: min_supported_version(),
      variadic_max_arity: variadic_max_arity(),
      generated_dir: generated_dir(),
      generated_layout: generated_layout(),
      metadata_dir: metadata_dir(),
      runtime_default_timeout: runtime_default_timeout(),
      runtime_default_stream_timeout: runtime_default_stream_timeout(),
      runtime_timeout_profile: runtime_timeout_profile()
    }
  end

  defp get(key, default) do
    Application.get_env(:snakebridge, key, default)
  end
end
