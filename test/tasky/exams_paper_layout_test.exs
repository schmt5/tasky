defmodule Tasky.ExamsPaperLayoutTest do
  use Tasky.DataCase, async: true

  import Tasky.AccountsFixtures

  alias Tasky.Exams

  defp content do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 3, "partId" => "q-1"},
          "content" => [%{"type" => "text", "text" => "Frage Eins"}]
        },
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => "a1"},
          "content" => [%{"type" => "paragraph"}]
        }
      ]
    }
  end

  defp create_exam do
    scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
    {:ok, exam} = Exams.create_exam(scope, %{name: "Test Prüfung", content: content()})
    %{scope: scope, exam: exam}
  end

  defp doc_with(lines) do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "answerBlock",
          "attrs" => %{"answerId" => "a1"},
          "content" => List.duplicate(%{"type" => "paragraph"}, lines)
        }
      ]
    }
  end

  describe "update_paper_layout/3" do
    test "stores only the line counts" do
      %{scope: scope, exam: exam} = create_exam()

      assert {:ok, updated} = Exams.update_paper_layout(scope, exam, doc_with(5))
      assert updated.paper_layout == %{"a1" => 5}
    end

    test "never touches the exam content" do
      # The whole reason paper_layout is its own column: the paper version
      # sizes a box with empty paragraphs, and those must not end up in the
      # document the learners sit.
      %{scope: scope, exam: exam} = create_exam()

      {:ok, updated} = Exams.update_paper_layout(scope, exam, doc_with(11))

      assert updated.content == content()
      assert Exams.get_exam!(scope, exam.id).content == content()
    end

    test "is last-write-wins, so resizing the same box twice is fine" do
      %{scope: scope, exam: exam} = create_exam()

      {:ok, _} = Exams.update_paper_layout(scope, exam, doc_with(3))
      {:ok, updated} = Exams.update_paper_layout(scope, exam, doc_with(8))

      assert updated.paper_layout == %{"a1" => 8}
    end

    test "an empty document clears the layout rather than raising" do
      %{scope: scope, exam: exam} = create_exam()

      assert {:ok, updated} =
               Exams.update_paper_layout(scope, exam, %{"type" => "doc", "content" => []})

      assert updated.paper_layout == %{}
    end

    test "a foreign teacher is refused" do
      %{exam: exam} = create_exam()
      other = user_scope_fixture(user_fixture(%{role: "teacher"}))

      assert {:error, :unauthorized} = Exams.update_paper_layout(other, exam, doc_with(4))
    end

    test "a learner is refused" do
      %{exam: exam} = create_exam()
      student = user_scope_fixture(user_fixture(%{role: "student"}))

      assert {:error, :unauthorized} = Exams.update_paper_layout(student, exam, doc_with(4))
    end
  end

  describe "duplicating an exam" do
    test "carries the paper layout over" do
      # The copy keeps the document's answerIds, so the sizing still points at
      # the boxes it was measured for — and it is manual work worth keeping.
      %{scope: scope, exam: exam} = create_exam()
      {:ok, exam} = Exams.update_paper_layout(scope, exam, doc_with(7))

      {:ok, copy} = Exams.duplicate_exam(scope, exam, "Kopie")

      assert copy.paper_layout == %{"a1" => 7}
      assert copy.id != exam.id
    end

    test "the copy's answer ids still match the carried layout" do
      %{scope: scope, exam: exam} = create_exam()
      {:ok, exam} = Exams.update_paper_layout(scope, exam, doc_with(7))

      {:ok, copy} = Exams.duplicate_exam(scope, exam, "Kopie")

      ids = Map.keys(Tasky.ExamPaper.extract_layout(copy.content))

      assert Enum.all?(Map.keys(copy.paper_layout), &(&1 in ids))
    end

    test "an exam that was never sized copies without one" do
      %{scope: scope, exam: exam} = create_exam()

      {:ok, copy} = Exams.duplicate_exam(scope, exam, "Kopie")

      assert is_nil(copy.paper_layout)
    end

    test "resizing the copy leaves the original alone" do
      %{scope: scope, exam: exam} = create_exam()
      {:ok, exam} = Exams.update_paper_layout(scope, exam, doc_with(7))
      {:ok, copy} = Exams.duplicate_exam(scope, exam, "Kopie")

      {:ok, _} = Exams.update_paper_layout(scope, copy, doc_with(2))

      assert Exams.get_exam!(scope, exam.id).paper_layout == %{"a1" => 7}
    end
  end
end
