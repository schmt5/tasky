defmodule Tasky.AudioPlays do
  @moduledoc """
  Audio blocks (`audio` node) and how often a learner may play them.

  The teacher sets `maxPlays` on the node; `nil` means no limit. The count of
  each learner lives in `audio_plays` on their submission, keyed by the node's
  `audioId`, never in the answer doc:

      %{"<audioId>" => %{"started" => 2, "active" => true, "position" => 73.4}}

  A play counts the moment it starts. While it is `active`, a reload picks it
  up again at `position` without costing a new one; only its end closes it.
  `position` only ever moves forward — the learner may pause, not rewind.

  The limit is always read from the server's own document (the exam's or the
  unit's content), never from what a client sends.

  Pure functions only; the contexts lock the rows and write the result.
  """

  @typedoc "One block's state."
  @type state :: %{String.t() => term()}

  @empty %{"started" => 0, "active" => false, "position" => 0}

  # A client reports its position every few seconds. A report further ahead
  # than that is a seek, not playback, and is not taken.
  @max_progress_step 30

  @doc "The audio node with `audio_id` in `doc`, or nil."
  def find(doc, audio_id) when is_binary(audio_id), do: do_find(doc, audio_id)
  def find(_doc, _audio_id), do: nil

  defp do_find(%{"type" => "audio", "attrs" => %{"audioId" => id}} = node, id), do: node

  defp do_find(%{"content" => content}, id) when is_list(content),
    do: Enum.find_value(content, &do_find(&1, id))

  defp do_find(_node, _id), do: nil

  @doc "The play limit of an audio node: a positive integer, or nil for none."
  def max_plays(%{"attrs" => %{"maxPlays" => max}}) when is_integer(max) and max > 0, do: max
  def max_plays(_node), do: nil

  @doc "The `src` of an audio node, or nil."
  def src(%{"attrs" => %{"src" => "/uploads/" <> _ = src}}), do: src
  def src(_node), do: nil

  @doc """
  Where the teacher plays the file of an audio node (`TaskyWeb.AudioController`):
  `/uploads/exams/1/x.mp3` → `/exams/1/audio/x.mp3`. Nil for anything else.
  """
  def teacher_url(node) do
    case src(node) do
      "/uploads/" <> rest ->
        case String.split(rest, "/") do
          [kind, id, file] when kind in ["exams", "tasks"] -> "/#{kind}/#{id}/audio/#{file}"
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc "The state of one block in a submission's `audio_plays`."
  @spec state(map() | nil, String.t()) :: state()
  def state(plays, audio_id) when is_map(plays) do
    case plays[audio_id] do
      %{} = s -> Map.merge(@empty, Map.take(s, Map.keys(@empty)))
      _ -> @empty
    end
  end

  def state(_plays, _audio_id), do: @empty

  @doc """
  Starts a play, or resumes the active one. `{:ok, state}` or
  `{:error, :exhausted}` once every play is used.
  """
  @spec start(state(), pos_integer() | nil) :: {:ok, state()} | {:error, :exhausted}
  def start(%{"active" => true} = state, _max), do: {:ok, state}

  def start(%{"started" => started} = state, max) when is_nil(max) or started < max,
    do: {:ok, %{state | "started" => started + 1, "active" => true, "position" => 0}}

  def start(_state, _max), do: {:error, :exhausted}

  @doc "Records how far the active play has got. Ignored when none is active."
  @spec progress(state(), term()) :: state()
  def progress(%{"active" => true, "position" => old} = state, position)
      when is_number(position) and position > old and position <= old + @max_progress_step,
      do: %{state | "position" => Float.round(position * 1.0, 1)}

  def progress(state, _position), do: state

  @doc "Closes the active play."
  @spec finish(state()) :: state()
  def finish(state), do: %{state | "active" => false, "position" => 0}

  @doc """
  Gives a learner one play back (a teacher's call, after a technical
  problem): an active play is cancelled, a finished one no longer counts.
  """
  @spec grant(state()) :: state()
  def grant(%{"started" => started} = state),
    do: %{state | "started" => max(started - 1, 0), "active" => false, "position" => 0}

  @doc "Whether the file may be served right now."
  def playable?(state, max), do: is_nil(max) or state["active"] == true

  @doc "What the learner's player is told: the state plus the limit."
  def view(state, max), do: Map.put(state, "maxPlays", max)

  @doc "Puts one block's state back into the submission's map."
  def put(plays, audio_id, state), do: Map.put(plays || %{}, audio_id, state)

  @doc "Every audio node in `doc`, in document order."
  def list(doc) do
    doc |> collect([]) |> Enum.reverse()
  end

  defp collect(%{"type" => "audio", "attrs" => %{"audioId" => id}} = node, acc)
       when is_binary(id),
       do: [node | acc]

  defp collect(%{"content" => content}, acc) when is_list(content),
    do: Enum.reduce(content, acc, &collect/2)

  defp collect(_node, acc), do: acc
end
