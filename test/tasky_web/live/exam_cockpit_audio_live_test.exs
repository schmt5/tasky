defmodule TaskyWeb.ExamCockpitAudioLiveTest do
  use TaskyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Tasky.AccountsFixtures
  import Tasky.ExamsFixtures

  alias Tasky.Exams

  @content %{
    "type" => "doc",
    "content" => [
      %{
        "type" => "audio",
        "attrs" => %{
          "audioId" => "hoer-1",
          "src" => "/uploads/exams/0/a.mp3",
          "title" => "Hörtext",
          "maxPlays" => 1
        }
      }
    ]
  }

  test "shows the plays and gives one back", %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})

    exam =
      exam_fixture(
        scope: user_scope_fixture(teacher),
        status: "running",
        attrs: %{content: @content}
      )

    submission = exam_submission_fixture(exam)

    {:ok, src} =
      Tasky.Uploads.save_exam_audio(exam.id, %Plug.Upload{
        path: write_tmp("ID3" <> "frames"),
        filename: "a.mp3"
      })

    exam
    |> Exams.Exam.document_changeset(%{
      "content" => put_in(@content, ["content", Access.at(0), "attrs", "src"], src)
    })
    |> Tasky.Repo.update!()

    {:ok, _} = Exams.start_audio_play(submission, "hoer-1")
    {:ok, _} = Exams.finish_audio_play(submission, "hoer-1")

    {:ok, view, _html} = conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/cockpit")
    assert has_element?(view, "#audio-plays-#{submission.id}-hoer-1", "1/1")

    view |> element("#grant-audio-play-#{submission.id}-hoer-1") |> render_click()

    assert has_element?(view, "#audio-plays-#{submission.id}-hoer-1", "0/1")
    refute has_element?(view, "#grant-audio-play-#{submission.id}-hoer-1")
    assert {:ok, %{"started" => 1}} = Exams.start_audio_play(submission, "hoer-1")
  end

  test "shows nothing for blocks without a limit", %{conn: conn} do
    teacher = user_fixture(%{role: "teacher"})
    content = put_in(@content, ["content", Access.at(0), "attrs", "maxPlays"], nil)

    exam =
      exam_fixture(
        scope: user_scope_fixture(teacher),
        status: "running",
        attrs: %{content: content}
      )

    submission = exam_submission_fixture(exam)

    {:ok, view, _html} = conn |> log_in_user(teacher) |> live(~p"/exams/#{exam}/cockpit")
    refute has_element?(view, "#audio-plays-#{submission.id}-hoer-1")
  end

  defp write_tmp(bytes) do
    path = Path.join(System.tmp_dir!(), "audio_#{System.unique_integer([:positive])}")
    File.write!(path, bytes)
    path
  end
end
