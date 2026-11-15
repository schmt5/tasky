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
    task = Tasky.TasksFixtures.sample_solution_fixture(task, content([paragraph("Vier")]))

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

    test "embeds the picture of a pin image in both variants" do
      scope = user_scope_fixture(user_fixture(%{role: "teacher"}))
      task = task_fixture(scope, %{name: "Karte"})

      {:ok, [png]} = Typst.render_to_png("#set page(width: 40pt, height: 30pt)\n#rect()", [])
      path = Path.join(System.tmp_dir!(), "pin-#{System.unique_integer([:positive])}.png")
      File.write!(path, png)
      on_exit(fn -> File.rm(path) end)

      {:ok, src} =
        Tasky.Uploads.save_task_image(task.id, %Plug.Upload{
          path: path,
          filename: "karte.png",
          content_type: "image/png"
        })

      pin_image = fn pins ->
        %{
          "type" => "imagePin",
          "attrs" => %{"answerId" => "pin", "src" => src, "aspect" => 4 / 3, "pins" => pins}
        }
      end

      {:ok, task} =
        Tasks.save_task_content(scope, task, %{
          "type" => "doc",
          "content" => [pin_image.([%{"pinId" => "p1"}])]
        })

      solution = [
        %{"pinId" => "p1", "x" => 0.5, "y" => 0.5, "zone" => %{"shape" => "circle", "r" => 0.1}}
      ]

      task =
        Tasky.TasksFixtures.sample_solution_fixture(task, %{
          "type" => "doc",
          "content" => [pin_image.(solution)]
        })

      for variant <- [:worksheet, :solution] do
        assert {:ok, pdf} = TaskPdf.render(task, variant)
        assert pdf =~ ~r{/Subtype\s*/Image}, "#{variant} has no image"
      end
    end
  end
end
