defmodule Tasky.ExamsAudioTest do
  @moduledoc """
  Audio-Blöcke in einer Prüfung: Der Server zählt die Durchgänge, die Limite
  kommt aus dem Prüfungsinhalt, und nach der Abgabe startet nichts mehr.
  """
  use Tasky.DataCase, async: true

  import Tasky.ExamsFixtures

  alias Tasky.Exams

  defp doc(max) do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "audio",
          "attrs" => %{
            "audioId" => "hoer-1",
            "src" => "/uploads/exams/0/a.mp3",
            "maxPlays" => max
          }
        }
      ]
    }
  end

  defp running_submission(max) do
    exam = exam_fixture(status: "running", attrs: %{content: doc(max)})
    src = "/uploads/exams/#{exam.id}/#{Ecto.UUID.generate()}.mp3"
    put_audio_file(src)
    exam = set_src(exam, src, max)
    {exam, exam_submission_fixture(exam)}
  end

  test "counts plays up to the limit and resumes a running one" do
    {_exam, submission} = running_submission(2)

    assert {:ok, %{"started" => 1, "active" => true, "maxPlays" => 2}} =
             Exams.start_audio_play(submission, "hoer-1")

    assert {:ok, %{"position" => 4.0}} = Exams.record_audio_progress(submission, "hoer-1", 4)

    # A reload: the same play, at the same place.
    assert {:ok, %{"started" => 1, "position" => 4.0}} =
             Exams.start_audio_play(submission, "hoer-1")

    assert {:ok, %{"active" => false}} = Exams.finish_audio_play(submission, "hoer-1")
    assert {:ok, %{"started" => 2}} = Exams.start_audio_play(submission, "hoer-1")
    assert {:ok, _} = Exams.finish_audio_play(submission, "hoer-1")
    assert {:error, :exhausted} = Exams.start_audio_play(submission, "hoer-1")
  end

  test "an unknown block is not found" do
    {_exam, submission} = running_submission(1)
    assert {:error, :not_found} = Exams.start_audio_play(submission, "nope")
  end

  test "a play is not spent on a file that does not load" do
    exam = exam_fixture(status: "running", attrs: %{content: doc(1)})
    submission = exam_submission_fixture(exam)

    assert {:error, :file_missing} = Exams.start_audio_play(submission, "hoer-1")

    assert %{"started" => 0} =
             Tasky.AudioPlays.state(Tasky.Repo.reload!(submission).audio_plays, "hoer-1")
  end

  test "nothing starts once the exam no longer runs or is handed in" do
    exam = exam_fixture(status: "open", attrs: %{content: doc(1)})
    submission = exam_submission_fixture(exam)
    assert {:error, :exam_not_running} = Exams.start_audio_play(submission, "hoer-1")

    {_exam, submission} = running_submission(1)
    {:ok, _} = Exams.submit_exam_submission(submission)
    assert {:error, :already_submitted} = Exams.start_audio_play(submission, "hoer-1")
  end

  test "the file is only handed out during a play" do
    {_exam, submission} = running_submission(1)

    assert {:error, :not_playable} = Exams.learner_audio_source(submission.exam_token, "hoer-1")
    {:ok, _} = Exams.start_audio_play(submission, "hoer-1")

    assert {:ok, {_source, "audio/mpeg"}} =
             Exams.learner_audio_source(submission.exam_token, "hoer-1")

    {:ok, _} = Exams.finish_audio_play(submission, "hoer-1")
    assert {:error, :not_playable} = Exams.learner_audio_source(submission.exam_token, "hoer-1")
  end

  test "the teacher gives a play back" do
    {exam, submission} = running_submission(1)
    {:ok, _} = Exams.start_audio_play(submission, "hoer-1")
    {:ok, _} = Exams.finish_audio_play(submission, "hoer-1")

    scope = Tasky.AccountsFixtures.user_scope_fixture(Tasky.Accounts.get_user!(exam.teacher_id))
    assert {:ok, _} = Exams.grant_audio_play(scope, submission, "hoer-1")
    assert {:ok, %{"started" => 1}} = Exams.start_audio_play(submission, "hoer-1")

    other =
      Tasky.AccountsFixtures.user_scope_fixture(
        Tasky.AccountsFixtures.user_fixture(%{role: "teacher"})
      )

    assert {:error, :unauthorized} = Exams.grant_audio_play(other, submission, "hoer-1")
  end

  defp set_src(exam, src, max) do
    content = put_in(doc(max), ["content", Access.at(0), "attrs", "src"], src)
    exam |> Exams.Exam.document_changeset(%{"content" => content}) |> Tasky.Repo.update!()
  end

  defp put_audio_file("/uploads/" <> key) do
    path = Path.join(Tasky.Uploads.dir(), key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "ID3" <> :binary.copy(<<0>>, 64))
  end
end
