# Phase 1 v2 Plan (Foundation Slice)

**Status:** Draft plan with updated dependencies (Crucible removed, hfdatasetx + chz_ex only)  
**Reference slice:** `tinker_cookbook/recipes/sl_basic.py`

This document re‑baselines Phase 1 after the datasets library rename and tightens the plan so the Phase 1 “slice” is implementable without hidden gaps.

---

## 0) Critical Review of the Current Phase 1 Plan

The previous Phase 1 plan (Foundation + `sl_basic`) is directionally correct, but it had two foundational issues:

1) **Wrong dataset dependency**  
   The plan referenced `CrucibleDatasets`. That library is now out of date and should be removed from all plans. The Phase 1 dataset layer must be built on **hfdatasetx** (current repo path: `hf_datasets_ex`), not Crucible.

2) **Missing “adapter” detail for dataset semantics**  
   The Python code relies on `datasets.Dataset` behavior: `load_dataset`, `DatasetDict`, `shuffle`, `take`, `skip`, `select`, and `to_list`. The old plan did not specify how we would recreate these semantics in Elixir. Phase 1 must include a clear adapter mapping for the dataset API so the supervised dataset pipeline is deterministic and testable.

The updated plan below fixes both.

---

## 1) Evidence: What Phase 1 Actually Uses (Python Reference)

### 1.1 Datasets usage in the Phase 1 slice
From `tinker_cookbook/recipes/sl_basic.py` and `tinker_cookbook/recipes/chat_sl/chat_datasets.py`:

- `datasets.load_dataset("HuggingFaceH4/no_robots")`
- `DatasetDict` access (`dataset["train"]`, `dataset["test"]`)
- `shuffle(seed=0)`
- `take(n)` / `skip(n)`
- For batching: `SupervisedDatasetFromHFDataset.get_batch/1` uses:
  - `select(range(...))`  
  - `rows.to_list()`
- For local JSONL: `datasets.Dataset.from_list(conversations)`

**Phase 1 requires** these exact behaviors to run `sl_basic`:
- Load dataset by repo_id
- Access train/test splits
- Shuffle deterministically by seed
- Select slices and batch deterministically
- Convert to list of maps
- Build a dataset from a list (JSONL)

### 1.2 chz usage in the Phase 1 slice
From `sl_basic.py`, `supervised/types.py`, and `supervised/train.py`:

- `@chz.chz` dataclasses for configs
- Builder pattern: config classes are callable (`__call__`) and return runtime objects
- `chz.Blueprint(...).apply(...)` to set defaults and override via CLI
- `chz.nested_entrypoint` / `Blueprint.make_from_argv`
- `chz.field(munger=...)` used to normalize values (e.g., `log_path`)

**Phase 1 requires** these exact behaviors in **chz_ex**:
- Schema definitions for configs
- Nested config + builder construction
- Blueprint apply + CLI parsing
- Basic mungers and defaults

---

## 2) Updated Dependencies (Phase 1 Only)

### Required
- **hfdatasetx** (current repo: `hf_datasets_ex`)
  - Must provide `load_dataset/2`, `DatasetDict`, `Dataset`, and dataset ops (`shuffle`, `take`, `skip`, `select`, `to_list` or equivalent).
- **chz_ex**
  - Must provide schema definitions, blueprint parsing, nested configs.
- **snakebridge** (only for Phase 2+; no direct dependency in Phase 1 `sl_basic`)

### Explicitly removed
- **CrucibleDatasets** (delete all references in docs and plans)

---

## 3) Phase 1 v2 Implementation Plan (Detailed)

### Step 1: Replace all Crucible references in Phase 1 docs

**Why:** The plan must reflect the active dataset library or it will diverge immediately.

**Actions:**
- Update any Phase 1 docs mentioning `CrucibleDatasets` to `hfdatasetx` (or `HfDatasetsEx` module).
- Make this a one‑time sweep now so Phase 1 work does not fragment.

**Done when:**
- No Phase 1 docs reference Crucible at all.

---

### Step 2: Define the Dataset Adapter Contract (Phase 1 scope)

**Why:** We need deterministic dataset operations that mirror HF datasets without re‑implementing HuggingFace in Elixir.

**Required adapter API for Phase 1:**
- `load_dataset(repo_id, opts) -> DatasetDict | Dataset`
- `DatasetDict["train" | "test"] -> Dataset`
- `Dataset.shuffle(seed: int) -> Dataset`
- `Dataset.take(n) -> Dataset`
- `Dataset.skip(n) -> Dataset`
- `Dataset.select(range) -> Dataset`
- `Dataset.to_list() -> list(map)`

**Mapping to hfdatasetx (from README):**
- `HfDatasetsEx.load_dataset/2` already supports `repo_id`, `config`, `split`, `streaming`.
- `DatasetDict` exists.
- `Dataset` operations include `map`, `filter`, `shuffle`, `select`, `take`, `skip`.

**Plan:**
- Build a minimal adapter module in the cookbook port (Elixir) that exposes the above API and delegates to hfdatasetx.
- If any operation is missing, implement it in the adapter via `Enum`/`Stream`.

**Done when:**
- The adapter passes unit tests that mirror the Python dataset operations used in `sl_basic`.

---

### Step 3: Port the `SupervisedDataset` abstraction

**Why:** `train.Config` expects dataset builders that return objects with `get_batch/1` and `__len__`.

**Python behavior to match:**
- `get_batch(index)` uses dataset.select on index range
- Returns list of `Datum` objects
- `__len__` returns `len(dataset) // batch_size`
- `set_epoch(seed)` reshuffles deterministically

