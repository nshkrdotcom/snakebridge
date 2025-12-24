# SnakeBridge: Generalized Python Adapter Development Plan

**Created:** November 25, 2025
**Goal:** Build comprehensive, test-driven Python adapters for major packages
**Approach:** Test-Driven Development (TDD) with incremental delivery

---

## Executive Summary

SnakeBridge already has a powerful generic adapter that works with ANY Python library via introspection. This plan focuses on:

1. **Strengthening the foundation** - Fill testing gaps, improve type system
2. **Building specialized adapters** - For packages that benefit from optimization
3. **Creating a comprehensive catalog** - Tested, documented integrations
4. **Generalizing patterns** - Reusable templates for future packages

---

## Current State Analysis

### What Already Works (v0.2.4)
- Generic adapter introspects ANY Python library
- Type system maps Python ↔ Elixir types
- Code generation creates type-safe Elixir modules
- Instance lifecycle management (UUID-based)
- Streaming support (GenAI adapter)
- 164+ tests, 100% pass rate

### Identified Gaps
| Gap | Impact | Priority |
|-----|--------|----------|
| Streaming tests | High | P1 |
| Security/input validation | High | P1 |
| Large data handling (DataFrames) | Medium | P2 |
| Async pattern generalization | Medium | P2 |
| Performance benchmarks | Medium | P3 |
| Cache invalidation tests | Low | P3 |

---

## Phase 1: Foundation Strengthening (Weeks 1-2)

### 1.1 Streaming Infrastructure Tests

**Goal:** Comprehensive test coverage for streaming functionality

**Test Files to Create:**

```
test/unit/streaming/
├── stream_detection_test.exs      # Detect streaming methods
├── stream_generation_test.exs     # Generate streaming wrappers
└── stream_consumption_test.exs    # Consume streaming responses

test/integration/streaming/
├── mock_streaming_test.exs        # Mocked streaming workflows
└── real_streaming_test.exs        # Real Python streaming
```

**Tests to Implement:**

```elixir
# test/unit/streaming/stream_detection_test.exs
defmodule SnakeBridge.StreamDetectionTest do
  use ExUnit.Case, async: true

  describe "detect_streaming_method/1" do
    test "identifies generator functions"
    test "identifies async generator functions"
    test "identifies methods with supports_streaming=true"
    test "returns false for regular functions"
  end
end

# test/unit/streaming/stream_generation_test.exs
defmodule SnakeBridge.StreamGenerationTest do
  use ExUnit.Case, async: true

  describe "generate_streaming_wrapper/2" do
    test "generates Stream.resource/3 for generators"
    test "generates callback-based wrapper for async"
    test "includes backpressure handling"
    test "includes timeout configuration"
  end
end

# test/integration/streaming/mock_streaming_test.exs
defmodule SnakeBridge.MockStreamingTest do
  use ExUnit.Case

  describe "streaming workflow" do
    test "discover streaming library"
    test "generate streaming modules"
    test "consume streaming response with callback"
    test "handle streaming errors gracefully"
    test "backpressure stops Python generator"
  end
end
```

**Implementation Tasks:**
1. Add `supports_streaming` field detection in introspector
2. Add streaming wrapper generation in generator.ex
3. Add Stream.resource/3 based consumption pattern
4. Add backpressure signal to Python adapter

---

### 1.2 Security & Input Validation

**Goal:** Prevent injection attacks and validate all inputs

**Test Files to Create:**

```
test/security/
├── path_validation_test.exs       # Python path sanitization
├── input_validation_test.exs      # Argument validation
└── injection_prevention_test.exs  # Code injection tests
```

**Tests to Implement:**

```elixir
# test/security/path_validation_test.exs
defmodule SnakeBridge.PathValidationTest do
  use ExUnit.Case, async: true

  describe "validate_python_path/1" do
    test "accepts valid module paths" do
      assert :ok = validate("numpy")
      assert :ok = validate("sklearn.ensemble")
    end

    test "rejects paths with shell characters" do
      assert {:error, _} = validate("os; rm -rf /")
      assert {:error, _} = validate("__import__('os')")
    end

    test "rejects paths with code injection" do
      assert {:error, _} = validate("eval('malicious')")
      assert {:error, _} = validate("exec(open('file').read())")
    end

    test "rejects relative imports" do
      assert {:error, _} = validate("..parent.module")
    end
  end
end

# test/security/injection_prevention_test.exs
defmodule SnakeBridge.InjectionPreventionTest do
  use ExUnit.Case, async: true

  describe "sanitize_arguments/1" do
    test "escapes special characters in string args"
    test "validates numeric bounds"
    test "rejects callable arguments"
    test "limits string length"
    test "limits nesting depth"
  end
end
```

**Implementation Tasks:**
1. Add `SnakeBridge.Security` module with validators
2. Add path validation regex: `^[a-zA-Z_][a-zA-Z0-9_.]*$`
3. Add argument sanitization before Python calls
4. Add nesting depth limits (default: 10)
5. Add string length limits (default: 1MB)

---

### 1.3 Type System Enhancements

**Goal:** Support complex Python types for scientific computing

**Types to Add:**

| Python Type | Elixir Representation | Serialization |
|-------------|----------------------|---------------|
| `numpy.ndarray` | `Nx.Tensor.t()` | Arrow IPC |
| `pandas.DataFrame` | `Explorer.DataFrame.t()` | Arrow IPC |
| `pandas.Series` | `Explorer.Series.t()` | Arrow IPC |
| `scipy.sparse.*` | `{:sparse, format, data}` | Custom |
| `torch.Tensor` | `Nx.Tensor.t()` | Arrow IPC |

**Test Files:**

