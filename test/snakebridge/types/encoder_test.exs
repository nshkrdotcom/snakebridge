defmodule SnakeBridge.Types.EncoderTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Types.Encoder

  @schema SnakeBridge.Types.schema_version()

  describe "encode/1 primitives" do
    test "encodes nil" do
      assert Encoder.encode(nil) == nil
    end

    test "encodes booleans" do
      assert Encoder.encode(true) == true
      assert Encoder.encode(false) == false
    end

    test "encodes integers" do
      assert Encoder.encode(0) == 0
      assert Encoder.encode(42) == 42
      assert Encoder.encode(-123) == -123
    end

    test "encodes floats" do
      assert Encoder.encode(3.14) == 3.14
      assert Encoder.encode(-2.5) == -2.5
    end

    test "encodes strings" do
      assert Encoder.encode("hello") == "hello"
      assert Encoder.encode("") == ""
    end

    test "encodes lists" do
      assert Encoder.encode([]) == []
      assert Encoder.encode([1, 2, 3]) == [1, 2, 3]
    end

    test "encodes maps with string keys" do
      assert Encoder.encode(%{"a" => 1}) == %{"a" => 1}
      assert Encoder.encode(%{"x" => "y"}) == %{"x" => "y"}
    end
  end

  describe "encode/1 atoms" do
    test "encodes atoms as tagged values" do
      assert Encoder.encode(:ok) == %{
               "__type__" => "atom",
               "__schema__" => @schema,
               "value" => "ok"
             }

      assert Encoder.encode(:error) == %{
               "__type__" => "atom",
               "__schema__" => @schema,
               "value" => "error"
             }

      assert Encoder.encode(:some_atom) == %{
               "__type__" => "atom",
               "__schema__" => @schema,
               "value" => "some_atom"
             }
    end

    test "encodes nil atom specifically" do
      assert Encoder.encode(nil) == nil
    end

    test "encodes boolean atoms specifically" do
      assert Encoder.encode(true) == true
      assert Encoder.encode(false) == false
    end
  end

  describe "encode/1 special floats" do
    test "encodes infinity" do
      assert Encoder.encode(:infinity) == %{
               "__type__" => "special_float",
               "__schema__" => @schema,
               "value" => "infinity"
             }
    end

    test "encodes negative infinity" do
      assert Encoder.encode(:neg_infinity) == %{
               "__type__" => "special_float",
               "__schema__" => @schema,
               "value" => "neg_infinity"
             }
    end

    test "encodes NaN" do
      assert Encoder.encode(:nan) == %{
               "__type__" => "special_float",
               "__schema__" => @schema,
               "value" => "nan"
             }
    end
  end

  describe "encode/1 tuples" do
    test "encodes empty tuple" do
      assert Encoder.encode({}) == %{
               "__type__" => "tuple",
               "__schema__" => @schema,
               "elements" => []
             }
    end

    test "encodes simple tuple" do
      assert Encoder.encode({1, 2, 3}) == %{
               "__type__" => "tuple",
               "__schema__" => @schema,
               "elements" => [1, 2, 3]
             }
    end

    test "encodes tuple with mixed types" do
      assert Encoder.encode({:ok, "result"}) == %{
               "__type__" => "tuple",
               "__schema__" => @schema,
               "elements" => [
                 %{"__type__" => "atom", "__schema__" => @schema, "value" => "ok"},
                 "result"
               ]
             }
    end

    test "encodes nested tuples" do
      assert Encoder.encode({{1, 2}, {3, 4}}) == %{
               "__type__" => "tuple",
               "__schema__" => @schema,
               "elements" => [
                 %{"__type__" => "tuple", "__schema__" => @schema, "elements" => [1, 2]},
                 %{"__type__" => "tuple", "__schema__" => @schema, "elements" => [3, 4]}
               ]
             }
    end
  end

  describe "encode/1 MapSet" do
    test "encodes empty MapSet" do
      assert Encoder.encode(MapSet.new()) == %{
               "__type__" => "set",
               "__schema__" => @schema,
               "elements" => []
             }
    end

    test "encodes MapSet with elements" do
      result = Encoder.encode(MapSet.new([1, 2, 3]))
      assert result["__type__"] == "set"
      assert result["__schema__"] == @schema
      assert Enum.sort(result["elements"]) == [1, 2, 3]
    end

    test "encodes MapSet with atoms" do
      result = Encoder.encode(MapSet.new([:a, :b, :c]))
      assert result["__type__"] == "set"
      assert result["__schema__"] == @schema

      values =
        result["elements"]
        |> Enum.map(fn element ->
          %{"__type__" => "atom", "value" => value} = element
          value
        end)
        |> Enum.sort()

      assert values == ["a", "b", "c"]
    end
  end

  describe "encode/1 binaries" do
    test "encodes UTF-8 string as string" do
      assert Encoder.encode("hello") == "hello"
    end

    test "encodes non-UTF-8 binary as base64" do
      binary = <<255, 254, 253>>

      assert Encoder.encode(binary) == %{
               "__type__" => "bytes",
               "__schema__" => @schema,
               "data" => Base.encode64(binary)
             }
    end

    test "encodes empty non-UTF-8 binary" do
      binary = <<>>
      assert Encoder.encode(binary) == ""
    end
  end

  describe "encode/1 DateTime" do
    test "encodes DateTime as ISO8601" do
      {:ok, dt, _} = DateTime.from_iso8601("2023-12-25T10:30:00Z")

      assert Encoder.encode(dt) == %{
               "__type__" => "datetime",
               "__schema__" => @schema,
               "value" => "2023-12-25T10:30:00Z"
             }
    end

    test "encodes DateTime with microseconds" do
      {:ok, dt, _} = DateTime.from_iso8601("2023-12-25T10:30:00.123456Z")

      assert Encoder.encode(dt) == %{
               "__type__" => "datetime",
               "__schema__" => @schema,
               "value" => "2023-12-25T10:30:00.123456Z"
             }
    end
  end

  describe "encode/1 Date" do
    test "encodes Date as ISO8601" do
      date = ~D[2023-12-25]

      assert Encoder.encode(date) == %{
               "__type__" => "date",
               "__schema__" => @schema,
               "value" => "2023-12-25"
             }
    end
  end

  describe "encode/1 Time" do
    test "encodes Time as ISO8601" do
      time = ~T[10:30:00]

      assert Encoder.encode(time) == %{
               "__type__" => "time",
               "__schema__" => @schema,
               "value" => "10:30:00"
             }
    end

    test "encodes Time with microseconds" do
      time = ~T[10:30:00.123456]

      assert Encoder.encode(time) == %{
               "__type__" => "time",
               "__schema__" => @schema,
               "value" => "10:30:00.123456"
             }
    end
  end

  describe "encode/1 nested structures" do
    test "encodes list with tuples" do
      assert Encoder.encode([{:ok, 1}, {:error, "msg"}]) == [
               %{
                 "__type__" => "tuple",
                 "__schema__" => @schema,
                 "elements" => [
                   %{"__type__" => "atom", "__schema__" => @schema, "value" => "ok"},
                   1
                 ]
               },
               %{
                 "__type__" => "tuple",
                 "__schema__" => @schema,
                 "elements" => [
                   %{"__type__" => "atom", "__schema__" => @schema, "value" => "error"},
                   "msg"
                 ]
               }
             ]
    end

    test "encodes map with atom keys" do
      assert Encoder.encode(%{status: :ok, value: 42}) == %{
               "status" => %{"__type__" => "atom", "__schema__" => @schema, "value" => "ok"},
               "value" => 42
             }
    end

    test "encodes deeply nested structure" do
      data = %{
        result: {:ok, MapSet.new([1, 2])},
        metadata: %{timestamp: ~D[2023-12-25]}
      }

      encoded = Encoder.encode(data)

      assert encoded == %{
               "result" => %{
                 "__type__" => "tuple",
                 "__schema__" => @schema,
                 "elements" => [
                   %{"__type__" => "atom", "__schema__" => @schema, "value" => "ok"},
                   %{"__type__" => "set", "__schema__" => @schema, "elements" => [1, 2]}
                 ]
               },
               "metadata" => %{
                 "timestamp" => %{
                   "__type__" => "date",
                   "__schema__" => @schema,
                   "value" => "2023-12-25"
                 }
               }
             }
    end

    test "encodes list with MapSets" do
      list = [MapSet.new([1, 2]), MapSet.new([3, 4])]
      encoded = Encoder.encode(list)

      assert length(encoded) == 2
      assert Enum.all?(encoded, fn item -> item["__type__"] == "set" end)
      assert Enum.all?(encoded, fn item -> item["__schema__"] == @schema end)
    end

    test "encodes tuple containing DateTime" do
      {:ok, dt, _} = DateTime.from_iso8601("2023-12-25T10:30:00Z")
      tuple = {:timestamp, dt}

      assert Encoder.encode(tuple) == %{
               "__type__" => "tuple",
               "__schema__" => @schema,
               "elements" => [
                 %{"__type__" => "atom", "__schema__" => @schema, "value" => "timestamp"},
                 %{
                   "__type__" => "datetime",
                   "__schema__" => @schema,
                   "value" => "2023-12-25T10:30:00Z"
                 }
               ]
             }
    end
  end

  describe "encode/1 edge cases" do
    test "encodes map with mixed key types" do
      # Maps with atom keys get converted to string keys
      result = Encoder.encode(%{"b" => 2, a: 1})
      assert result == %{"a" => 1, "b" => 2}
    end

    test "encodes empty structures" do
      assert Encoder.encode({}) == %{
               "__type__" => "tuple",
               "__schema__" => @schema,
               "elements" => []
             }

      assert Encoder.encode([]) == []
      assert Encoder.encode(%{}) == %{}
    end

    test "encodes list with nil values" do
      assert Encoder.encode([1, nil, 3]) == [1, nil, 3]
    end

    test "encodes map with nil values" do
      assert Encoder.encode(%{"key" => nil}) == %{"key" => nil}
    end
  end
end
