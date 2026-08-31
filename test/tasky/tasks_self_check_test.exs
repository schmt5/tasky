defmodule Tasky.TasksSelfCheckTest do
  @moduledoc """
  Automatische Selbstkontrolle einer Lerneinheit.

  Die Auswertung ist das, was Lernende unmittelbar nach der Abgabe zu sehen
  bekommen — ein falsches ❌ an einer richtigen Antwort ist hier der teuerste
  Fehler. Darum steht die Zählung von `total` im Mittelpunkt: geprüft wird nur,
  was auch prüfbar ist.
  """
  use ExUnit.Case, async: true

  alias Tasky.Tasks.SelfCheck
  alias Tasky.Tasks.Task
  alias Tasky.Tasks.TaskSubmission

  defp answer_block(id, text) do
    %{
      "type" => "answerBlock",
      "attrs" => %{"answerId" => id},
      "content" => [text_paragraph(text)]
    }
  end

  defp text_paragraph(nil), do: %{"type" => "paragraph"}

  defp text_paragraph(text),
    do: %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}

  defp lueckentext_paragraph(id, text) do
    %{
      "type" => "paragraph",
      "content" => [
        %{"type" => "text", "text" => "Die Hauptstadt ist "},
        %{
          "type" => "lueckentext",
          "attrs" => %{"answerId" => id},
          "content" => if(text, do: [%{"type" => "text", "text" => text}], else: [])
        },
        %{"type" => "text", "text" => "."}
      ]
    }
  end

  defp task_item(id, label, checked) do
    %{
      "type" => "taskItem",
      "attrs" => %{"answerId" => id, "checked" => checked},
      "content" => [text_paragraph(label)]
    }
  end

  defp doc(nodes), do: %{"type" => "doc", "content" => nodes}

  defp task(sample, off \\ []),
    do: %Task{sample_solution: sample, self_check_off: off, content: %{}}

  defp submission(nodes), do: %TaskSubmission{content: doc(nodes)}

  describe "evaluate/2" do
    test "paart über die answerId, nicht über die Reihenfolge" do
      # Die Antworten stehen in umgekehrter Reihenfolge im Dokument: eine
      # positionsbasierte Paarung (wie bei Prüfungen) würde hier beides
      # verdrehen und zwei falsche Verdikte liefern.
      task = task(%{"a" => [text_paragraph("Bern")], "b" => [text_paragraph("Aare")]})
      submission = submission([answer_block("b", "Aare"), answer_block("a", "Bern")])

      assert %{verdicts: verdicts, correct: 2, total: 2} = SelfCheck.evaluate(task, submission)
      assert verdicts == %{"a" => "correct", "b" => "correct"}
    end

    test "ignoriert Gross-/Kleinschreibung, aber keine Tippfehler" do
      task = task(%{"a" => [text_paragraph("Bern")]})

      assert %{correct: 1} = SelfCheck.evaluate(task, submission([answer_block("a", "bern")]))

      assert %{correct: 0, total: 1} =
               SelfCheck.evaluate(task, submission([answer_block("a", "Bren")]))
    end

    test "akzeptiert die mit ; getrennten Alternativen der Musterlösung" do
      task = task(%{"a" => [text_paragraph("Bern; Berne")]})

      assert %{correct: 1} = SelfCheck.evaluate(task, submission([answer_block("a", "Berne")]))
      assert %{correct: 0} = SelfCheck.evaluate(task, submission([answer_block("a", "Basel")]))
    end

    test "wertet Lückentexte wie Antwortfelder" do
      task = task(%{"a" => [%{"type" => "text", "text" => "Bern"}]})
      submission = submission([lueckentext_paragraph("a", "Bern")])

      assert %{verdicts: %{"a" => "correct"}, total: 1} = SelfCheck.evaluate(task, submission)
    end

    test "vergleicht bei Checkboxen den checked-Zustand" do
      task = task(%{"a" => true, "b" => false})

      submission = submission([task_item("a", "Bern", true), task_item("b", "Zürich", true)])

      assert %{verdicts: verdicts, correct: 1, total: 2} = SelfCheck.evaluate(task, submission)
      assert verdicts == %{"a" => "correct", "b" => "wrong"}
    end

    test "eine leere Antwort ist falsch, nicht ungeprüft" do
      task = task(%{"a" => [text_paragraph("Bern")]})

      assert %{verdicts: %{"a" => "wrong"}, total: 1} =
               SelfCheck.evaluate(task, submission([answer_block("a", "   ")]))
    end

    test "abgeschaltete Felder zählen nicht in die Quote" do
      task = task(%{"a" => [text_paragraph("Bern")], "b" => [text_paragraph("Aare")]}, ["b"])
      submission = submission([answer_block("a", "Bern"), answer_block("b", "irgendwas")])

      assert %{verdicts: verdicts, correct: 1, total: 1} = SelfCheck.evaluate(task, submission)
      refute Map.has_key?(verdicts, "b")
    end

    test "Felder ohne Musterlösung zählen nicht" do
      # Ein Feld, das die Lehrperson leer gelassen hat, darf keine Quote
      # verderben — es gibt schlicht keine Vorgabe.
      task = task(%{"a" => [text_paragraph("Bern")], "b" => [text_paragraph("  ")]})
      submission = submission([answer_block("a", "Bern"), answer_block("b", "etwas")])

      assert %{correct: 1, total: 1} = SelfCheck.evaluate(task, submission)
    end

    test "ohne Antwortdokument gibt es nichts zu prüfen" do
      task = task(%{"a" => [text_paragraph("Bern")]})

      assert %{verdicts: %{}, correct: 0, total: 0} =
               SelfCheck.evaluate(task, %TaskSubmission{content: nil})
    end
  end

  describe "review_doc/3" do
    test "setzt das Verdikt als Attribut, nicht als ✅/❌ im Text" do
      task = task(%{"a" => [text_paragraph("Bern")]})
      base = doc([answer_block("a", "Basel")])

      %{"content" => [block | _]} = SelfCheck.review_doc(task, base, %{"a" => "wrong"})

      assert block["attrs"]["verdict"] == "wrong"
      refute block |> Jason.encode!() |> String.contains?("❌")
    end

    test "hängt die Musterlösung als solutionHint hinter das Antwortfeld" do
      task = task(%{"a" => [text_paragraph("Bern")]})
      base = doc([answer_block("a", "Basel")])

      %{"content" => [_answer, hint]} = SelfCheck.review_doc(task, base, %{"a" => "wrong"})

      assert hint["type"] == "solutionHint"
      assert hint |> Jason.encode!() |> String.contains?("Bern")
    end

    test "entfernt im Zwilling die answerId, damit sie nicht zweimal im DOM steht" do
      task = task(%{"a" => [text_paragraph("Bern")]})
      base = doc([answer_block("a", "Basel")])

      %{"content" => [_answer, hint]} = SelfCheck.review_doc(task, base, %{"a" => "wrong"})

      refute hint |> Jason.encode!() |> String.contains?("answerId")
    end

    test "füllt beim Lückentext den ganzen Satz nochmals" do
      task = task(%{"a" => [%{"type" => "text", "text" => "Bern"}]})
      base = doc([lueckentext_paragraph("a", "Basel")])

      %{"content" => [_paragraph, hint]} = SelfCheck.review_doc(task, base, %{"a" => "wrong"})

      json = Jason.encode!(hint)
      assert hint["type"] == "solutionHint"
      assert String.contains?(json, "Die Hauptstadt ist ")
      assert String.contains?(json, "Bern")
    end

    test "gibt Checkboxen kein zweites Feld — das Verdikt genügt dort" do
      task = task(%{"a" => true})
      base = doc([task_item("a", "Bern", false)])

      %{"content" => nodes} = SelfCheck.review_doc(task, base, %{"a" => "wrong"})

      assert length(nodes) == 1
      assert hd(nodes)["attrs"]["verdict"] == "wrong"
    end

    test "zeigt die Musterlösung auch bei abgeschalteter Prüfung — nur ohne Verdikt" do
      task = task(%{"a" => [text_paragraph("Bern")]}, ["a"])
      base = doc([answer_block("a", "eigene Formulierung")])

      %{"content" => [answer, hint]} = SelfCheck.review_doc(task, base, %{})

      refute Map.has_key?(answer["attrs"] || %{}, "verdict")
      assert hint["type"] == "solutionHint"
    end

    test "hängt keinen leeren Zwilling an ein Feld ohne Musterlösung" do
      task = task(%{"a" => []})
      base = doc([answer_block("a", "irgendwas"), lueckentext_paragraph("b", "auch")])

      %{"content" => nodes} = SelfCheck.review_doc(task, base, %{})

      assert length(nodes) == 2
      refute nodes |> Jason.encode!() |> String.contains?("solutionHint")
    end

    test "lässt die Anmerkungen der Lehrperson aus dem Zwilling heraus" do
      task = task(%{"a" => [%{"type" => "text", "text" => "Bern"}]})

      base =
        doc([
          %{
            "type" => "paragraph",
            "content" => [
              %{"type" => "lueckentext", "attrs" => %{"answerId" => "a"}, "content" => []},
              %{
                "type" => "text",
                "text" => "so nicht!",
                "marks" => [%{"type" => "teacherComment"}]
              }
            ]
          }
        ])

      %{"content" => [_paragraph, hint]} = SelfCheck.review_doc(task, base, %{"a" => "wrong"})

      refute hint |> Jason.encode!() |> String.contains?("so nicht!")
    end
  end

  describe "mehrere gültige Antworten" do
    test "das Semikolon ist ein Autorenformat und darf nicht in der Anzeige landen" do
      task = task(%{"a" => [text_paragraph("pdf;.pdf")]})
      base = doc([answer_block("a", ".pdf")])

      %{"content" => [_answer, hint]} = SelfCheck.review_doc(task, base, %{"a" => "correct"})

      json = Jason.encode!(hint)
      assert String.contains?(json, "pdf oder .pdf")
      refute String.contains?(json, ";")
    end

    test "im Lückentext liest sich der Zwilling als Satz" do
      task = task(%{"a" => [%{"type" => "text", "text" => "Bern;Berne"}]})
      base = doc([lueckentext_paragraph("a", "Berne")])

      %{"content" => [_paragraph, hint]} = SelfCheck.review_doc(task, base, %{"a" => "correct"})

      json = Jason.encode!(hint)
      assert String.contains?(json, "Die Hauptstadt ist ")
      assert String.contains?(json, "Bern oder Berne")
      refute String.contains?(json, ";")
    end

    test "die Anzeige ändert die Bewertung nicht — jede Variante zählt weiter" do
      task = task(%{"a" => [text_paragraph("pdf;.pdf")], "b" => [text_paragraph("pdf;.pdf")]})

      assert %{verdicts: verdicts, correct: 2, total: 2} =
               SelfCheck.evaluate(
                 task,
                 doc([answer_block("a", "pdf"), answer_block("b", ".pdf")])
               )

      assert verdicts == %{"a" => "correct", "b" => "correct"}
    end

    test "eine Antwort, die keiner Variante entspricht, bleibt falsch" do
      task = task(%{"a" => [text_paragraph("pdf;.pdf")]})

      assert %{verdicts: %{"a" => "wrong"}} =
               SelfCheck.evaluate(task, doc([answer_block("a", "docx")]))
    end
  end
end
