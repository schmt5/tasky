defmodule Tasky.TaskPdfTest do
  use Tasky.DataCase, async: true

  import Tasky.AccountsFixtures
  import Tasky.TasksFixtures

  alias Tasky.TaskPdf
  alias Tasky.Tasks

  defp paragraph(text),
    do: %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}

  defp content(answer) do
    %{
      "type" => "doc",
      "content" => [
        paragraph("Was ist 2 + 2?"),
        %{"type" => "answerBlock", "attrs" => %{"answerId" => "a"}, "content" => answer}
      ]
    }
  end

  setup do
    scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
    task = task_fixture(scope, %{name: "Rechnen"})
    {:ok, task} = Tasks.save_task_content(scope, task, content([%{"type" => "paragraph"}]))
    {:ok, task} = Tasks.save_sample_solution(scope, task, content([paragraph("Vier")]))

    %{task: task}
  end

  describe "data/2" do
    test "the worksheet has empty writing lines", %{task: task} do
      data = TaskPdf.data(task, :worksheet)

      assert data["mode"] == "paper"
      assert data["title"] == "Rechnen – Arbeitsblatt"
      assert [_question, block] = data["doc"]["content"]
      assert block["content"] == List.duplicate(%{"type" => "paragraph"}, 4)
    end

    test "the solution has the answer filled in", %{task: task} do
      data = TaskPdf.data(task, :solution)

      assert data["mode"] == "review"
      assert data["title"] == "Rechnen – Musterlösung"
      assert [_question, block] = data["doc"]["content"]
      assert block["content"] == [paragraph("Vier")]
    end
  end

  describe "render/2" do
    test "renders both variants", %{task: task} do
      assert {:ok, "%PDF" <> _} = TaskPdf.render(task, :worksheet)
      assert {:ok, "%PDF" <> _} = TaskPdf.render(task, :solution)
    end
  end
end
