defmodule Tasky.AI.CorrectionClient do
  @moduledoc """
  Calls the Anthropic Claude API to auto-correct one exam-submission part.

  Design notes:
    * Tool-use enforces a strict response shape (no JSON-from-text parsing).
    * `temperature: 0` makes grading repeatable.
    * The system prompt is cached (`cache_control: ephemeral`) so consecutive
      corrections of the same part reuse the prefix.
    * Claude returns only a list of per-answer verdicts plus a points value.
      The caller (`BulkCorrectionRunner`) is responsible for annotating the
      submission with `__ai_id`s before the call and applying the verdicts
      back to the original document afterwards — Claude never re-emits the
      document structure.
  """

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-4-20250514"

  @tool_name "submit_correction"

  @tool %{
    "name" => @tool_name,
    "description" =>
      "Submit the verdicts for each answer node of an exam submission and the awarded points.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "verdicts" => %{
          "type" => "array",
          "description" =>
            "One entry per answer node in the submission. The id must match an `__ai_id` value present in the submission JSON.",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "verdict" => %{"type" => "string", "enum" => ["correct", "incorrect"]}
            },
            "required" => ["id", "verdict"]
          }
        },
        "points" => %{
          "type" => "number",
          "description" =>
            "Awarded points in the range [0, max_points]. Integer or decimal with 0.5 steps."
        }
      },
      "required" => ["verdicts", "points"]
    }
  }

  @doc """
  Sends an already-annotated submission (each answer node carries an
  `__ai_id` attribute) plus the sample solution to Claude.

  Returns `{:ok, %{verdicts: %{id => verdict}, points: number}}` on success,
  `{:error, reason}` on failure.
  """
  def correct_part(annotated_submission_nodes, sample_solution_nodes, max_points, opts \\ %{})
      when is_list(annotated_submission_nodes) and is_list(sample_solution_nodes) do
    case api_key() do
      key when is_binary(key) and key != "" ->
        do_correct(key, annotated_submission_nodes, sample_solution_nodes, max_points, opts)

      _ ->
        {:error, "Kein Anthropic API Key konfiguriert."}
    end
  end

  defp do_correct(api_key, submission_nodes, sample_solution_nodes, max_points, opts) do
    body = %{
      "model" => @model,
      "max_tokens" => 4096,
      "temperature" => 0,
      "system" => build_system_blocks(sample_solution_nodes, max_points, opts),
      "tools" => [@tool],
      "tool_choice" => %{"type" => "tool", "name" => @tool_name},
      "messages" => [
        %{
          "role" => "user",
          "content" => build_user_message(submission_nodes)
        }
      ]
    }

    case Req.post(@api_url,
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", "2023-06-01"}
           ],
           receive_timeout: 120_000
         ) do
      {:ok, %Req.Response{status: 200, body: response_body}} ->
        parse_response(response_body)

      {:ok, %Req.Response{status: status, body: response_body}} ->
        error_msg = extract_error_message(response_body)
        Logger.error("Claude API error (#{status}): #{error_msg}")
        {:error, "Claude API Fehler (#{status}): #{error_msg}"}

      {:error, exception} ->
        Logger.error("Claude API request failed: #{inspect(exception)}")
        {:error, "Verbindung zur Claude API fehlgeschlagen."}
    end
  end

  defp build_system_blocks(sample_solution_nodes, max_points, opts) do
    rules = build_rules(opts)

    sample_block = """
    SAMPLE SOLUTION (TipTap JSON nodes, identical for every student of this question):
    #{Jason.encode!(sample_solution_nodes)}

    MAXIMUM POINTS: #{max_points || 0}
    """

    [
      %{
        "type" => "text",
        "text" => rules <> "\n\n" <> sample_block,
        "cache_control" => %{"type" => "ephemeral"}
      }
    ]
  end

  defp build_rules(opts) do
    base = """
    You are an exam correction assistant. The exam content is in German; spelling judgments must follow German orthography.

    You receive a student's submission as TipTap/ProseMirror JSON nodes and a sample solution (also TipTap JSON nodes) with a maximum point value.

    Every answer-bearing node in the submission has been tagged with an `__ai_id` attribute inside its `attrs`. Answer-bearing types are `answerBlock`, `lueckentext`, and `taskItem`. Each such node represents ONE answer that you must judge.

    How to judge each answer type:
    - `answerBlock`, `lueckentext`: compare the student's written/filled-in text against the sample solution. Verdict is "correct" if the content matches the sample (with partial-credit reasoning allowed for the points field), otherwise "incorrect".
    - `taskItem`: the student's answer is the *checked state* (`attrs.checked` = true or false), not the option text itself. Compare the student's `checked` value against the sample solution's `checked` value for the same option. Verdict is "correct" if both match (both true OR both false), otherwise "incorrect". Every taskItem must get a verdict — including unchecked ones, because leaving a wrong option unchecked is also a correct decision.

    Your tasks:
    1. For each `__ai_id` in the submission, decide "correct" or "incorrect" using the rules above. Return one verdict per `__ai_id` — never fewer, never more.
    2. Determine a fair point score in [0, MAXIMUM POINTS] based on the overall correctness. Partial credit is allowed.

    Submit your answer by calling the `submit_correction` tool with `verdicts` and `points`.

    Rules:
    - The `verdicts` array MUST contain exactly one entry per `__ai_id` present in the submission. Do not invent ids that are not in the submission. Do not skip ids.
    - `verdict` must be the literal string "correct" or "incorrect".
    - Points may be integers or decimals with 0.5 steps (0, 0.5, 1, 1.5, 2, ...).
    - Do NOT return the document content. Only verdicts and points.

    EXAMPLES

    Example 1 — answerBlock (free text answer).
    Sample solution snippet:
      {"type":"paragraph","content":[{"type":"text","text":"Was ist die Hauptstadt von Frankreich?"}]}
      {"type":"answerBlock","content":[{"type":"paragraph","content":[{"type":"text","text":"Paris"}]}]}
    Student submission snippet:
      {"type":"paragraph","content":[{"type":"text","text":"Was ist die Hauptstadt von Frankreich?"}]}
      {"type":"answerBlock","attrs":{"__ai_id":"1"},"content":[{"type":"paragraph","content":[{"type":"text","text":"Paris"}]}]}
    Expected verdict entry: {"id":"1","verdict":"correct"}

    Example 2 — lueckentext (fill-in-the-blank, inline). The `lueckentext` node contains the student's text; compare it to the same lueckentext in the sample solution.
    Sample solution snippet:
      {"type":"paragraph","content":[
        {"type":"text","text":"Die Hauptstadt von Deutschland ist "},
        {"type":"lueckentext","content":[{"type":"text","text":"Berlin"}]},
        {"type":"text","text":"."}
      ]}
    Student submission snippet:
      {"type":"paragraph","content":[
        {"type":"text","text":"Die Hauptstadt von Deutschland ist "},
        {"type":"lueckentext","attrs":{"__ai_id":"2"},"content":[{"type":"text","text":"München"}]},
        {"type":"text","text":"."}
      ]}
    Expected verdict entry: {"id":"2","verdict":"incorrect"}  (München ≠ Berlin)

    Example 3 — taskItem (checkbox list). EVERY taskItem gets a verdict, including unchecked ones. The verdict reflects whether the student's `checked` value matches the sample solution's.
    Question: "Welche der folgenden Lebensmittel sind Obst?"
    Sample solution items (`taskList` containing three `taskItem`s):
      {"type":"taskItem","attrs":{"checked":false},"content":[{"type":"paragraph","content":[{"type":"text","text":"Schokolade"}]}]}
      {"type":"taskItem","attrs":{"checked":true}, "content":[{"type":"paragraph","content":[{"type":"text","text":"Apfel"}]}]}
      {"type":"taskItem","attrs":{"checked":false},"content":[{"type":"paragraph","content":[{"type":"text","text":"Nudeln"}]}]}
    Student submission items:
      {"type":"taskItem","attrs":{"checked":true, "__ai_id":"3"},"content":[{"type":"paragraph","content":[{"type":"text","text":"Schokolade"}]}]}
      {"type":"taskItem","attrs":{"checked":true, "__ai_id":"4"},"content":[{"type":"paragraph","content":[{"type":"text","text":"Apfel"}]}]}
      {"type":"taskItem","attrs":{"checked":false,"__ai_id":"5"},"content":[{"type":"paragraph","content":[{"type":"text","text":"Nudeln"}]}]}
    Expected verdict entries:
      {"id":"3","verdict":"incorrect"}  (student checked Schokolade but sample is unchecked)
      {"id":"4","verdict":"correct"}    (both checked)
      {"id":"5","verdict":"correct"}    (both unchecked — correctly leaving Nudeln out is also a correct decision)
    """

    spelling_note =
      if Map.get(opts, :ignore_spelling, false) do
        """

        SPELLING NOTE: Spelling and minor typos must be IGNORED when evaluating answers. Focus on whether the student conveyed the correct meaning. A misspelled but semantically correct answer is "correct".
        """
      else
        """

        SPELLING NOTE: Spelling is IMPORTANT and must be considered. Misspelled answers are "incorrect" even if the meaning is clear. This is especially important for language exams.
        """
      end

    base <> spelling_note
  end

  defp build_user_message(annotated_submission_nodes) do
    """
    STUDENT SUBMISSION (TipTap JSON nodes — answer nodes are tagged with `__ai_id`):
    #{Jason.encode!(annotated_submission_nodes)}

    Call the submit_correction tool with one verdict per `__ai_id`.
    """
  end

  defp parse_response(%{"content" => blocks}) when is_list(blocks) do
    case Enum.find(blocks, &(&1["type"] == "tool_use" and &1["name"] == @tool_name)) do
      %{"input" => %{"verdicts" => verdicts, "points" => points}}
      when is_list(verdicts) and is_number(points) ->
        case build_verdict_map(verdicts) do
          {:ok, map} -> {:ok, %{verdicts: map, points: normalize_points(points)}}
          {:error, _} = err -> err
        end

      %{"input" => other} ->
        Logger.error("Claude tool_use input had unexpected shape: #{inspect(other)}")
        {:error, "Unerwartetes Antwortformat von Claude."}

      _ ->
        Logger.error("Claude response missing #{@tool_name} tool_use block: #{inspect(blocks)}")
        {:error, "Claude hat das Korrektur-Tool nicht aufgerufen."}
    end
  end

  defp parse_response(other) do
    Logger.error("Unexpected Claude response structure: #{inspect(other)}")
    {:error, "Unerwartete Antwortstruktur von Claude."}
  end

  defp build_verdict_map(list) do
    Enum.reduce_while(list, {:ok, %{}}, fn
      %{"id" => id, "verdict" => v}, {:ok, acc}
      when is_binary(id) and v in ["correct", "incorrect"] ->
        {:cont, {:ok, Map.put(acc, id, v)}}

      bad, _acc ->
        Logger.error("Invalid verdict entry from Claude: #{inspect(bad)}")
        {:halt, {:error, "Ungültiger Verdict-Eintrag von Claude."}}
    end)
  end

  defp normalize_points(points) when is_float(points) do
    rounded = Float.round(points * 2) / 2
    if rounded == trunc(rounded), do: trunc(rounded), else: rounded
  end

  defp normalize_points(points) when is_integer(points), do: points

  defp extract_error_message(%{"error" => %{"message" => msg}}), do: msg
  defp extract_error_message(body) when is_map(body), do: inspect(body)
  defp extract_error_message(body) when is_binary(body), do: body
  defp extract_error_message(other), do: inspect(other)

  defp api_key do
    Application.get_env(:tasky, :anthropic_api_key)
  end
end
