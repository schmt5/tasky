defmodule Tasky.ExamsPhasesTest do
  use Tasky.DataCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams
  alias Tasky.Exams.Exam
  alias Tasky.Repo

  setup do
    scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
    %{scope: scope}
  end

  defp question(part_id, text) do
    attrs = if part_id, do: %{"level" => 3, "partId" => part_id}, else: %{"level" => 3}

    %{
      "type" => "heading",
      "attrs" => attrs,
      "content" => [%{"type" => "text", "text" => text}]
    }
  end

  defp doc(nodes), do: %{"type" => "doc", "content" => nodes}

  defp two_part_exam(scope, opts \\ []) do
    exam_fixture(
      Keyword.merge(
        [scope: scope, attrs: %{content: doc([question("p1", "Eins"), question("p2", "Zwei")])}],
        opts
      )
    )
  end

  describe "part_ids" do
    test "follow the content on every save", %{scope: scope} do
      exam = two_part_exam(scope)
      assert exam.part_ids == ["p1", "p2"]

      {:ok, exam} =
        exam
        |> Exam.document_changeset(%{content: doc([question("p3", "Drei")])})
        |> Repo.update()

      assert exam.part_ids == ["p3"]
    end

    test "follow the editor's save", %{scope: scope} do
      exam = two_part_exam(scope)

      {:ok, exam} =
        Exams.save_exam_structure(
          scope,
          exam,
          doc([question("p2", "Zwei"), question("p4", "Vier")])
        )

      assert exam.part_ids == ["p2", "p4"]
    end

    test "a free-document exam has its one part", %{scope: scope} do
      exam = exam_fixture(scope: scope, answer_mode: "free_document")
      assert exam.part_ids == [Tasky.ExamDoc.free_document_part_id()]
    end

    test "headings without a partId get the positional ids", %{scope: scope} do
      content = doc([question(nil, "Eins"), question(nil, "Zwei")])
      exam = exam_fixture(scope: scope, attrs: %{content: content})

      expected =
        content |> Exams.split_content_into_parts("answer_fields") |> Enum.map(& &1.id)

      assert exam.part_ids == expected
      assert expected != []
    end

    test "a duplicate carries them", %{scope: scope} do
      exam = two_part_exam(scope)
      {:ok, copy} = Exams.duplicate_exam(scope, exam, "Kopie")

      assert copy.part_ids == ["p1", "p2"]
    end
  end
end