```
test/unit/type_system/
├── numpy_types_test.exs           # NumPy array handling
├── pandas_types_test.exs          # DataFrame/Series handling
├── arrow_serialization_test.exs   # Apache Arrow IPC
└── complex_types_test.exs         # Nested/union types
```

**Tests to Implement:**

```elixir
# test/unit/type_system/numpy_types_test.exs
defmodule SnakeBridge.NumpyTypesTest do
  use ExUnit.Case, async: true

  describe "numpy array handling" do
    test "converts 1D array to Nx tensor" do
      python_array = %{"shape" => [5], "dtype" => "float64", "data" => [1,2,3,4,5]}
      {:ok, tensor} = TypeSystem.from_python(python_array, :ndarray)
      assert Nx.shape(tensor) == {5}
    end

    test "converts 2D array preserving shape" do
      python_array = %{"shape" => [2, 3], "dtype" => "float32", "data" => [[1,2,3],[4,5,6]]}
      {:ok, tensor} = TypeSystem.from_python(python_array, :ndarray)
      assert Nx.shape(tensor) == {2, 3}
    end

    test "handles various dtypes" do
      for dtype <- ["float32", "float64", "int32", "int64", "bool"] do
        # Test conversion for each dtype
      end
    end

    test "uses Arrow IPC for large arrays (>10KB)"
    test "falls back to JSON for small arrays"
  end
end

# test/unit/type_system/pandas_types_test.exs
defmodule SnakeBridge.PandasTypesTest do
  use ExUnit.Case, async: true

  describe "DataFrame handling" do
    test "converts to Explorer.DataFrame"
    test "preserves column types"
    test "handles missing values (NaN, None)"
    test "handles categorical columns"
    test "handles datetime columns"
    test "uses Arrow IPC for transfer"
  end
end
```

**Implementation Tasks:**
1. Add optional `{:nx, "~> 0.7"}` dependency
2. Add optional `{:explorer, "~> 0.9"}` dependency
3. Implement Arrow IPC serialization in Python adapter
4. Add type detection for numpy/pandas objects
5. Add Nx.Tensor ↔ numpy.ndarray conversion
6. Add Explorer.DataFrame ↔ pandas.DataFrame conversion

---

## Phase 2: Scientific Computing Adapters (Weeks 3-5)

### 2.1 NumPy Adapter

**Goal:** Optimized NumPy integration with Nx tensors

**Catalog Entry:**
```elixir
%{
  name: :numpy,
  description: "Numerical computing with N-dimensional arrays",
  category: :scientific,
  pypi_package: "numpy",
  import_name: "numpy",
  version: ">=1.24.0",
  python_requires: ">=3.9",
  adapter: :specialized,  # Specialized for performance
  adapter_module: "snakebridge_adapter.adapters.numpy",
  supports_streaming: false,
  supports_classes: true,
  supports_functions: true,
  elixir_integration: :nx,  # Uses Nx for tensors
  dependencies: ["pyarrow>=14.0"],  # For efficient transfer
  status: :tested
}
```

**Test Files:**

```
test/adapters/numpy/
├── numpy_discovery_test.exs       # Discover numpy structure
├── numpy_functions_test.exs       # Test common functions
├── numpy_arrays_test.exs          # Array creation/manipulation
├── numpy_linalg_test.exs          # Linear algebra
├── numpy_fft_test.exs             # FFT operations
├── numpy_random_test.exs          # Random number generation
└── numpy_performance_test.exs     # Benchmarks
```

**Tests to Implement:**

```elixir
# test/adapters/numpy/numpy_functions_test.exs
defmodule SnakeBridge.Adapters.NumpyFunctionsTest do
  use ExUnit.Case
  @moduletag :numpy

  setup_all do
    {:ok, _} = SnakeBridge.integrate("numpy")
    :ok
  end

  describe "array creation" do
    test "numpy.array creates tensor from list" do
      {:ok, tensor} = Numpy.array([1, 2, 3, 4, 5])
      assert Nx.shape(tensor) == {5}
      assert Nx.to_list(tensor) == [1.0, 2.0, 3.0, 4.0, 5.0]
    end

    test "numpy.zeros creates zero tensor" do
      {:ok, tensor} = Numpy.zeros([3, 3])
      assert Nx.shape(tensor) == {3, 3}
    end

    test "numpy.ones creates ones tensor" do
      {:ok, tensor} = Numpy.ones([2, 4])
      assert Nx.shape(tensor) == {2, 4}
    end

    test "numpy.arange creates range tensor" do
      {:ok, tensor} = Numpy.arange(0, 10, 2)
      assert Nx.to_list(tensor) == [0.0, 2.0, 4.0, 6.0, 8.0]
    end

    test "numpy.linspace creates linear space" do
      {:ok, tensor} = Numpy.linspace(0, 1, 5)
      assert length(Nx.to_list(tensor)) == 5
    end
  end

  describe "mathematical operations" do
    test "numpy.mean calculates mean" do
      {:ok, result} = Numpy.mean([1, 2, 3, 4, 5])
      assert_in_delta result, 3.0, 0.001
    end

    test "numpy.std calculates standard deviation"
    test "numpy.sum sums elements"
    test "numpy.dot performs dot product"
    test "numpy.matmul performs matrix multiplication"
  end

  describe "linear algebra (numpy.linalg)" do
    test "linalg.inv inverts matrix"
    test "linalg.det calculates determinant"
    test "linalg.eig calculates eigenvalues"
    test "linalg.svd performs SVD"
    test "linalg.solve solves linear system"
  end
end

# test/adapters/numpy/numpy_performance_test.exs
defmodule SnakeBridge.Adapters.NumpyPerformanceTest do
  use ExUnit.Case
  @moduletag [:numpy, :benchmark]

  describe "performance benchmarks" do
    test "small array transfer (<1KB) uses JSON" do
      small = List.duplicate(1.0, 100)
      {time_us, {:ok, _}} = :timer.tc(fn -> Numpy.array(small) end)
      assert time_us < 10_000  # <10ms
    end

    test "large array transfer (>1MB) uses Arrow" do
      large = List.duplicate(1.0, 1_000_000)
      {time_us, {:ok, _}} = :timer.tc(fn -> Numpy.array(large) end)
      assert time_us < 1_000_000  # <1s even for 1M elements
    end

    test "matrix multiplication performance" do
      # Compare with Nx.multiply for baseline
    end
  end
end
```

