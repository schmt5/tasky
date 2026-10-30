defmodule Tasky.Exams.ProgressTest do
  use ExUnit.Case, async: true

  alias Tasky.Exams.Exam
  alias Tasky.Exams.Progress

  defp text(t), do: %{"type" => "text", "text" => t}
  defp para(content), do: %{"type" => "paragraph", "content" => content}

  defp heading(id, label),
    do: %{
      "type" => "heading",
      "attrs" => %{"level" => 3, "partId" => id},
      "content" => [text(label)]
    }

  defp radio(gid, oid, checked),
    do: %{
      "type" => "choice",
      "attrs" => %{"groupId" => gid, "optionId" => oid, "checked" => checked}
    }

  defp task_item(id, label, checked),
    do: %{
      "type" => "taskItem",
      "attrs" => %{"answerId" => id, "checked" => checked},
      "content" => [para([text(label)])]
    }

  defp answer_block(id, ""),
    do: %{"type" => "answerBlock", "attrs" => %{"answerId" => id}, "content" => [para([])]}

  defp answer_block(id, t),
    do: %{"type" => "answerBlock", "attrs" => %{"answerId" => id}, "content" => [para([text(t)])]}

  # q-1 a radio group, q-2 three checkboxes, q-3 a free text, q-4 a free text
  # flagged for auto-correction.
  defp doc(answers \\ %{}) do
    city = Map.get(answers, :city)
    [c1, c2, c3] = Map.get(answers, :cantons, [false, false, false])

    %{
      "type" => "doc",
      "content" => [
        heading("q-1", "Hauptstadt"),
        para([radio("g1", "g1-bern", city == :bern), text(" Bern")]),
        para([radio("g1", "g1-zh", city == :zh), text(" Zürich")]),
        heading("q-2", "Kantone"),
        %{
          "type" => "taskList",
          "content" => [
            task_item("c1", "Bern", c1),
            task_item("c2", "Zürich", c2),
            task_item("c3", "Genf", c3)
          ]
        },
        heading("q-3", "Begründung"),
        answer_block("t1", Map.get(answers, :reason, "")),
        heading("q-4", "Fluss"),
        answer_block("t2", Map.get(answers, :river, ""))
      ]
    }
  end

  defp exam(attrs \\ %{}) do
    struct!(
      %Exam{
        answer_mode: "answer_fields",
        content: doc(),
        sample_solution: %{
          "g1" => "g1-bern",
          "c1" => true,
          "c2" => true,
          "c3" => false,
          "t1" => [para([text("Weil")])],
          "t2" => [para([text("Aare")])]
        },
        ai_correction_config: %{"q-4" => %{"auto_correct" => true, "ignore_case" => true}}
      },
      attrs
    )
  end

  defp statuses(answers, exam \\ exam()),
    do: exam |> Progress.prepare() |> Progress.statuses(doc(answers))

  test "prepare/1 lists the parts with their headings" do
    assert Progress.prepare(exam()).parts == [
             %{id: "q-1", label: "Hauptstadt"},
             %{id: "q-2", label: "Kantone"},
             %{id: "q-3", label: "Begründung"},
             %{id: "q-4", label: "Fluss"}
           ]
  end

  test "a submission nobody has saved yet is not started anywhere" do
    prepared = Progress.prepare(exam())
    blank = Map.new(prepared.parts, &{&1.id, :not_started})

    assert Progress.statuses(prepared, %{}) == blank
    assert Progress.statuses(prepared, nil) == blank
    assert Progress.statuses(prepared, doc()) == blank
  end

  test "a radio group is right or wrong" do
    assert %{"q-1" => :correct} = statuses(%{city: :bern})
    assert %{"q-1" => :wrong} = statuses(%{city: :zh})
  end

  test "a radio without a label still counts as chosen" do
    content = %{
      "type" => "doc",
      "content" => [heading("q-1", "Hauptstadt"), para([radio("g1", "g1-bern", true)])]
    }

    exam = exam(content: content)
    assert %{"q-1" => :correct} = exam |> Progress.prepare() |> Progress.statuses(content)
  end

  test "checkboxes are right, partly right or wrong" do
    assert %{"q-2" => :correct} = statuses(%{cantons: [true, true, false]})
    assert %{"q-2" => :partial} = statuses(%{cantons: [true, false, false]})
    assert %{"q-2" => :wrong} = statuses(%{cantons: [false, false, true]})
  end

  test "a free text without auto-correction is only answered" do
    assert %{"q-3" => :answered} = statuses(%{reason: "Weil es so ist"})
    assert %{"q-3" => :not_started} = statuses(%{reason: "   "})
  end

  test "a free text flagged for auto-correction uses its comparison options" do
    assert %{"q-4" => :correct} = statuses(%{river: "aare"})
    assert %{"q-4" => :wrong} = statuses(%{river: "Rhein"})
  end

  test "a free document is never auto-corrected" do
    exam = exam(answer_mode: "free_document")

    assert exam |> Progress.prepare() |> Progress.statuses(doc(%{city: :zh})) == %{
             "document" => :answered
           }
  end
end
