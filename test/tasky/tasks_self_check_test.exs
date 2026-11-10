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

  defp question(id),
    do: %{
      "type" => "heading",
      "attrs" => %{"level" => 3, "partId" => id},
      "content" => [%{"type" => "text", "text" => "Frage"}]
    }

  # Only the sample matters to `review_doc/3`; the content is the skeleton
  # `evaluate/2` reads the questions from.
  defp task(sample, content_nodes \\ [], config \\ %{}),
    do: %Task{
      sample_solution: sample,
      content: doc([question("q-1") | content_nodes]),
      correction_config: config
    }

  defp submission(nodes), do: %TaskSubmission{content: doc(nodes)}

  # Evaluates `nodes` as the submission against a unit whose single question
  # holds the same answer fields, under `config` for that question.
  defp evaluate(sample, nodes, config \\ nil) do
    config = if config, do: %{"q-1" => config}, else: %{}
    SelfCheck.evaluate(task(sample, nodes, config), submission(nodes))
  end

  describe "evaluate/2" do
    test "paart über die answerId, nicht über die Reihenfolge" do
      # Die Antworten stehen in umgekehrter Reihenfolge im Dokument: eine
      # positionsbasierte Paarung (wie bei Prüfungen) würde hier beides
      # verdrehen und zwei falsche Verdikte liefern.
      task =
        task(
          %{"a" => [text_paragraph("Bern")], "b" => [text_paragraph("Aare")]},
          [answer_block("a", nil), answer_block("b", nil)]
        )

      submission = submission([answer_block("b", "Aare"), answer_block("a", "Bern")])

      assert %{verdicts: verdicts, correct: 2, total: 2} = SelfCheck.evaluate(task, submission)
      assert verdicts == %{"a" => "correct", "b" => "correct"}
    end

    test "ignoriert ohne eigene Optionen Gross-/Kleinschreibung, aber keine Tippfehler" do
      sample = %{"a" => [text_paragraph("Bern")]}

      assert %{correct: 1} = evaluate(sample, [answer_block("a", "bern")])
      assert %{correct: 0, total: 1} = evaluate(sample, [answer_block("a", "Bren")])
    end

    test "akzeptiert die mit ; getrennten Alternativen der Musterlösung" do
      sample = %{"a" => [text_paragraph("Bern; Berne")]}

      assert %{correct: 1} = evaluate(sample, [answer_block("a", "Berne")])
      assert %{correct: 0} = evaluate(sample, [answer_block("a", "Basel")])
    end

    test "wertet Lückentexte wie Antwortfelder" do
      sample = %{"a" => [%{"type" => "text", "text" => "Bern"}]}

      assert %{verdicts: %{"a" => "correct"}, total: 1} =
               evaluate(sample, [lueckentext_paragraph("a", "Bern")])
    end

    test "vergleicht bei Checkboxen den checked-Zustand" do
      assert %{verdicts: verdicts, correct: 1, total: 2} =
               evaluate(%{"a" => true, "b" => false}, [
                 task_item("a", "Bern", true),
                 task_item("b", "Zürich", true)
               ])

      assert verdicts == %{"a" => "correct", "b" => "wrong"}
    end

    test "eine leere Antwort ist falsch, nicht ungeprüft" do
      assert %{verdicts: %{"a" => "wrong"}, total: 1} =
               evaluate(%{"a" => [text_paragraph("Bern")]}, [answer_block("a", "   ")])
    end

    test "Felder ohne Musterlösung zählen nicht" do
      # Ein Feld, das die Lehrperson leer gelassen hat, darf keine Quote
      # verderben — es gibt schlicht keine Vorgabe.
      sample = %{"a" => [text_paragraph("Bern")], "b" => [text_paragraph("  ")]}

      assert %{correct: 1, total: 1} =
               evaluate(sample, [answer_block("a", "Bern"), answer_block("b", "etwas")])
    end

    test "ohne Antwortdokument gibt es nichts zu prüfen" do
      task = task(%{"a" => [text_paragraph("Bern")]}, [answer_block("a", nil)])

      assert %{verdicts: %{}, correct: 0, total: 0} =
               SelfCheck.evaluate(task, %TaskSubmission{content: nil})
    end

    test "Antwortfelder vor der ersten Frage werden nicht geprüft" do
      task = %Task{
        sample_solution: %{"a" => [text_paragraph("Bern")], "b" => [text_paragraph("Aare")]},
        content: doc([answer_block("a", nil), question("q-1"), answer_block("b", nil)]),
        correction_config: %{}
      }

      submission = submission([answer_block("a", "Bern"), answer_block("b", "Aare")])

      assert %{verdicts: verdicts, total: 1} = SelfCheck.evaluate(task, submission)
      assert verdicts == %{"b" => "correct"}
    end
  end

  describe "Korrekturoptionen pro Frage" do
    test "ohne Auto-Korrektur zählen die Textfelder der Frage nicht" do
      sample = %{"a" => [text_paragraph("Bern")], "b" => true}

      assert %{verdicts: verdicts, total: 1} =
               evaluate(
                 sample,
                 [answer_block("a", "irgendwas"), task_item("b", "Bern", true)],
                 %{"auto_correct" => false}
               )

      # Checkboxen vergleichen exakt und werden darum immer geprüft.
      assert verdicts == %{"b" => "correct"}
    end

    test "Gross-/Kleinschreibung zählt, wenn die Option aus ist" do
      config = %{"auto_correct" => true, "ignore_case" => false}

      assert %{verdicts: %{"a" => "wrong"}} =
               evaluate(%{"a" => [text_paragraph("Bern")]}, [answer_block("a", "bern")], config)
    end

    test "Satzzeichen und Rechtschreibung lassen sich ignorieren" do
      config = %{"auto_correct" => true, "ignore_punctuation" => true, "ignore_spelling" => true}

      assert %{verdicts: %{"a" => "correct", "b" => "correct"}} =
               evaluate(
                 %{"a" => [text_paragraph("Bern!")], "b" => [text_paragraph("Hauptstadt")]},
                 [answer_block("a", "Bern"), answer_block("b", "Hauptstat")],
                 config
               )
    end

    test "jede Frage hat ihre eigenen Optionen" do
      task = %Task{
        sample_solution: %{"a" => [text_paragraph("Bern")], "b" => [text_paragraph("Bern")]},
        content:
          doc([
            question("q-1"),
            answer_block("a", nil),
            question("q-2"),
            answer_block("b", nil)
          ]),
        correction_config: %{"q-2" => %{"auto_correct" => true, "ignore_case" => false}}
      }

      submission = submission([answer_block("a", "bern"), answer_block("b", "bern")])

      assert %{verdicts: %{"a" => "correct", "b" => "wrong"}} =
               SelfCheck.evaluate(task, submission)
    end

    test "alles oder nichts zählt eine Checkbox-Liste als einen Eintrag" do
      list = fn a, b ->
        %{
          "type" => "taskList",
          "content" => [task_item("a", "Bern", a), task_item("b", "Zürich", b)]
        }
      end

      sample = %{"a" => true, "b" => false}
      config = %{"checkbox_scoring" => "all_or_nothing"}

      assert %{verdicts: verdicts, correct: 0, total: 1} =
               evaluate(sample, [list.(true, true)], config)

      assert verdicts == %{"a" => "wrong", "b" => "wrong"}

      assert %{correct: 1, total: 1} = evaluate(sample, [list.(true, false)], config)
      assert %{correct: 1, total: 2} = evaluate(sample, [list.(true, true)])
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

    test "zeigt die Musterlösung auch ohne Auto-Korrektur — nur ohne Verdikt" do
      task = task(%{"a" => [text_paragraph("Bern")]})
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
      assert String.contains?(json, "pdf, .pdf")
      refute String.contains?(json, ";")
    end

    test "im Lückentext liest sich der Zwilling als Satz" do
      task = task(%{"a" => [%{"type" => "text", "text" => "Bern;Berne"}]})
      base = doc([lueckentext_paragraph("a", "Berne")])

      %{"content" => [_paragraph, hint]} = SelfCheck.review_doc(task, base, %{"a" => "correct"})

      json = Jason.encode!(hint)
      assert String.contains?(json, "Die Hauptstadt ist ")
      assert String.contains?(json, "Bern, Berne")
      refute String.contains?(json, ";")
    end

    test "die Anzeige ändert die Bewertung nicht — jede Variante zählt weiter" do
      sample = %{"a" => [text_paragraph("pdf;.pdf")], "b" => [text_paragraph("pdf;.pdf")]}

      assert %{verdicts: verdicts, correct: 2, total: 2} =
               evaluate(sample, [answer_block("a", "pdf"), answer_block("b", ".pdf")])

      assert verdicts == %{"a" => "correct", "b" => "correct"}
    end

    test "eine Antwort, die keiner Variante entspricht, bleibt falsch" do
      assert %{verdicts: %{"a" => "wrong"}} =
               evaluate(%{"a" => [text_paragraph("pdf;.pdf")]}, [answer_block("a", "docx")])
    end
  end

  test "an essay field is never checked against the sample" do
    essay = %{
      "type" => "answerBlock",
      "attrs" => %{"answerId" => "e", "rich" => true},
      "content" => [text_paragraph("Mein Aufsatz")]
    }

    assert %{verdicts: verdicts, total: 0} =
             evaluate(%{"e" => [text_paragraph("Erwartungshorizont")]}, [essay])

    assert verdicts == %{}
  end

  describe "a pin image" do
    @zones [
      %{"pinId" => "a", "x" => 0.2, "y" => 0.2, "zone" => %{"shape" => "circle", "r" => 0.05}},
      %{"pinId" => "b", "x" => 0.8, "y" => 0.8, "zone" => %{"shape" => "circle", "r" => 0.05}}
    ]

    defp pin_image(pins),
      do: %{
        "type" => "imagePin",
        "attrs" => %{"answerId" => "img", "aspect" => 1.0, "pins" => pins}
      }

    test "is right with every pin in its zone, wrong with any outside" do
      both = [
        %{"pinId" => "a", "x" => 0.2, "y" => 0.21},
        %{"pinId" => "b", "x" => 0.8, "y" => 0.8}
      ]

      one = [
        %{"pinId" => "a", "x" => 0.2, "y" => 0.21},
        %{"pinId" => "b", "x" => nil, "y" => nil}
      ]

      assert %{verdicts: %{"img" => "correct"}} = evaluate(%{"img" => @zones}, [pin_image(both)])
      assert %{verdicts: %{"img" => "wrong"}} = evaluate(%{"img" => @zones}, [pin_image(one)])
    end
  end
end
