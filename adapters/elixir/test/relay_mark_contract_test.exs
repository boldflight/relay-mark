defmodule RelayMark.ContractTest do
  use ExUnit.Case, async: true

  test "canonical descriptor shares one compatibility number and rejects old AST counter" do
    assert RelayMark.Contract.descriptor() == %{
             "contract_version" => 1,
             "schema" => "relaymark-prosemirror",
             "source_contract" => "relaymark_ast"
           }

    ast = %{"type" => "relaymark.document", "blocks" => []}
    assert :ok = RelayMark.validate_document(ast)
    assert {:error, _} = RelayMark.validate_document(Map.put(ast, "version", 1))
  end
end
