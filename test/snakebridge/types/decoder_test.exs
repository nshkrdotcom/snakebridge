defmodule SnakeBridge.Types.DecoderTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Types.Decoder

  @schema SnakeBridge.Types.schema_version()

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

  describe "decode/1 atoms" do
    setup do
      restore = SnakeBridge.Env.put_app_env_override(:snakebridge, :atom_allowlist, ["ok"])
      on_exit(restore)

      :ok
    end

    test "decodes allowlisted atom tags into atoms" do
      assert Decoder.decode(%{
               "__type__" => "atom",
               "__schema__" => @schema,
               "value" => "ok"
             }) == :ok
    end

    test "decodes non-allowlisted atom tags into strings" do
      assert Decoder.decode(%{
               "__type__" => "atom",
               "__schema__" => @schema,
               "value" => "not_allowed"
             }) == "not_allowed"
    end
  end

  describe "decode/1 special floats" do
    test "decodes infinity" do
      assert Decoder.decode(%{
               "__type__" => "special_float",
               "__schema__" => @schema,
               "value" => "infinity"
             }) == :infinity
    end

    test "decodes negative infinity" do
      assert Decoder.decode(%{
               "__type__" => "special_float",
               "__schema__" => @schema,
               "value" => "neg_infinity"
             }) == :neg_infinity
    end

    test "decodes NaN" do
      assert Decoder.decode(%{
               "__type__" => "special_float",
               "__schema__" => @schema,
               "value" => "nan"
             }) == :nan
    end
  end

  describe "decode/1 tuples" do
    test "decodes empty tuple" do
      assert Decoder.decode(%{
               "__type__" => "tuple",
               "__schema__" => @schema,
               "elements" => []
             }) == {}
    end

    test "decodes simple tuple" do
      assert Decoder.decode(%{
               "__type__" => "tuple",
               "__schema__" => @schema,
               "elements" => [1, 2, 3]
             }) == {1, 2, 3}
    end

    test "decodes tuple with mixed types" do
      assert Decoder.decode(%{
               "__type__" => "tuple",
               "__schema__" => @schema,
               "elements" => ["ok", "result"]
             }) == {"ok", "result"}
    end

    test "decodes nested tuples" do
      assert Decoder.decode(%{
               "__type__" => "tuple",
               "__schema__" => @schema,
               "elements" => [
                 %{"__type__" => "tuple", "__schema__" => @schema, "elements" => [1, 2]},
                 %{"__type__" => "tuple", "__schema__" => @schema, "elements" => [3, 4]}
               ]
             }) == {{1, 2}, {3, 4}}
    end

    test "decodes single element tuple" do
      assert Decoder.decode(%{
               "__type__" => "tuple",
               "__schema__" => @schema,
               "elements" => [42]
             }) == {42}
    end
  end

  describe "decode/1 sets" do
    test "decodes empty set" do
      assert Decoder.decode(%{
               "__type__" => "set",
               "__schema__" => @schema,
               "elements" => []
             }) == MapSet.new()
    end

    test "decodes set with elements" do
      result =
        Decoder.decode(%{
          "__type__" => "set",
          "__schema__" => @schema,
          "elements" => [1, 2, 3]
        })

      assert MapSet.equal?(result, MapSet.new([1, 2, 3]))
    end

    test "decodes set with string elements" do
      result =
        Decoder.decode(%{
          "__type__" => "set",
          "__schema__" => @schema,
          "elements" => ["a", "b", "c"]
        })

      assert MapSet.equal?(result, MapSet.new(["a", "b", "c"]))
    end

    test "decodes set with duplicate elements (should deduplicate)" do
      result =
        Decoder.decode(%{
          "__type__" => "set",
          "__schema__" => @schema,
          "elements" => [1, 2, 2, 3, 3]
        })

      assert MapSet.equal?(result, MapSet.new([1, 2, 3]))
    end

    test "decodes frozenset into MapSet" do
      result =
        Decoder.decode(%{
          "__type__" => "frozenset",
          "__schema__" => @schema,
          "elements" => [1, 2, 3]
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
               "__schema__" => @schema,
               "data" => encoded
             }) == binary
    end

    test "decodes empty bytes" do
      assert Decoder.decode(%{
               "__type__" => "bytes",
               "__schema__" => @schema,
               "data" => ""
             }) == <<>>
    end

    test "decodes bytes with various data" do
      binary = <<0, 1, 2, 255, 128, 64>>
      encoded = Base.encode64(binary)

      assert Decoder.decode(%{
               "__type__" => "bytes",
               "__schema__" => @schema,
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
          "__schema__" => @schema,
          "value" => "2023-12-25T10:30:00Z"
        })

      assert DateTime.compare(result, expected) == :eq
    end

    test "decodes DateTime with microseconds" do
      {:ok, expected, _} = DateTime.from_iso8601("2023-12-25T10:30:00.123456Z")

      result =
        Decoder.decode(%{
          "__type__" => "datetime",
          "__schema__" => @schema,
          "value" => "2023-12-25T10:30:00.123456Z"
        })

      assert DateTime.compare(result, expected) == :eq
    end

    test "decodes DateTime with timezone offset" do
      {:ok, expected, _} = DateTime.from_iso8601("2023-12-25T10:30:00+05:00")

      result =
        Decoder.decode(%{
          "__type__" => "datetime",
          "__schema__" => @schema,
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
               "__schema__" => @schema,
               "value" => "2023-12-25"
             }) == expected
    end

    test "decodes various dates" do
      assert Decoder.decode(%{
               "__type__" => "date",
               "__schema__" => @schema,
               "value" => "2000-01-01"
             }) == ~D[2000-01-01]

      assert Decoder.decode(%{
               "__type__" => "date",
               "__schema__" => @schema,
               "value" => "1999-12-31"
             }) == ~D[1999-12-31]
    end
  end

  describe "decode/1 Time" do
    test "decodes Time from ISO8601" do
      expected = ~T[10:30:00]

      assert Decoder.decode(%{
               "__type__" => "time",
               "__schema__" => @schema,
               "value" => "10:30:00"
             }) == expected
    end

    test "decodes Time with microseconds" do
      expected = ~T[10:30:00.123456]

      assert Decoder.decode(%{
               "__type__" => "time",
               "__schema__" => @schema,
               "value" => "10:30:00.123456"
             }) == expected
    end

    test "decodes various times" do
      assert Decoder.decode(%{
               "__type__" => "time",
               "__schema__" => @schema,
               "value" => "00:00:00"
             }) == ~T[00:00:00]

      assert Decoder.decode(%{
               "__type__" => "time",
               "__schema__" => @schema,
               "value" => "23:59:59"
             }) == ~T[23:59:59]
    end
  end

  describe "decode/1 complex numbers" do
    test "decodes complex number" do
      assert Decoder.decode(%{
               "__type__" => "complex",
               "__schema__" => @schema,
               "real" => 3.0,
               "imag" => 4.0
             }) == %{real: 3.0, imag: 4.0}
    end

    test "decodes complex number with integer parts" do
      assert Decoder.decode(%{
               "__type__" => "complex",
               "__schema__" => @schema,
               "real" => 5,
               "imag" => -2
             }) == %{real: 5, imag: -2}
    end

    test "decodes complex number with zero imaginary part" do
      assert Decoder.decode(%{
               "__type__" => "complex",
               "__schema__" => @schema,
               "real" => 7.5,
               "imag" => 0
             }) == %{real: 7.5, imag: 0}
    end
  end

  describe "decode/1 legacy wire formats" do
    test "decodes tuple using legacy value key" do
      assert Decoder.decode(%{
               "__type__" => "tuple",
               "value" => [1, 2, 3]
             }) == {1, 2, 3}
    end

    test "decodes set using legacy value key" do
      result =
        Decoder.decode(%{
          "__type__" => "set",
          "value" => [1, 2, 3]
        })

      assert MapSet.equal?(result, MapSet.new([1, 2, 3]))
    end

    test "decodes bytes using legacy value key" do
      binary = <<1, 2, 3>>
      encoded = Base.encode64(binary)

      assert Decoder.decode(%{
               "__type__" => "bytes",
               "value" => encoded
             }) == binary
    end

    test "decodes legacy special float tags" do
      assert Decoder.decode(%{"__type__" => "infinity"}) == :infinity
      assert Decoder.decode(%{"__type__" => "neg_infinity"}) == :neg_infinity
      assert Decoder.decode(%{"__type__" => "nan"}) == :nan
    end
  end

  describe "decode/1 nested structures" do
    test "decodes list with tuples" do
      assert Decoder.decode([
               %{"__type__" => "tuple", "__schema__" => @schema, "elements" => ["ok", 1]},
               %{"__type__" => "tuple", "__schema__" => @schema, "elements" => ["error", "msg"]}
             ]) == [{"ok", 1}, {"error", "msg"}]
    end

    test "decodes deeply nested structure" do
      data = %{
        "result" => %{
          "__type__" => "tuple",
          "__schema__" => @schema,
          "elements" => [
            "ok",
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

      decoded = Decoder.decode(data)

      assert decoded["result"] == {"ok", MapSet.new([1, 2])}
      assert decoded["metadata"]["timestamp"] == ~D[2023-12-25]
    end

    test "decodes list with sets" do
      list = [
        %{"__type__" => "set", "__schema__" => @schema, "elements" => [1, 2]},
        %{"__type__" => "set", "__schema__" => @schema, "elements" => [3, 4]}
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
          "__schema__" => @schema,
          "elements" => [
            "timestamp",
            %{
              "__type__" => "datetime",
              "__schema__" => @schema,
              "value" => "2023-12-25T10:30:00Z"
            }
          ]
        })

      assert elem(result, 0) == "timestamp"
      assert DateTime.compare(elem(result, 1), expected_dt) == :eq
    end

    test "decodes map containing multiple type-tagged values" do
      data = %{
        "tuple" => %{"__type__" => "tuple", "__schema__" => @schema, "elements" => [1, 2]},
        "set" => %{"__type__" => "set", "__schema__" => @schema, "elements" => [3, 4]},
        "date" => %{"__type__" => "date", "__schema__" => @schema, "value" => "2023-12-25"},
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
      assert Decoder.decode(%{
               "__type__" => "tuple",
               "__schema__" => @schema,
               "elements" => []
             }) == {}

      assert Decoder.decode(%{
               "__type__" => "set",
               "__schema__" => @schema,
               "elements" => []
             }) == MapSet.new()

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
        "__schema__" => @schema,
        "elements" => [
          %{
            "__type__" => "set",
            "__schema__" => @schema,
            "elements" => [
              %{"__type__" => "tuple", "__schema__" => @schema, "elements" => [1, 2]},
              %{"__type__" => "tuple", "__schema__" => @schema, "elements" => [3, 4]}
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
          "__schema__" => @schema,
          "elements" => ["ok", 200]
        },
        "data" => %{
          "items" => [
            %{"__type__" => "tuple", "__schema__" => @schema, "elements" => ["a", 1]},
            %{"__type__" => "tuple", "__schema__" => @schema, "elements" => ["b", 2]}
          ],
          "tags" => %{
            "__type__" => "set",
            "__schema__" => @schema,
            "elements" => ["tag1", "tag2"]
          }
        },
        "timestamp" => %{
          "__type__" => "datetime",
          "__schema__" => @schema,
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

  describe "decode/1 tagged dict" do
    test "decodes tagged dict with integer keys" do
      encoded = %{
        "__type__" => "dict",
        "__schema__" => @schema,
        "pairs" => [[1, "one"], [2, "two"]]
      }

      decoded = Decoder.decode(encoded)
      assert decoded == %{1 => "one", 2 => "two"}
    end

    test "decodes tagged dict without schema version" do
      encoded = %{
        "__type__" => "dict",
        "pairs" => [[1, "one"], [2, "two"]]
      }

      decoded = Decoder.decode(encoded)
      assert decoded == %{1 => "one", 2 => "two"}
    end

    test "decodes tagged dict with tuple keys" do
      encoded = %{
        "__type__" => "dict",
        "__schema__" => @schema,
        "pairs" => [
          [%{"__type__" => "tuple", "elements" => [0, 0]}, "origin"],
          [%{"__type__" => "tuple", "elements" => [1, 1]}, "point"]
        ]
      }

      decoded = Decoder.decode(encoded)
      assert decoded == %{{0, 0} => "origin", {1, 1} => "point"}
    end

    test "decodes tagged dict with mixed keys" do
      encoded = %{
        "__type__" => "dict",
        "pairs" => [
          ["string_key", 1],
          [42, 2],
          [1.5, 3]
        ]
      }

      decoded = Decoder.decode(encoded)
      assert decoded["string_key"] == 1
      assert decoded[42] == 2
      assert decoded[1.5] == 3
    end

    test "decodes empty tagged dict" do
      encoded = %{"__type__" => "dict", "pairs" => []}
      assert Decoder.decode(encoded) == %{}
    end

    test "decodes nested tagged dicts" do
      encoded = %{
        "__type__" => "dict",
        "pairs" => [
          [1, %{"__type__" => "dict", "pairs" => [[2, "nested"]]}]
        ]
      }

      decoded = Decoder.decode(encoded)
      assert decoded == %{1 => %{2 => "nested"}}
    end

    test "decodes tagged dict with float keys" do
      encoded = %{
        "__type__" => "dict",
        "pairs" => [[1.5, "one point five"], [2.5, "two point five"]]
      }

      decoded = Decoder.decode(encoded)
      assert decoded == %{1.5 => "one point five", 2.5 => "two point five"}
    end

    test "decodes tagged dict with complex nested values" do
      encoded = %{
        "__type__" => "dict",
        "pairs" => [
          [1, %{"__type__" => "tuple", "elements" => ["a", "b"]}],
          [2, %{"__type__" => "set", "elements" => [1, 2, 3]}]
        ]
      }

      decoded = Decoder.decode(encoded)
      assert decoded[1] == {"a", "b"}
      assert MapSet.equal?(decoded[2], MapSet.new([1, 2, 3]))
    end

    test "decodes tagged dict with atom keys when allowlisted" do
      SnakeBridge.Env.put_app_env_override(:snakebridge, :atom_allowlist, :all)

      encoded = %{
        "__type__" => "dict",
        "pairs" => [
          [%{"__type__" => "atom", "value" => "key1"}, "value1"],
          [%{"__type__" => "atom", "value" => "key2"}, "value2"]
        ]
      }

      decoded = Decoder.decode(encoded)
      assert decoded[:key1] == "value1"
      assert decoded[:key2] == "value2"
    end
  end
end
