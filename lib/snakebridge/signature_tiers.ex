defmodule SnakeBridge.SignatureTiers do
  @moduledoc false

  @tiers %{
    "runtime" => 1,
    "text_signature" => 2,
    "runtime_hints" => 3,
    "stub" => 4,
    "stubgen" => 5,
    "variadic" => 6
  }

  @spec normalize(atom() | String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil
  def normalize(source) when is_atom(source), do: Atom.to_string(source)
  def normalize(source) when is_binary(source), do: source

  @spec rank(atom() | String.t() | nil) :: non_neg_integer()
  def rank(source) do
    source
    |> normalize()
    |> case do
      "attribute" -> Map.fetch!(@tiers, "runtime")
      value -> Map.get(@tiers, value, 999)
    end
  end

  @spec meets_min?(atom() | String.t() | nil, atom() | String.t() | nil) :: boolean()
  def meets_min?(source, min_tier) do
    rank(source) <= rank(min_tier)
  end

  @spec known_tiers() :: [String.t()]
  def known_tiers, do: Map.keys(@tiers)
end