**Python Adapter:**

```python
# priv/python/snakebridge_adapter/adapters/numpy_adapter.py
class NumpyAdapter(ThreadSafeAdapter):
    """Optimized NumPy adapter with Arrow IPC transfer."""

    def __init__(self):
        super().__init__()
        import numpy as np
        import pyarrow as pa
        self.np = np
        self.pa = pa

    @tool(description="Create array and return as Arrow IPC")
    def array(self, data: list, dtype: str = None) -> dict:
        arr = self.np.array(data, dtype=dtype)
        return self._to_arrow_response(arr)

    @tool(description="Perform operation and return result")
    def operation(self, op: str, *args, **kwargs) -> dict:
        func = getattr(self.np, op)
        result = func(*args, **kwargs)
        if isinstance(result, self.np.ndarray):
            return self._to_arrow_response(result)
        return {"success": True, "result": result}

    def _to_arrow_response(self, arr: np.ndarray) -> dict:
        """Convert numpy array to Arrow IPC for efficient transfer."""
        if arr.nbytes < 10_240:  # <10KB
            return {
                "success": True,
                "format": "json",
                "shape": list(arr.shape),
                "dtype": str(arr.dtype),
                "data": arr.tolist()
            }
        else:
            # Use Arrow IPC for large arrays
            tensor = self.pa.Tensor.from_numpy(arr)
            sink = self.pa.BufferOutputStream()
            self.pa.ipc.write_tensor(tensor, sink)
            return {
                "success": True,
                "format": "arrow_ipc",
                "shape": list(arr.shape),
                "dtype": str(arr.dtype),
                "binary": sink.getvalue().to_pybytes()
            }
```

---

### 2.2 Pandas Adapter

**Goal:** DataFrame integration with Explorer

**Test Files:**

```
test/adapters/pandas/
├── pandas_discovery_test.exs      # Discover pandas structure
├── pandas_dataframe_test.exs      # DataFrame operations
├── pandas_series_test.exs         # Series operations
├── pandas_io_test.exs             # CSV, JSON, Parquet I/O
├── pandas_groupby_test.exs        # GroupBy operations
└── pandas_merge_test.exs          # Merge/join operations
```

**Tests to Implement:**

```elixir
# test/adapters/pandas/pandas_dataframe_test.exs
defmodule SnakeBridge.Adapters.PandasDataFrameTest do
  use ExUnit.Case
  @moduletag :pandas

  describe "DataFrame creation" do
    test "creates DataFrame from map" do
      data = %{
        "name" => ["Alice", "Bob", "Charlie"],
        "age" => [25, 30, 35],
        "salary" => [50000.0, 60000.0, 70000.0]
      }
      {:ok, df} = Pandas.DataFrame.new(data)

      assert Explorer.DataFrame.n_rows(df) == 3
      assert Explorer.DataFrame.n_columns(df) == 3
    end

    test "preserves column types" do
      data = %{
        "int_col" => [1, 2, 3],
        "float_col" => [1.1, 2.2, 3.3],
        "str_col" => ["a", "b", "c"],
        "bool_col" => [true, false, true]
      }
      {:ok, df} = Pandas.DataFrame.new(data)

      assert Explorer.DataFrame.dtypes(df)["int_col"] == {:s, 64}
      assert Explorer.DataFrame.dtypes(df)["float_col"] == {:f, 64}
      assert Explorer.DataFrame.dtypes(df)["str_col"] == :string
      assert Explorer.DataFrame.dtypes(df)["bool_col"] == :boolean
    end

    test "handles missing values (None, NaN)" do
      data = %{"col" => [1.0, nil, 3.0, :nan]}
      {:ok, df} = Pandas.DataFrame.new(data)
      # Explorer uses nil for missing values
    end
  end

  describe "DataFrame operations" do
    setup do
      {:ok, df} = create_sample_dataframe()
      {:ok, df: df}
    end

    test "head returns first n rows", %{df: df} do
      {:ok, result} = Pandas.DataFrame.head(df, 5)
      assert Explorer.DataFrame.n_rows(result) == 5
    end

    test "describe returns statistics", %{df: df} do
      {:ok, stats} = Pandas.DataFrame.describe(df)
      assert Map.has_key?(stats, "mean")
      assert Map.has_key?(stats, "std")
    end

    test "filter with query", %{df: df} do
      {:ok, filtered} = Pandas.DataFrame.query(df, "age > 30")
      # Verify filter applied
    end

    test "groupby and aggregate", %{df: df} do
      {:ok, grouped} = Pandas.DataFrame.groupby(df, "department")
      {:ok, result} = Pandas.GroupBy.agg(grouped, %{"salary" => "mean"})
      # Verify aggregation
    end
  end

  describe "I/O operations" do
    test "read_csv loads CSV file"
    test "to_csv exports to CSV"
    test "read_parquet loads Parquet file"
    test "to_parquet exports to Parquet"
    test "read_json loads JSON file"
  end
end
```

---

### 2.3 Scikit-learn Adapter

**Goal:** ML model training and inference

