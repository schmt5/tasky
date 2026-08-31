defmodule Tasky.Correction.AnswerVariantsTest do
  use ExUnit.Case, async: true

  alias Tasky.Correction.AnswerVariants

  doctest Tasky.Correction.AnswerVariants, import: false

  describe "split/1" do
    test "einzelne Antwort bleibt eine Antwort" do
      assert AnswerVariants.split("pdf") == ["pdf"]
    end

    test "trennt am Semikolon" do
      assert AnswerVariants.split("pdf;.pdf") == ["pdf", ".pdf"]
    end

    test "ignoriert Leerzeichen rund um die Alternativen" do
      assert AnswerVariants.split("  rasch ; flink ;  zügig ") == ["rasch", "flink", "zügig"]
    end

    test "wirft leere Abschnitte weg" do
      assert AnswerVariants.split("pdf;;.pdf;") == ["pdf", ".pdf"]
    end

    test "leerer Text und nil ergeben keine Alternative" do
      assert AnswerVariants.split("") == []
      assert AnswerVariants.split("   ") == []
      assert AnswerVariants.split(nil) == []
    end
  end

  describe "humanize/1" do
    test "eine Alternative steht für sich" do
      assert AnswerVariants.humanize("pdf") == "pdf"
    end

    test "zwei Alternativen werden mit Komma verbunden" do
      assert AnswerVariants.humanize("pdf;.pdf") == "pdf, .pdf"
    end

    test "mehr als zwei: alle mit Komma" do
      assert AnswerVariants.humanize("rasch; flink; zügig; geschwind") ==
               "rasch, flink, zügig, geschwind"
    end

    test "ohne Alternativen bleibt nichts übrig" do
      assert AnswerVariants.humanize(nil) == ""
    end
  end

  describe "humanize_answer/2" do
    test "answerBlock: die Liste steht wieder in einem Paragraphen" do
      nodes = [paragraph("pdf;.pdf")]

      assert AnswerVariants.humanize_answer(%{"type" => "answerBlock"}, nodes) == [
               paragraph("pdf, .pdf")
             ]
    end

    test "lueckentext: die Liste bleibt inline" do
      nodes = [text("Bern;Berne")]

      assert AnswerVariants.humanize_answer(%{"type" => "lueckentext"}, nodes) == [
               text("Bern, Berne")
             ]
    end

    test "ohne Semikolon bleiben die Knoten unangetastet — Formatierung überlebt" do
      nodes = [%{"type" => "text", "text" => "Bern", "marks" => [%{"type" => "bold"}]}]

      assert AnswerVariants.humanize_answer(%{"type" => "lueckentext"}, nodes) == nodes
    end

    test "eine Checkbox hat keine Alternativen" do
      assert AnswerVariants.humanize_answer(%{"type" => "taskItem"}, true) == true
    end

    test "ein leeres Antwortfeld bleibt leer" do
      assert AnswerVariants.humanize_answer(%{"type" => "answerBlock"}, []) == []
    end
  end

  describe "humanize_doc/1" do
    test "schreibt Antwortknoten in der Tiefe um und lässt den Rest stehen" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "heading", "content" => [text("Frage 1")]},
          %{"type" => "answerBlock", "content" => [paragraph("pdf; .pdf")]},
          %{
            "type" => "paragraph",
            "content" => [
              text("Die Hauptstadt ist "),
              %{"type" => "lueckentext", "content" => [text("Bern;Berne")]}
            ]
          }
        ]
      }

      assert %{"content" => [heading, answer, sentence]} = AnswerVariants.humanize_doc(doc)

      assert heading == %{"type" => "heading", "content" => [text("Frage 1")]}
      assert answer == %{"type" => "answerBlock", "content" => [paragraph("pdf, .pdf")]}

      assert sentence == %{
               "type" => "paragraph",
               "content" => [
                 text("Die Hauptstadt ist "),
                 %{"type" => "lueckentext", "content" => [text("Bern, Berne")]}
               ]
             }
    end

    test "behält die Attribute des Antwortknotens" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "answerBlock",
            "attrs" => %{"answerId" => "a"},
            "content" => [paragraph("pdf;.pdf")]
          }
        ]
      }

      assert %{"content" => [answer]} = AnswerVariants.humanize_doc(doc)
      assert answer["attrs"] == %{"answerId" => "a"}
    end

    test "kommt mit einem leeren Dokument klar" do
      assert AnswerVariants.humanize_doc(%{}) == %{}
      assert AnswerVariants.humanize_doc(nil) == nil
    end
  end

  defp text(value), do: %{"type" => "text", "text" => value}
  defp paragraph(value), do: %{"type" => "paragraph", "content" => [text(value)]}
end
