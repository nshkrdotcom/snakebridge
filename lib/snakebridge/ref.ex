defmodule SnakeBridge.Ref do
  @moduledoc """
  Structured reference to a Python object managed by SnakeBridge.

  This struct defines the cross-language wire shape for Python object references.
  """

  @schema_version 1

  @typedoc """
  Wire format for Python object references.

  Required keys:
  - `"__type__"` => `"ref"`
  - `"__schema__"` => `#{@schema_version}`
  - `"id"` => reference id
  - `"session_id"` => runtime session id
  - `"python_module"` => Python module path
  - `"library"` => library root
  """
  @type t :: %{optional(String.t()) => term()}

  @spec schema_version() :: pos_integer()
  def schema_version, do: @schema_version
end