**Test Files:**

```
test/adapters/sklearn/
├── sklearn_discovery_test.exs     # Discover sklearn structure
├── sklearn_preprocessing_test.exs # Preprocessing transformers
├── sklearn_models_test.exs        # Model training/prediction
├── sklearn_pipeline_test.exs      # Pipeline composition
├── sklearn_metrics_test.exs       # Evaluation metrics
└── sklearn_persistence_test.exs   # Model save/load
```

**Tests to Implement:**

```elixir
# test/adapters/sklearn/sklearn_models_test.exs
defmodule SnakeBridge.Adapters.SklearnModelsTest do
  use ExUnit.Case
  @moduletag :sklearn

  describe "classification models" do
    test "LogisticRegression training and prediction" do
      # Training data
      X_train = Nx.tensor([[1, 2], [2, 3], [3, 4], [4, 5]])
      y_train = Nx.tensor([0, 0, 1, 1])

      # Create and train model
      {:ok, model} = Sklearn.LinearModel.LogisticRegression.create()
      {:ok, model} = Sklearn.LinearModel.LogisticRegression.fit(model, X_train, y_train)

      # Predict
      X_test = Nx.tensor([[2.5, 3.5]])
      {:ok, prediction} = Sklearn.LinearModel.LogisticRegression.predict(model, X_test)

      assert prediction in [0, 1]
    end

    test "RandomForestClassifier with hyperparameters" do
      {:ok, model} = Sklearn.Ensemble.RandomForestClassifier.create(%{
        n_estimators: 100,
        max_depth: 5,
        random_state: 42
      })
      # Train and predict...
    end

    test "SVC with different kernels" do
      for kernel <- ["linear", "rbf", "poly"] do
        {:ok, model} = Sklearn.SVM.SVC.create(%{kernel: kernel})
        # Test each kernel...
      end
    end
  end

  describe "regression models" do
    test "LinearRegression training and prediction"
    test "Ridge regression with regularization"
    test "RandomForestRegressor"
    test "GradientBoostingRegressor"
  end

  describe "model persistence" do
    test "save model to file" do
      {:ok, model} = create_trained_model()
      {:ok, path} = Sklearn.Model.save(model, "/tmp/model.pkl")
      assert File.exists?(path)
    end

    test "load model from file" do
      {:ok, model} = Sklearn.Model.load("/tmp/model.pkl")
      {:ok, prediction} = Sklearn.Model.predict(model, X_test)
      # Verify prediction matches original model
    end
  end
end

# test/adapters/sklearn/sklearn_pipeline_test.exs
defmodule SnakeBridge.Adapters.SklearnPipelineTest do
  use ExUnit.Case
  @moduletag :sklearn

  describe "Pipeline composition" do
    test "create pipeline with multiple steps" do
      {:ok, pipeline} = Sklearn.Pipeline.create([
        {"scaler", Sklearn.Preprocessing.StandardScaler},
        {"pca", Sklearn.Decomposition.PCA, %{n_components: 2}},
        {"classifier", Sklearn.LinearModel.LogisticRegression}
      ])

      {:ok, pipeline} = Sklearn.Pipeline.fit(pipeline, X_train, y_train)
      {:ok, predictions} = Sklearn.Pipeline.predict(pipeline, X_test)
    end

    test "ColumnTransformer for mixed types"
    test "GridSearchCV for hyperparameter tuning"
    test "cross_val_score for evaluation"
  end
end
```

---

## Phase 3: AI/ML Framework Adapters (Weeks 6-9)

### 3.1 Unsloth Adapter

**Goal:** Fast LLM fine-tuning (2-5x faster, 80% less VRAM)

**Catalog Entry:**
```elixir
%{
  name: :unsloth,
  description: "Fast LLM fine-tuning with LoRA/QLoRA",
  category: :llm,
  pypi_package: "unsloth",
  version: ">=2024.8",
  adapter: :specialized,
  supports_streaming: true,
  supports_classes: true,
  requires_env: ["HF_TOKEN"],  # HuggingFace token for gated models
  dependencies: ["torch", "transformers", "peft", "bitsandbytes", "trl"],
  gpu_required: true,
  status: :beta
}
```

**Test Files:**

```
test/adapters/unsloth/
├── unsloth_discovery_test.exs     # Discover unsloth structure
├── unsloth_model_test.exs         # Model loading (4-bit, LoRA)
├── unsloth_finetune_test.exs      # Fine-tuning workflows
├── unsloth_inference_test.exs     # Fast inference
├── unsloth_export_test.exs        # Export to GGUF/vLLM
├── unsloth_streaming_test.exs     # Streaming generation
└── unsloth_memory_test.exs        # Memory optimization tests
```

**Tests to Implement:**

