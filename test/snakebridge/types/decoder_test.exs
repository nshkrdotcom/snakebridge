defmodule SnakeBridge.Types.DecoderTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Types.Decoder

  describe "decode/1 primitives" do
    test "decodes nil" do
      assert Decoder.decode(nil) == nil
    end

    test "decodes booleans" do
      assert Decoder.decode(true) == true
      assert Decoder.decode(false) == false
    end

    test "decodes integers" do
      assert Decoder.decode(0) == 0
      assert Decoder.decode(42) == 42
      assert Decoder.decode(-123) == -123
    end

    test "decodes floats" do
      assert Decoder.decode(3.14) == 3.14
      assert Decoder.decode(-2.5) == -2.5
    end

    test "decodes strings" do
      assert Decoder.decode("hello") == "hello"
      assert Decoder.decode("") == ""
    end

    test "decodes lists" do
      assert Decoder.decode([]) == []
      assert Decoder.decode([1, 2, 3]) == [1, 2, 3]
    end

    test "decodes maps without type tags" do
      assert Decoder.decode(%{"a" => 1}) == %{"a" => 1}
      assert Decoder.decode(%{"x" => "y"}) == %{"x" => "y"}
    end
  end

  describe "decode/1 special floats" do
    test "decodes infinity" do
      assert Decoder.decode(%{
               "__type__" => "special_float",
               "value" => "infinity"
             }) == :infinity
    end

    test "decodes negative infinity" do
      assert Decoder.decode(%{
               "__type__" => "special_float",
               "value" => "neg_infinity"
             }) == :neg_infinity
    end

    test "decodes NaN" do
      assert Decoder.decode(%{
               "__type__" => "special_float",
               "value" => "nan"
             }) == :nan
    end
  end

  describe "decode/1 tuples" do
    test "decodes empty tuple" do
      assert Decoder.decode(%{
               "__type__" => "tuple",
               "elements" => []
             }) == {}
    end

    test "decodes simple tuple" do
      assert Decoder.decode(%{
               "__type__" => "tuple",
               "elements" => [1, 2, 3]
             }) == {1, 2, 3}
    end

    test "decodes tuple with mixed types" do
      assert Decoder.decode(%{
               "__type__" => "tuple",
               "elements" => ["ok", "result"]
             }) == {"ok", "result"}
    end

    test "decodes nested tuples" do
      assert Decoder.decode(%{
               "__type__" => "tuple",
               "elements" => [
                 %{"__type__" => "tuple", "elements" => [1, 2]},
                 %{"__type__" => "tuple", "elements" => [3, 4]}
               ]
             }) == {{1, 2}, {3, 4}}
    end

    test "decodes single element tuple" do
      assert Decoder.decode(%{
               "__type__" => "tuple",
               "elements" => [42]
             }) == {42}
    end
  end

  describe "decode/1 sets" do
    test "decodes empty set" do
      assert Decoder.decode(%{
               "__type__" => "set",
               "elements" => []
             }) == MapSet.new()
    end

    test "decodes set with elements" do
      result =
        Decoder.decode(%{
          "__type__" => "set",
          "elements" => [1, 2, 3]
        })

      assert MapSet.equal?(result, MapSet.new([1, 2, 3]))
    end

    test "decodes set with string elements" do
      result =
        Decoder.decode(%{
          "__type__" => "set",
          "elements" => ["a", "b", "c"]
        })

      assert MapSet.equal?(result, MapSet.new(["a", "b", "c"]))
    end

    test "decodes set with duplicate elements (should deduplicate)" do
      result =
        Decoder.decode(%{
          "__type__" => "set",
          "elements" => [1, 2, 2, 3, 3]
        })

      assert MapSet.equal?(result, MapSet.new([1, 2, 3]))
    end
  end

  describe "decode/1 bytes" do
    test "decodes base64 encoded bytes" do
      binary = <<255, 254, 253>>
      encoded = Base.encode64(binary)

      assert Decoder.decode(%{
               "__type__" => "bytes",
               "data" => encoded
             }) == binary
    end

    test "decodes empty bytes" do
      assert Decoder.decode(%{
               "__type__" => "bytes",
               "data" => ""
             }) == <<>>
    end

    test "decodes bytes with various data" do
      binary = <<0, 1, 2, 255, 128, 64>>
      encoded = Base.encode64(binary)

      assert Decoder.decode(%{
               "__type__" => "bytes",
               "data" => encoded
             }) == binary
    end
  end

  describe "decode/1 DateTime" do
    test "decodes DateTime from ISO8601" do
      {:ok, expected, _} = DateTime.from_iso8601("2023-12-25T10:30:00Z")

      result =
        Decoder.decode(%{
          "__type__" => "datetime",
          "value" => "2023-12-25T10:30:00Z"
        })

      assert DateTime.compare(result, expected) == :eq
    end

    test "decodes DateTime with microseconds" do
      {:ok, expected, _} = DateTime.from_iso8601("2023-12-25T10:30:00.123456Z")

      result =
        Decoder.decode(%{
          "__type__" => "datetime",
          "value" => "2023-12-25T10:30:00.123456Z"
        })

      assert DateTime.compare(result, expected) == :eq
    end

    test "decodes DateTime with timezone offset" do
      {:ok, expected, _} = DateTime.from_iso8601("2023-12-25T10:30:00+05:00")

      result =
        Decoder.decode(%{
          "__type__" => "datetime",
          "value" => "2023-12-25T10:30:00+05:00"
        })

      assert DateTime.compare(result, expected) == :eq
    end
  end

  describe "decode/1 Date" do
    test "decodes Date from ISO8601" do
      expected = ~D[2023-12-25]

      assert Decoder.decode(%{
               "__type__" => "date",
               "value" => "2023-12-25"
             }) == expected
    end

    test "decodes various dates" do
      assert Decoder.decode(%{"__type__" => "date", "value" => "2000-01-01"}) == ~D[2000-01-01]
      assert Decoder.decode(%{"__type__" => "date", "value" => "1999-12-31"}) == ~D[1999-12-31]
    end
  end

  describe "decode/1 Time" do
    test "decodes Time from ISO8601" do
      expected = ~T[10:30:00]

      assert Decoder.decode(%{
               "__type__" => "time",
               "value" => "10:30:00"
             }) == expected
    end

    test "decodes Time with microseconds" do
      expected = ~T[10:30:00.123456]

      assert Decoder.decode(%{
               "__type__" => "time",
               "value" => "10:30:00.123456"
             }) == expected
    end

    test "decodes various times" do
      assert Decoder.decode(%{"__type__" => "time", "value" => "00:00:00"}) == ~T[00:00:00]
      assert Decoder.decode(%{"__type__" => "time", "value" => "23:59:59"}) == ~T[23:59:59]
    end
  end

  describe "decode/1 complex numbers" do
    test "decodes complex number" do
      assert Decoder.decode(%{
               "__type__" => "complex",
               "real" => 3.0,
               "imag" => 4.0
             }) == %{real: 3.0, imag: 4.0}
    end

    test "decodes complex number with integer parts" do
      assert Decoder.decode(%{
               "__type__" => "complex",
               "real" => 5,
               "imag" => -2
             }) == %{real: 5, imag: -2}
    end

    test "decodes complex number with zero imaginary part" do
      assert Decoder.decode(%{
               "__type__" => "complex",
               "real" => 7.5,
               "imag" => 0
             }) == %{real: 7.5, imag: 0}
    end
  end

  describe "decode/1 nested structures" do
    test "decodes list with tuples" do
      assert Decoder.decode([
               %{"__type__" => "tuple", "elements" => ["ok", 1]},
               %{"__type__" => "tuple", "elements" => ["error", "msg"]}
             ]) == [{"ok", 1}, {"error", "msg"}]
    end

    test "decodes deeply nested structure" do
      data = %{
        "result" => %{
          "__type__" => "tuple",
          "elements" => [
            "ok",
            %{"__type__" => "set", "elements" => [1, 2]}
          ]
        },
        "metadata" => %{
          "timestamp" => %{
            "__type__" => "date",
            "value" => "2023-12-25"
          }
        }
      }

      decoded = Decoder.decode(data)

      assert decoded["result"] == {"ok", MapSet.new([1, 2])}
      assert decoded["metadata"]["timestamp"] == ~D[2023-12-25]
    end

    test "decodes list with sets" do
      list = [
        %{"__type__" => "set", "elements" => [1, 2]},
        %{"__type__" => "set", "elements" => [3, 4]}
      ]

      decoded = Decoder.decode(list)

      assert length(decoded) == 2
      assert MapSet.equal?(Enum.at(decoded, 0), MapSet.new([1, 2]))
      assert MapSet.equal?(Enum.at(decoded, 1), MapSet.new([3, 4]))
    end

    test "decodes tuple containing DateTime" do
      {:ok, expected_dt, _} = DateTime.from_iso8601("2023-12-25T10:30:00Z")

      result =
        Decoder.decode(%{
          "__type__" => "tuple",
          "elements" => [
            "timestamp",
            %{
              "__type__" => "datetime",
              "value" => "2023-12-25T10:30:00Z"
            }
          ]
        })

      assert elem(result, 0) == "timestamp"
      assert DateTime.compare(elem(result, 1), expected_dt) == :eq
    end

    test "decodes map containing multiple type-tagged values" do
      data = %{
        "tuple" => %{"__type__" => "tuple", "elements" => [1, 2]},
        "set" => %{"__type__" => "set", "elements" => [3, 4]},
        "date" => %{"__type__" => "date", "value" => "2023-12-25"},
        "regular" => "value"
      }

      decoded = Decoder.decode(data)

      assert decoded["tuple"] == {1, 2}
      assert MapSet.equal?(decoded["set"], MapSet.new([3, 4]))
      assert decoded["date"] == ~D[2023-12-25]
      assert decoded["regular"] == "value"
    end
  end

  describe "decode/1 edge cases" do
    test "decodes empty structures" do
      assert Decoder.decode(%{"__type__" => "tuple", "elements" => []}) == {}
      assert Decoder.decode(%{"__type__" => "set", "elements" => []}) == MapSet.new()
      assert Decoder.decode([]) == []
      assert Decoder.decode(%{}) == %{}
    end

    test "decodes list with nil values" do
      assert Decoder.decode([1, nil, 3]) == [1, nil, 3]
    end

    test "decodes map with nil values" do
      assert Decoder.decode(%{"key" => nil}) == %{"key" => nil}
    end

    test "decodes map with __type__ as regular field when not recognized" do
      # If __type__ is not a recognized type, treat as regular map
      result = Decoder.decode(%{"__type__" => "unknown", "data" => 123})
      assert result == %{"__type__" => "unknown", "data" => 123}
    end

    test "preserves nested type tags in decoded values" do
      # Tuple containing a set containing tuples
      data = %{
        "__type__" => "tuple",
        "elements" => [
          %{
            "__type__" => "set",
            "elements" => [
              %{"__type__" => "tuple", "elements" => [1, 2]},
              %{"__type__" => "tuple", "elements" => [3, 4]}
            ]
          }
        ]
      }

      result = Decoder.decode(data)
      assert is_tuple(result)
      assert tuple_size(result) == 1
      set = elem(result, 0)
      assert MapSet.size(set) == 2
      assert MapSet.member?(set, {1, 2})
      assert MapSet.member?(set, {3, 4})
    end
  end

  describe "decode/1 round-trip compatibility" do
    test "handles nested type-tagged structures" do
      # Complex nested structure
      data = %{
        "status" => %{
          "__type__" => "tuple",
          "elements" => ["ok", 200]
        },
        "data" => %{
          "items" => [
            %{"__type__" => "tuple", "elements" => ["a", 1]},
            %{"__type__" => "tuple", "elements" => ["b", 2]}
          ],
          "tags" => %{
            "__type__" => "set",
            "elements" => ["tag1", "tag2"]
          }
        },
        "timestamp" => %{
          "__type__" => "datetime",
          "value" => "2023-12-25T10:30:00Z"
        }
      }

      decoded = Decoder.decode(data)
      {:ok, expected_dt, _} = DateTime.from_iso8601("2023-12-25T10:30:00Z")

      assert decoded["status"] == {"ok", 200}
      assert decoded["data"]["items"] == [{"a", 1}, {"b", 2}]
      assert MapSet.equal?(decoded["data"]["tags"], MapSet.new(["tag1", "tag2"]))
      assert DateTime.compare(decoded["timestamp"], expected_dt) == :eq
    end
  end
end
