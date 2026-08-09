defmodule Tasky.FeedbackFixtures do
  @moduledoc """
  Test helpers for the anonymous course feedback mailbox.
  """

  alias Tasky.Feedback.Message
  alias Tasky.Repo

  @doc """
  Writes a message straight to the database.

  Bypasses `Tasky.Feedback.create_message/3` on purpose: tests that set up a
  full mailbox must not trip the rate limit, and some need a message whose
  sender is already known to be stored.
  """
  def feedback_message_fixture(course, student, attrs \\ %{}) do
    %Message{}
    |> Ecto.Changeset.change(%{
      course_id: course.id,
      student_id: student.id,
      body: Map.get(attrs, :body, "Das Tempo ist zu hoch."),
      read_at: Map.get(attrs, :read_at)
    })
    |> Repo.insert!()
  end
end