```elixir
# test/adapters/unsloth/unsloth_model_test.exs
defmodule SnakeBridge.Adapters.UnslothModelTest do
  use ExUnit.Case
  @moduletag [:unsloth, :external, :gpu]

  describe "model loading" do
    test "load 4-bit quantized model" do
      {:ok, model, tokenizer} = Unsloth.FastLanguageModel.from_pretrained(%{
        model_name: "unsloth/llama-3-8b-bnb-4bit",
        max_seq_length: 2048,
        load_in_4bit: true
      })

      assert model != nil
      assert tokenizer != nil
    end

    test "add LoRA adapters" do
      {:ok, model, tokenizer} = load_base_model()

      {:ok, model} = Unsloth.FastLanguageModel.get_peft_model(model, %{
        r: 16,  # LoRA rank
        target_modules: ["q_proj", "k_proj", "v_proj", "o_proj"],
        lora_alpha: 16,
        lora_dropout: 0,
        bias: "none",
        use_gradient_checkpointing: "unsloth"
      })

      # Verify LoRA layers added
      {:ok, trainable_params} = Unsloth.Model.print_trainable_parameters(model)
      assert trainable_params < 1_000_000  # Only LoRA params trainable
    end

    test "supported models" do
      for model_name <- [
        "unsloth/llama-3-8b-bnb-4bit",
        "unsloth/mistral-7b-bnb-4bit",
        "unsloth/gemma-7b-bnb-4bit",
        "unsloth/phi-3-mini-4k-instruct-bnb-4bit"
      ] do
        {:ok, model, _} = Unsloth.FastLanguageModel.from_pretrained(%{
          model_name: model_name,
          max_seq_length: 512,
          load_in_4bit: true
        })
        assert model != nil
      end
    end
  end
end

# test/adapters/unsloth/unsloth_finetune_test.exs
defmodule SnakeBridge.Adapters.UnslothFinetuneTest do
  use ExUnit.Case
  @moduletag [:unsloth, :external, :gpu, :slow]

  describe "fine-tuning" do
    test "fine-tune with SFTTrainer" do
      {:ok, model, tokenizer} = load_model_with_lora()

      # Prepare dataset
      dataset = [
        %{instruction: "Summarize:", input: "Long text...", output: "Summary"},
        %{instruction: "Translate:", input: "Hello", output: "Hola"}
      ]

      {:ok, trainer} = Unsloth.SFTTrainer.create(%{
        model: model,
        tokenizer: tokenizer,
        train_dataset: dataset,
        dataset_text_field: "text",
        max_seq_length: 2048,
        args: %{
          per_device_train_batch_size: 2,
          gradient_accumulation_steps: 4,
          warmup_steps: 5,
          max_steps: 20,  # Short for test
          learning_rate: 2.0e-4,
          fp16: true,
          logging_steps: 1,
          output_dir: "/tmp/unsloth_test"
        }
      })

      {:ok, stats} = Unsloth.SFTTrainer.train(trainer)
      assert stats.train_loss < 10.0  # Training happened
    end

    test "fine-tune with DPO (Direct Preference Optimization)" do
      {:ok, model, tokenizer} = load_model_with_lora()

      # Preference pairs
      dataset = [
        %{prompt: "Question?", chosen: "Good answer", rejected: "Bad answer"}
      ]

      {:ok, trainer} = Unsloth.DPOTrainer.create(%{
        model: model,
        ref_model: nil,  # Use implicit reference
        tokenizer: tokenizer,
        train_dataset: dataset,
        beta: 0.1
      })

      {:ok, stats} = Unsloth.DPOTrainer.train(trainer)
      assert Map.has_key?(stats, :train_loss)
    end
  end

  describe "memory optimization" do
    test "gradient checkpointing reduces memory" do
      {:ok, model, _} = Unsloth.FastLanguageModel.from_pretrained(%{
        model_name: "unsloth/llama-3-8b-bnb-4bit",
        use_gradient_checkpointing: "unsloth"  # 30% less VRAM
      })

      {:ok, memory_before} = get_gpu_memory()
      # Run forward pass
      {:ok, memory_after} = get_gpu_memory()

      # Memory should be significantly lower with checkpointing
    end
  end
end

# test/adapters/unsloth/unsloth_export_test.exs
defmodule SnakeBridge.Adapters.UnslothExportTest do
  use ExUnit.Case
  @moduletag [:unsloth, :external, :gpu]

  describe "model export" do
    test "export to GGUF for llama.cpp" do
      {:ok, model, tokenizer} = load_finetuned_model()

      {:ok, path} = Unsloth.Model.save_pretrained_gguf(
        model,
        tokenizer,
        "/tmp/model",
        quantization_method: "q4_k_m"
      )

      assert File.exists?(path <> ".gguf")
    end

    test "export merged 16-bit model" do
      {:ok, model, tokenizer} = load_finetuned_model()

      {:ok, path} = Unsloth.Model.save_pretrained_merged(
        model,
        tokenizer,
        "/tmp/model_merged",
        save_method: "merged_16bit"
      )

      assert File.exists?(path)
    end

    test "push to HuggingFace Hub" do
      {:ok, model, tokenizer} = load_finetuned_model()

      {:ok, url} = Unsloth.Model.push_to_hub_merged(
        model,
        tokenizer,
        "username/model-name",
        token: System.get_env("HF_TOKEN")
      )

      assert String.contains?(url, "huggingface.co")
    end
  end
end

---

### 3.2 Demo Adapter

**Goal:** Programmatic LLM prompting framework

**Test Files:**

```
test/adapters/demo/
├── demo_discovery_test.exs        # Discover Demo structure
├── demo_signatures_test.exs       # Signature definitions
├── demo_modules_test.exs          # Predict, ChainOfThought, etc.
├── demo_optimizers_test.exs       # BootstrapFewShot, etc.
├── demo_teleprompters_test.exs    # Teleprompter compilation
└── demo_evaluate_test.exs         # Evaluation metrics
```

**Tests to Implement:**

```elixir
# test/adapters/demo/demo_modules_test.exs
defmodule SnakeBridge.Adapters.DemoModulesTest do
  use ExUnit.Case
  @moduletag [:demo, :external]

  describe "Predict module" do
    test "basic prediction with signature" do
      {:ok, predict} = Demo.Predict.create("question -> answer")
      {:ok, result} = Demo.Predict.forward(predict, %{question: "What is 2+2?"})

      assert Map.has_key?(result, :answer)
    end

    test "prediction with multiple outputs" do
      {:ok, predict} = Demo.Predict.create("question -> answer, confidence")
      {:ok, result} = Demo.Predict.forward(predict, %{question: "Capital of France?"})

      assert Map.has_key?(result, :answer)
      assert Map.has_key?(result, :confidence)
    end
  end

  describe "ChainOfThought module" do
    test "generates reasoning steps" do
      {:ok, cot} = Demo.ChainOfThought.create("question -> answer")
      {:ok, result} = Demo.ChainOfThought.forward(cot, %{question: "What is 15% of 80?"})

      assert Map.has_key?(result, :rationale)
      assert Map.has_key?(result, :answer)
    end
  end

  describe "ReAct module" do
    test "tool-using agent" do
      {:ok, react} = Demo.ReAct.create("question -> answer", tools: [
        %{name: "search", desc: "Search the web"},
        %{name: "calculate", desc: "Do math"}
      ])

      {:ok, result} = Demo.ReAct.forward(react, %{
        question: "What is the GDP of Japan in billions?"
      })
    end
  end
