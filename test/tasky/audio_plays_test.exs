defmodule Tasky.AudioPlaysTest do
  use ExUnit.Case, async: true

  alias Tasky.AudioPlays

  defp audio(id, max),
    do: %{
      "type" => "audio",
      "attrs" => %{"audioId" => id, "src" => "/uploads/exams/1/a.mp3", "maxPlays" => max}
    }

  test "finds audio nodes anywhere in a doc" do
    doc = %{"type" => "doc", "content" => [%{"type" => "callout", "content" => [audio("a", 2)]}]}

    assert %{"attrs" => %{"audioId" => "a"}} = AudioPlays.find(doc, "a")
    assert AudioPlays.find(doc, "b") == nil
    assert [%{"attrs" => %{"audioId" => "a"}}] = AudioPlays.list(doc)
  end

  test "only a positive integer is a limit" do
    assert AudioPlays.max_plays(audio("a", 2)) == 2
    assert AudioPlays.max_plays(audio("a", nil)) == nil
    assert AudioPlays.max_plays(audio("a", 0)) == nil
    assert AudioPlays.max_plays(audio("a", "2")) == nil
  end

  test "a play counts when it starts and a running one resumes for free" do
    state = AudioPlays.state(%{}, "a")

    assert {:ok, %{"started" => 1, "active" => true} = state} = AudioPlays.start(state, 2)
    state = AudioPlays.progress(state, 12.34)
    assert {:ok, %{"started" => 1, "position" => 12.3}} = AudioPlays.start(state, 2)

    state = AudioPlays.finish(state)
    assert {:ok, state} = AudioPlays.start(state, 2)
    state = AudioPlays.finish(state)
    assert {:error, :exhausted} = AudioPlays.start(state, 2)
  end

  test "the position only moves forward, and only by playback" do
    {:ok, state} = AudioPlays.start(AudioPlays.state(%{}, "a"), 1)
    state = AudioPlays.progress(state, 20)

    assert AudioPlays.progress(state, 10)["position"] == 20
    assert AudioPlays.progress(state, 200)["position"] == 20
    assert AudioPlays.progress(state, "25")["position"] == 20
    assert AudioPlays.progress(state, 25)["position"] == 25.0
    assert AudioPlays.progress(AudioPlays.finish(state), 25)["position"] == 0
  end

  test "granting gives one play back and cancels a running one" do
    {:ok, state} = AudioPlays.start(AudioPlays.state(%{}, "a"), 1)

    assert %{"started" => 0, "active" => false} = AudioPlays.grant(state)
    assert %{"started" => 0} = AudioPlays.grant(AudioPlays.grant(state))
  end

  test "maps the stored src to the teacher's route" do
    assert AudioPlays.teacher_url(audio("a", nil)) == "/exams/1/audio/a.mp3"
    assert AudioPlays.teacher_url(%{"attrs" => %{"src" => "https://x/a.mp3"}}) == nil
  end
end
