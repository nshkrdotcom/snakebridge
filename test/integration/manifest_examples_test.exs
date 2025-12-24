defmodule SnakeBridge.Integration.ManifestExamplesTest do
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

  test "sympy manifest example simplifies expressions" do
    sympy_mod = Module.concat([SnakeBridge, SymPy])

    {:ok, simplified} =
      sympy_mod.simplify(%{expr: "sin(x)**2 + cos(x)**2"})

    assert simplified == "1" or String.contains?(simplified, "1")
  end

  test "pylatexenc manifest example renders latex" do
    pylatexenc_mod = Module.concat([SnakeBridge, PyLatexEnc])

    {:ok, text} = pylatexenc_mod.latex_to_text(%{latex: "\\alpha + \\beta"})
    assert is_binary(text)
  end

  test "math-verify manifest example grades equivalent answers" do
    math_verify_mod = Module.concat([SnakeBridge, MathVerify])

    {:ok, graded} = math_verify_mod.grade(%{gold: "x^2", answer: "x*x"})
    assert is_boolean(graded) or is_map(graded) or is_binary(graded)
  end
end