end

# test/adapters/demo/demo_optimizers_test.exs
defmodule SnakeBridge.Adapters.DemoOptimizersTest do
  use ExUnit.Case
  @moduletag [:demo, :external, :slow]

  describe "BootstrapFewShot" do
    test "optimizes module with examples" do
      # Define metric
      {:ok, metric} = Demo.Evaluate.create_metric(fn pred, expected ->
        pred.answer == expected.answer
      end)

      # Training data
      trainset = [
        %{question: "2+2?", answer: "4"},
        %{question: "3*3?", answer: "9"}
      ]

      {:ok, optimizer} = Demo.BootstrapFewShot.create(%{
        metric: metric,
        max_bootstrapped_demos: 4
      })

      {:ok, module} = Demo.Predict.create("question -> answer")
      {:ok, optimized} = Demo.BootstrapFewShot.compile(optimizer, module, trainset)

      # Optimized module should perform better
    end
  end
end
```

---

### 3.3 Transformers Adapter (HuggingFace)

**Goal:** Pre-trained model inference

**Test Files:**

```
test/adapters/transformers/
├── transformers_discovery_test.exs
├── transformers_pipeline_test.exs   # High-level pipelines
├── transformers_models_test.exs     # Model loading
├── transformers_tokenizers_test.exs # Tokenization
└── transformers_generation_test.exs # Text generation
```

**Tests to Implement:**

```elixir
# test/adapters/transformers/transformers_pipeline_test.exs
defmodule SnakeBridge.Adapters.TransformersPipelineTest do
  use ExUnit.Case
  @moduletag [:transformers, :external, :slow]

  describe "sentiment analysis pipeline" do
    test "analyzes text sentiment" do
      {:ok, classifier} = Transformers.Pipeline.create("sentiment-analysis")
      {:ok, result} = Transformers.Pipeline.run(classifier, "I love this product!")

      assert result.label in ["POSITIVE", "NEGATIVE"]
      assert result.score >= 0 and result.score <= 1
    end
  end

  describe "text generation pipeline" do
    test "generates text continuation" do
      {:ok, generator} = Transformers.Pipeline.create("text-generation", %{
        model: "gpt2"
      })
      {:ok, result} = Transformers.Pipeline.run(generator, "Once upon a time")

      assert String.starts_with?(result.generated_text, "Once upon a time")
    end

    test "streaming text generation" do
      {:ok, generator} = Transformers.Pipeline.create("text-generation", %{
        model: "gpt2",
        streaming: true
      })

      tokens = []
      {:ok, _} = Transformers.Pipeline.stream(generator, "Hello", fn token ->
        tokens = [token | tokens]
      end)

      assert length(tokens) > 0
    end
  end

  describe "embeddings pipeline" do
    test "generates text embeddings" do
      {:ok, embedder} = Transformers.Pipeline.create("feature-extraction", %{
        model: "sentence-transformers/all-MiniLM-L6-v2"
      })
      {:ok, embeddings} = Transformers.Pipeline.run(embedder, "Hello world")

      assert is_list(embeddings)
      assert length(hd(embeddings)) == 384  # Model dimension
    end
  end

  describe "question answering pipeline" do
    test "extracts answer from context" do
      {:ok, qa} = Transformers.Pipeline.create("question-answering")
      {:ok, result} = Transformers.Pipeline.run(qa, %{
        question: "What is the capital of France?",
        context: "France is a country in Europe. Its capital is Paris."
      })

      assert result.answer == "Paris"
    end
  end
end
```

---

## Phase 4: Streaming & Async Pattern Generalization (Weeks 10-11)

### 4.1 Generalized Streaming Framework

**Goal:** Reusable streaming patterns for any library

**Architecture:**

```
┌─────────────────────────────────────────────────────────────┐
│                  SnakeBridge.Streaming                       │
├─────────────────────────────────────────────────────────────┤
│  Behaviors:                                                  │
│  - SyncGenerator    → Python generator (yield)              │
│  - AsyncGenerator   → Python async generator (async yield) │
│  - Callback         → Python callbacks to Elixir           │
│  - SSE              → Server-Sent Events                    │
│  - WebSocket        → Bidirectional streaming               │
└─────────────────────────────────────────────────────────────┘
```

**Test Files:**

```
test/streaming/
├── sync_generator_test.exs        # Python generators
├── async_generator_test.exs       # Async generators
├── callback_streaming_test.exs    # Callback-based
├── backpressure_test.exs          # Flow control
├── error_handling_test.exs        # Stream errors
└── composition_test.exs           # Stream pipelines
```

**Tests to Implement:**

```elixir
# test/streaming/sync_generator_test.exs
defmodule SnakeBridge.Streaming.SyncGeneratorTest do
  use ExUnit.Case

  describe "consuming Python generators" do
    test "Stream.resource wraps generator" do
      {:ok, stream} = SnakeBridge.stream("itertools", "count", [0])

      result = stream
      |> Stream.take(5)
      |> Enum.to_list()

      assert result == [0, 1, 2, 3, 4]
    end

    test "generator cleanup on stream close" do
      {:ok, stream} = SnakeBridge.stream("infinite_generator", "run", [])

      # Take only 3 elements, verify Python generator is closed
      _ = stream |> Stream.take(3) |> Enum.to_list()

      # Verify cleanup happened (no resource leak)
    end

    test "error in generator propagates" do
      {:ok, stream} = SnakeBridge.stream("failing_generator", "run", [])

      assert_raise SnakeBridge.StreamError, fn ->
        stream |> Enum.to_list()
      end
    end
  end
