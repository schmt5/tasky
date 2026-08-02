defmodule Tasky.CourseExportTest do
  use ExUnit.Case, async: true

  alias Tasky.Courses.Course
  alias Tasky.Courses.CourseExport
  alias Tasky.Tasks.Task
  alias Tasky.Tasks.TaskAttachment
  alias Tasky.Tasks.TaskUploadField

  defp course(attrs \\ %{}), do: struct(%Course{name: "Webbau"}, attrs)

  defp task(attrs) do
    struct(
      %Task{name: "Einheit", status: "published", attachments: [], upload_fields: []},
      attrs
    )
  end

  defp content(string) do
    %{
      "type" => "doc",
      "content" => [
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => string}]}
      ]
    }
  end

  test "renders title, description and a unit count" do
    markdown =
      CourseExport.to_markdown(
        course(%{description: "Grundlagen des Webbaus"}),
        [task(%{name: "Einstieg", content: content("Hallo")})]
      )

    assert markdown =~ "# Webbau"
    assert markdown =~ "Grundlagen des Webbaus"
    assert markdown =~ "Export von 1 Lerneinheit dieses Kurses"
    assert markdown =~ "## 1. Einstieg"
    assert markdown =~ "Hallo"
  end

  test "uses the plural unit word and numbers units in the given order" do
    markdown =
      CourseExport.to_markdown(course(), [
        task(%{name: "Erste"}),
        task(%{name: "Zweite"}),
        task(%{name: "Dritte"})
      ])

    assert markdown =~ "Export von 3 Lerneinheiten"

    assert [_before, first, second, third] = String.split(markdown, "## ")
    assert first =~ "1. Erste"
    assert second =~ "2. Zweite"
    assert third =~ "3. Dritte"
  end

  test "a course without units says so and adds no legend" do
    markdown = CourseExport.to_markdown(course(), [])

    assert markdown =~ "Dieser Kurs enthält noch keine Lerneinheiten."
    refute markdown =~ "Legende"
  end

  test "marks drafts, archived, extended and locked units" do
    markdown =
      CourseExport.to_markdown(course(), [
        task(%{name: "A", status: "draft"}),
        task(%{name: "B", status: "archived"}),
        task(%{name: "C", extended: true, locked: true})
      ])

    assert markdown =~ "_Entwurf_"
    assert markdown =~ "_Archiviert_"

    assert markdown =~
             "_Erweiterte (freiwillige) Lerneinheit · Für Lernende noch nicht freigeschaltet_"
  end

  test "a published, mandatory, unlocked unit carries no status line" do
    markdown = CourseExport.to_markdown(course(), [task(%{name: "A", content: content("Text")})])

    refute markdown =~ "Entwurf"
    refute markdown =~ "freigeschaltet"
  end

  test "an empty unit is called out instead of leaving a hole" do
    for empty <- [nil, %{}, %{"type" => "doc", "content" => []}] do
      markdown = CourseExport.to_markdown(course(), [task(%{name: "A", content: empty})])
      assert markdown =~ "Diese Lerneinheit enthält noch keinen Inhalt."
    end
  end

  test "lists attachments and upload fields, flagging required ones" do
    unit =
      task(%{
        name: "A",
        attachments: [
          %TaskAttachment{original_name: "dossier.pdf"},
          %TaskAttachment{original_name: "vorlage.xlsx"}
        ],
        upload_fields: [
          %TaskUploadField{label: "Skizze", required: true},
          %TaskUploadField{label: "Reflexion", required: false}
        ]
      })

    markdown = CourseExport.to_markdown(course(), [unit])

    assert markdown =~ "**Anhänge:** dossier.pdf, vorlage.xlsx"
    assert markdown =~ "**Von Lernenden abzugebende Dateien:** Skizze (Pflicht), Reflexion"
  end

  test "passes options through to the converter" do
    unit =
      task(%{
        name: "A",
        content: %{
          "type" => "doc",
          "content" => [%{"type" => "image", "attrs" => %{"src" => "/uploads/tasks/1/a.png"}}]
        }
      })

    markdown = CourseExport.to_markdown(course(), [unit], base_url: "https://tasky.test")

    assert markdown =~ "https://tasky.test/uploads/tasks/1/a.png"
  end
end
