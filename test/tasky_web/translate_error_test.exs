defmodule TaskyWeb.TranslateErrorTest do
  use ExUnit.Case, async: true

  import TaskyWeb.CoreComponents, only: [translate_error: 1]

  test "translates Ecto's default messages into German" do
    assert translate_error({"can't be blank", [validation: :required]}) ==
             "darf nicht leer sein"

    assert translate_error({"has already been taken", []}) == "ist bereits vergeben"

    assert translate_error({"must be greater than or equal to %{number}", [number: 0]}) ==
             "muss mindestens 0 sein"
  end

  test "picks the plural form from the count" do
    msg = "should be at most %{count} character(s)"

    assert translate_error({msg, [count: 1]}) == "darf höchstens 1 Zeichen lang sein"
    assert translate_error({msg, [count: 100]}) == "darf höchstens 100 Zeichen lang sein"

    msg = "should have at least %{count} item(s)"
    assert translate_error({msg, [count: 1]}) == "muss mindestens 1 Eintrag haben"
    assert translate_error({msg, [count: 2]}) == "muss mindestens 2 Einträge haben"
  end

  test "keeps messages that are already German" do
    assert translate_error({"stimmt nicht überein", []}) == "stimmt nicht überein"
  end
end
