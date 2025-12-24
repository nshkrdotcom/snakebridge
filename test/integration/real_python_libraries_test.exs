defmodule SnakeBridge.Integration.RealPythonLibrariesTest do
  @moduledoc """
  Real Python integration tests for curated library manifests.

  Run with: mix test --only real_python
  """

  use ExUnit.Case, async: false

  alias SnakeBridge.Manifest.Loader
  alias SnakeBridge.TestHelpers

  @moduletag :integration
  @moduletag :real_python
  @moduletag :slow

  setup_all do
    adapter_spec = "snakebridge_adapter.adapter.SnakeBridgeAdapter"

    {python_exe, _pythonpath, pool_config} =
      SnakeBridge.SnakepitTestHelper.prepare_python_env!(adapter_spec)

    original_adapter = Application.get_env(:snakebridge, :snakepit_adapter)
    Application.put_env(:snakebridge, :snakepit_adapter, SnakeBridge.SnakepitAdapter)

    restore_env =
      SnakeBridge.SnakepitTestHelper.start_snakepit!(
        pool_config: pool_config,
        python_executable: python_exe
      )

    on_exit(fn ->
      restore_env.()
      Application.put_env(:snakebridge, :snakepit_adapter, original_adapter)
    end)

    TestHelpers.purge_modules([SnakeBridge.SymPy, SnakeBridge.PyLatexEnc, SnakeBridge.MathVerify])

    {:ok, _modules} = Loader.load([:sympy, :pylatexenc, :math_verify], [])

    :ok
  end

  test "sympy manifest supports solve and simplify" do
    sympy_mod = Module.concat([SnakeBridge, SymPy])

    {:ok, simplified} =
      sympy_mod.simplify(%{expr: "sin(x)**2 + cos(x)**2"})

    assert simplified == "1" or String.contains?(simplified, "1")

    {:ok, solutions} =
      sympy_mod.solve(%{expr: "x**2 - 1", symbol: "x"})

    assert is_list(solutions)
    assert Enum.any?(solutions, &is_binary/1)
  end

  test "sympy manifest supports substitution and symbols" do
    sympy_mod = Module.concat([SnakeBridge, SymPy])

    {:ok, subs_result} =
      sympy_mod.subs(%{expr: "x + 1", mapping: %{"x" => 2}})

    assert is_binary(subs_result)
    assert String.contains?(subs_result, "3")

    {:ok, symbols} =
      sympy_mod.free_symbols(%{expr: "x*y + 1"})

    assert is_list(symbols)
    assert Enum.any?(symbols, &(&1 == "x"))
  end

  test "pylatexenc manifest supports latex to text and parse" do
    pylatexenc_mod = Module.concat([SnakeBridge, PyLatexEnc])

    {:ok, text} =
      pylatexenc_mod.latex_to_text(%{latex: "\\alpha + \\beta"})

    assert is_binary(text)

    {:ok, ast} = pylatexenc_mod.parse(%{latex: "\\frac{1}{2}"})

    assert is_list(ast)
    assert Enum.any?(ast, &is_map/1)
  end

  test "pylatexenc manifest supports unicode to latex" do
    pylatexenc_mod = Module.concat([SnakeBridge, PyLatexEnc])

    {:ok, latex} =
      pylatexenc_mod.unicode_to_latex(%{text: "α + β"})

    assert is_binary(latex)
    assert String.contains?(latex, "\\alpha")
  end

  test "math-verify manifest supports verify" do
    math_verify_mod = Module.concat([SnakeBridge, MathVerify])

    {:ok, result} =
      math_verify_mod.verify(%{gold: "x^2", answer: "x*x"})

    assert is_boolean(result) or is_map(result) or is_binary(result)
  end

  test "math-verify manifest supports parse and grade" do
    math_verify_mod = Module.concat([SnakeBridge, MathVerify])

    {:ok, parsed} =
      math_verify_mod.parse(%{text: "The answer is $x^2$"})

    assert parsed != nil

    {:ok, graded} =
      math_verify_mod.grade(%{gold: "x^2", answer: "x*x"})

    assert is_boolean(graded) or is_map(graded) or is_binary(graded)
  end
end
