defmodule SnakeBridge.BytesTest do
  use ExUnit.Case, async: true

  alias SnakeBridge.Bytes

  describe "Bytes.new/1" do
    test "creates Bytes struct from string" do
      bytes = Bytes.new("hello")
      assert %Bytes{data: "hello"} = bytes
    end

    test "creates Bytes struct from binary" do
      bytes = Bytes.new(<<0, 1, 2, 255>>)
      assert %Bytes{data: <<0, 1, 2, 255>>} = bytes
    end

    test "creates Bytes struct from empty binary" do
      bytes = Bytes.new("")
      assert %Bytes{data: ""} = bytes
    end

    test "creates Bytes struct from UTF-8 string" do
      bytes = Bytes.new("日本語")
      assert %Bytes{data: "日本語"} = bytes
    end
  end

  describe "Bytes.data/1" do
    test "extracts data from Bytes struct" do
      bytes = Bytes.new("hello")
      assert Bytes.data(bytes) == "hello"
    end

    test "extracts binary data from Bytes struct" do
      bytes = Bytes.new(<<0, 1, 2, 255>>)
      assert Bytes.data(bytes) == <<0, 1, 2, 255>>
    end

    test "extracts empty data from Bytes struct" do
      bytes = Bytes.new("")
      assert Bytes.data(bytes) == ""
    end
  end

  describe "struct creation" do
    test "can create Bytes struct directly" do
      bytes = %Bytes{data: "test"}
      assert bytes.data == "test"
    end

    test "default data is nil" do
      bytes = %Bytes{}
      assert bytes.data == nil
    end
  end
end