**Plan:**
- Define `SupervisedDataset` behaviour in Elixir:
  - `get_batch(index) :: [Datum]`
  - `len() :: non_neg_integer`
  - `set_epoch(seed) :: :ok`
- Implement:
  - `SupervisedDatasetFromHfDataset` (backed by hfdatasetx dataset)
  - `StreamingSupervisedDatasetFromHfDataset` (optional for Phase 1, but stub interface now)

**Done when:**
- Batch slicing, shuffling, and length match the Python reference semantics.

---

### Step 4: Port `ChatDatasetBuilder` + `NoRobotsBuilder`

**Why:** `sl_basic` builds a `ChatDatasetBuilderCommonConfig`, then `NoRobotsBuilder`.

**Python behavior:**
- Builds tokenizer + renderer from config
- Loads `no_robots` dataset
- Shuffles train set
- Converts `row["messages"]` into Datum via renderer

**Plan:**
- Define Elixir equivalents:
  - `ChatDatasetBuilderCommonConfig`
  - `ChatDatasetBuilder` behaviour + `NoRobotsBuilder`
- Use adapter from Step 2 to load dataset.
- Use renderer from Step 5 to convert conversations.

**Done when:**
- `NoRobotsBuilder.call()` returns `{train_dataset, test_dataset}` with deterministic batch order.

---

### Step 5: Renderers + TrainOnWhat + Tokenizer (minimal but correct)

**Why:** `TrainOnWhat` and `Renderer.build_supervised_example` are core to the slice.

**Python behavior:**
- `TrainOnWhat` selects which assistant tokens get loss weight
- Renderer outputs `(ModelInput, weights)`
- `datum_from_model_input_weights` converts to final `Datum` with shifted targets

**Plan:**
- Implement:
  - `TrainOnWhat` enum in Elixir with the same values
  - A `Renderer` behaviour with `build_supervised_example(messages, train_on_what)`
  - One concrete renderer for the Phase 1 model (Llama 3.1‑8B or chosen default)
- Tokenization:
  - Use existing Elixir tokenizer (e.g., `tiktoken_ex`) with a minimal compatibility layer
  - If no tokenizer support for the model, explicitly pin to a supported tokenizer and document the mismatch

**Done when:**
- `build_supervised_example` produces stable token+weight outputs for a small test conversation.

---

### Step 6: Port `datum_from_model_input_weights`

**Why:** All training uses this transformation.

**Python behavior:**
- Truncate to max_length (drop image chunks entirely if overflow)
- Right‑shift inputs, left‑shift targets
- Build `Datum` with `target_tokens` and `weights` as `TensorData`

**Plan:**
- Implement Elixir equivalent (no images needed in Phase 1 unless model uses them).
- Mirror Python edge cases: minimum length, image trimming, weight alignment.

**Done when:**
- Unit tests match Python expectations for truncation + shifting.

---

### Step 7: Port the `supervised/train` loop (Phase 1 minimal)

**Why:** `sl_basic` must run end‑to‑end.

**Plan:**
- Implement a minimal sequential training loop first (no pipeline), then add pipelining if needed.
- Required features:
  - Instantiate training client (Tinkex)
  - Iterate over batches
  - Compute learning rate schedule
  - Forward/backward + optim step
  - Save checkpoints every N steps
  - Log metrics

**Note:** Use mocks in tests; only real calls in integration demo.

**Done when:**
- `sl_basic` runs to completion in Elixir with deterministic logging output.

---

### Step 8: Build the Elixir `sl_basic` example + CLI

**Why:** This is the canonical Phase 1 slice.

**Plan:**
- Create `sl_basic.exs` that mirrors Python:
  - Build blueprint
  - Override defaults
  - `entrypoint` / `make_from_argv`
  - `check_log_dir` behavior
  - `train.main` call

**Done when:**
- Example runs end‑to‑end with no manual edits (just CLI args).

---

### Step 9: Tests (TDD, no sleeps)

**Plan:**
- Use Supertester for deterministic async‑safe tests
- Add tests for:
  - Dataset adapter semantics (shuffle/take/skip/select)
  - Renderer outputs for a known conversation
  - `datum_from_model_input_weights` invariants
  - `NoRobotsBuilder` integration (mock dataset)
  - `sl_basic` happy‑path (mocked Tinkex client)

**Done when:**
- Tests pass deterministically without sleeps or network.

---

## 4) Phase 1 Definition of Done (updated)

Phase 1 is done when all of the following are true:

1) `sl_basic` runs end‑to‑end in Elixir with the **NoRobots** dataset
2) Dataset ops (`shuffle`, `take`, `skip`, `select`) are deterministic and tested
3) Renderer + TrainOnWhat behavior matches the Python reference
4) No Crucible references exist in Phase 1 docs or code
5) All tests pass without sleeps or external network

---

## 5) Open Questions / Decisions (Need Owner)

- **Tokenizer choice:** Which Elixir tokenizer is the canonical one for Llama‑3 in Phase 1?
- **hfdatasetx API:** Confirm which dataset ops are fully implemented vs need adapters.
- **Tinkex client:** Is the Elixir training client ready for supervised loop, or do we stub in Phase 1?

---

## 6) Quick Checklist (Phase 1 v2)

- [ ] Replace Crucible references with hfdatasetx
- [ ] Implement dataset adapter + tests
- [ ] Port `ChatDatasetBuilder` + `NoRobotsBuilder`
- [ ] Implement renderer + TrainOnWhat
- [ ] Port datum conversion
- [ ] Implement minimal supervised train loop
- [ ] Add `sl_basic` example + CLI
- [ ] Write tests (no sleeps, no network)