end

# test/streaming/backpressure_test.exs
defmodule SnakeBridge.Streaming.BackpressureTest do
  use ExUnit.Case

  describe "backpressure handling" do
    test "slow consumer pauses Python generator" do
      {:ok, stream} = SnakeBridge.stream("fast_producer", "generate", [])

      # Consume slowly
      stream
      |> Stream.each(fn _ -> Process.sleep(100) end)
      |> Stream.take(5)
      |> Stream.run()

      # Verify Python didn't produce more than needed
    end

    test "configurable buffer size" do
      {:ok, stream} = SnakeBridge.stream("producer", "run", [],
        buffer_size: 10,
        overflow: :drop
      )
    end
  end
end
```

---

### 4.2 Async Pattern Library

**Goal:** Handle Python async/await from Elixir

**Patterns to Support:**

| Python Pattern | Elixir Handling |
|---------------|-----------------|
| `async def` | Task.async wrapper |
| `await coroutine` | Blocking wait in worker |
| `async for` | Stream with async iterator |
| `asyncio.gather` | Task.await_many |
| Callback-based | GenServer message passing |

**Tests:**

```elixir
# test/async/coroutine_test.exs
defmodule SnakeBridge.Async.CoroutineTest do
  use ExUnit.Case

  describe "coroutine handling" do
    test "awaits coroutine result" do
      # Python: async def fetch_data(url): ...
      {:ok, result} = SnakeBridge.await("aiohttp_client", "fetch", ["https://example.com"])
      assert is_binary(result)
    end

    test "parallel coroutine execution" do
      urls = ["https://a.com", "https://b.com", "https://c.com"]

      tasks = Enum.map(urls, fn url ->
        Task.async(fn ->
          SnakeBridge.await("aiohttp_client", "fetch", [url])
        end)
      end)

      results = Task.await_many(tasks, 10_000)
      assert length(results) == 3
    end

    test "timeout handling for slow coroutines" do
      assert {:error, :timeout} =
        SnakeBridge.await("slow_service", "fetch", [], timeout: 100)
    end
  end
end
```

---

## Phase 5: Production Hardening & Documentation (Weeks 12-14)

### 5.1 Performance Benchmarks

**Goal:** Establish baseline performance metrics

**Benchmark Suite:**

```elixir
# bench/snakebridge_bench.exs
defmodule SnakeBridgeBench do
  use Benchee

  def run do
    Benchee.run(
      %{
        "discovery_small" => fn -> SnakeBridge.discover("json") end,
        "discovery_large" => fn -> SnakeBridge.discover("numpy") end,
        "generation_10_classes" => fn -> generate_n_classes(10) end,
        "generation_100_classes" => fn -> generate_n_classes(100) end,
        "function_call_simple" => fn -> Json.dumps(%{a: 1}) end,
        "function_call_complex" => fn -> Numpy.matmul(large_matrix, large_matrix) end,
        "array_transfer_1kb" => fn -> transfer_array(1_000) end,
        "array_transfer_1mb" => fn -> transfer_array(1_000_000) end,
        "streaming_100_chunks" => fn -> stream_chunks(100) end,
        "streaming_10000_chunks" => fn -> stream_chunks(10_000) end
      },
      time: 10,
      memory_time: 2,
      formatters: [
        Benchee.Formatters.HTML,
        Benchee.Formatters.Console
      ]
    )
  end
end
```

**Performance Targets:**

| Operation | Target | Acceptable |
|-----------|--------|------------|
| Discovery (small library) | <100ms | <500ms |
| Discovery (large library) | <2s | <5s |
| Function call (simple) | <10ms | <50ms |
| Array transfer 1KB | <5ms | <20ms |
| Array transfer 1MB | <100ms | <500ms |
| Streaming latency/chunk | <5ms | <20ms |
| Code generation (10 classes) | <50ms | <200ms |

---

### 5.2 Documentation

**Documentation Structure:**

```
docs/
├── getting_started.md             # Quick start guide
├── adapters/
│   ├── numpy.md                   # NumPy integration guide
│   ├── pandas.md                  # Pandas integration guide
│   ├── sklearn.md                 # Scikit-learn guide
│   ├── unsloth.md                 # Unsloth fine-tuning guide
│   ├── demo.md                    # Demo guide
│   └── transformers.md            # HuggingFace guide
├── patterns/
│   ├── streaming.md               # Streaming patterns
│   ├── async.md                   # Async handling
│   ├── type_conversion.md         # Type system guide
│   └── error_handling.md          # Error handling
├── advanced/
│   ├── custom_adapters.md         # Writing custom adapters
│   ├── performance_tuning.md      # Performance optimization
│   └── deployment.md              # Production deployment
└── api/
    └── [auto-generated from docs]
```

---

### 5.3 CI/CD Pipeline

**GitHub Actions Workflow:**

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        elixir: [1.16, 1.17]
        otp: [26, 27]
        python: [3.9, 3.11, 3.12]

    steps:
      - uses: actions/checkout@v4

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ matrix.elixir }}
          otp-version: ${{ matrix.otp }}

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python }}

      - name: Install dependencies
        run: |
          mix deps.get
          pip install -e priv/python/
          pip install numpy pandas scikit-learn

      - name: Run unit tests
        run: mix test test/unit

      - name: Run integration tests (mocked)
        run: mix test test/integration --exclude real_python

      - name: Run real Python tests
        run: mix test --only real_python
        env:
          SNAKEPIT_PYTHON: python3

      - name: Run adapter tests
        run: mix test test/adapters
        env:
          SNAKEPIT_PYTHON: python3

  benchmark:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - name: Run benchmarks
        run: mix run bench/snakebridge_bench.exs

      - name: Upload benchmark results
        uses: actions/upload-artifact@v4
        with:
          name: benchmarks
          path: bench/output/
```

---

## Test-Driven Development Workflow

### For Each New Feature:

```
1. WRITE TESTS FIRST
   └── Create test file in appropriate directory
   └── Write failing tests for expected behavior
   └── Run tests, verify they fail

2. IMPLEMENT MINIMUM CODE
   └── Write simplest code to pass tests
   └── Run tests, verify they pass
   └── Refactor if needed

3. ADD EDGE CASES
   └── Add tests for error conditions
   └── Add tests for boundary values
   └── Add property-based tests

4. INTEGRATION TESTS
   └── Test with mocked Snakepit
   └── Test with real Python (tagged)

5. DOCUMENTATION
   └── Add @doc and @moduledoc
   └── Add examples to docs/
   └── Update README if needed
```

### Test Tagging Strategy:

```elixir
# Fast, always run
@moduletag :unit

# Slower, run by default
@moduletag :integration

# Requires Python, skip by default
@moduletag :real_python

# Requires external services
@moduletag :external

# Performance benchmarks
@moduletag :benchmark

# Specific adapter
@moduletag :numpy
@moduletag :pandas
@moduletag :sklearn
@moduletag :unsloth
@moduletag :demo
@moduletag :transformers
```

---

## Summary: Deliverables by Phase

### Phase 1 (Weeks 1-2): Foundation
- [ ] 15+ streaming tests
- [ ] 10+ security tests
- [ ] Type system enhancements for scientific types
- [ ] Arrow IPC serialization

### Phase 2 (Weeks 3-5): Scientific Computing
- [ ] NumPy adapter with 30+ tests
- [ ] Pandas adapter with 25+ tests
- [ ] Scikit-learn adapter with 40+ tests
- [ ] Performance benchmarks for all

### Phase 3 (Weeks 6-9): AI/ML Frameworks
- [ ] Unsloth adapter with 35+ tests (fine-tuning, LoRA, export)
- [ ] Demo adapter with 30+ tests
- [ ] Transformers adapter with 25+ tests
- [ ] Streaming integration for all

### Phase 4 (Weeks 10-11): Patterns
- [ ] Generalized streaming framework
- [ ] Async pattern library
- [ ] 20+ streaming/async tests

### Phase 5 (Weeks 12-14): Production
- [ ] Complete benchmark suite
- [ ] Full documentation
- [ ] CI/CD pipeline
- [ ] v0.3.0 release

---

## Appendix: File Locations

### New Test Files to Create:

```
test/
├── security/
│   ├── path_validation_test.exs
│   ├── input_validation_test.exs
│   └── injection_prevention_test.exs
├── streaming/
│   ├── sync_generator_test.exs
│   ├── async_generator_test.exs
│   ├── backpressure_test.exs
│   └── error_handling_test.exs
├── async/
│   └── coroutine_test.exs
├── adapters/
│   ├── numpy/
│   │   ├── numpy_discovery_test.exs
│   │   ├── numpy_functions_test.exs
│   │   ├── numpy_arrays_test.exs
│   │   └── numpy_performance_test.exs
│   ├── pandas/
│   │   ├── pandas_discovery_test.exs
│   │   ├── pandas_dataframe_test.exs
│   │   └── pandas_io_test.exs
│   ├── sklearn/
│   │   ├── sklearn_discovery_test.exs
│   │   ├── sklearn_models_test.exs
│   │   └── sklearn_pipeline_test.exs
│   ├── unsloth/
│   │   ├── unsloth_model_test.exs
│   │   ├── unsloth_finetune_test.exs
│   │   └── unsloth_export_test.exs
│   ├── demo/
│   │   ├── demo_modules_test.exs
│   │   └── demo_optimizers_test.exs
│   └── transformers/
│       ├── transformers_pipeline_test.exs
│       └── transformers_generation_test.exs
└── unit/
    └── type_system/
        ├── numpy_types_test.exs
        ├── pandas_types_test.exs
        └── arrow_serialization_test.exs
```

### New Source Files to Create:

```
lib/snakebridge/
├── security.ex                    # Input validation
├── streaming/
│   ├── generator.ex               # Generator handling
│   ├── async.ex                   # Async patterns
│   └── backpressure.ex            # Flow control
└── type_system/
    ├── numpy.ex                   # NumPy type handling
    ├── pandas.ex                  # Pandas type handling
    └── arrow.ex                   # Arrow IPC

priv/python/snakebridge_adapter/adapters/
├── numpy_adapter.py               # NumPy optimizations
├── pandas_adapter.py              # Pandas optimizations
├── sklearn_adapter.py             # Scikit-learn adapter
├── unsloth_adapter.py             # Unsloth fine-tuning adapter
├── demo_adapter.py                # Demo adapter
└── transformers_adapter.py        # Transformers adapter
```

---

*This plan provides a comprehensive, test-driven roadmap for building generalized Python adapters in SnakeBridge.*
