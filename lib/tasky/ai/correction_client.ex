defmodule Tasky.AI.CorrectionClient do
  @moduledoc """
  Calls the Anthropic Claude API to auto-correct an exam submission part
  by comparing it against a sample solution.
  """

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-4-20250514"

  @doc """
  Sends the submission and sample solution JSON nodes to Claude for correction.

  Returns `{:ok, %{corrected_nodes: list(), points: number()}}` on success,
  or `{:error, reason}` on failure.
  """
  def correct_part(submission_nodes, sample_solution_nodes, max_points, opts \\ %{})
      when is_list(submission_nodes) and is_list(sample_solution_nodes) do
    case api_key() do
      key when is_binary(key) and key != "" ->
        do_correct(key, submission_nodes, sample_solution_nodes, max_points, opts)

      _ ->
        {:error, "Kein Anthropic API Key konfiguriert."}
    end
  end

  defp do_correct(api_key, submission_nodes, sample_solution_nodes, max_points, opts) do
    system_prompt = build_system_prompt(opts)
    user_message = build_user_message(submission_nodes, sample_solution_nodes, max_points)

    body = %{
      "model" => @model,
      "max_tokens" => 8192,
      "system" => system_prompt,
      "messages" => [
        %{"role" => "user", "content" => user_message}
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

  defp build_system_prompt(opts) do
    base = """
    You are an exam correction assistant. You receive two JSON documents representing parts of an exam in TipTap/ProseMirror JSON format:

    1. A student's submission (TipTap JSON nodes array)
    2. The teacher's sample solution (TipTap JSON nodes array) with the maximum achievable points

    Your tasks:
    1. Analyze both documents to identify which content represents ANSWERS (text the student wrote/selected, typically inside "answerBlock" nodes, filled-in "lueckentext" nodes, or checked "taskItem" nodes) versus structural CONTENT (headings, questions, instructions).
    2. Compare each student answer against the corresponding part in the sample solution.
    3. For each answer: prepend ✅ to the text if correct, or ❌ if incorrect. Only modify text nodes that are part of answers. Do NOT modify structural content, headings, or question text.
    4. Determine a fair point score between 0 and the maximum points based on overall correctness. Partial credit is allowed.

    IMPORTANT RULES:
    - Return ONLY valid JSON, no markdown code fences, no explanation.
    - The JSON must have exactly two keys: "corrected_nodes" (the edited submission nodes array with ✅/❌ markers) and "points" (a number between 0 and max points).
    - Keep the exact same JSON structure of the submission nodes. Only prepend ✅ or ❌ to text content within answer areas.
    - Do NOT remove or restructure any nodes. Only modify "text" values within answer nodes.
    - If a "text" node already starts with ✅ or ❌, do NOT add another marker.
    - Points can be integers or decimals with 0.5 steps (e.g. 0, 0.5, 1, 1.5, 2, ...).
    """

    spelling_note =
      if Map.get(opts, :ignore_spelling, false) do
        """

        SPELLING NOTE: Spelling and minor typos should be IGNORED when evaluating answers. Focus only on whether the student conveyed the correct meaning and content. A misspelled but semantically correct answer should be marked as ✅ correct. Only mark answers as ❌ incorrect if they are factually wrong, not because of spelling errors.
        """
      else
        """

        SPELLING NOTE: Spelling is IMPORTANT and must be considered when evaluating answers. Answers must be spelled correctly to be marked as ✅ correct. Misspelled words in answers should be marked as ❌ incorrect, even if the intended meaning is clear. This is especially important for language exams where exact spelling matters.
        """
      end

    base <> spelling_note
  end

  defp build_user_message(submission_nodes, sample_solution_nodes, max_points) do
    """
    STUDENT SUBMISSION (JSON nodes):
    #{Jason.encode!(submission_nodes)}

    SAMPLE SOLUTION (JSON nodes):
    #{Jason.encode!(sample_solution_nodes)}

    MAXIMUM POINTS: #{max_points || 0}

    Please correct the submission and return the result as JSON with "corrected_nodes" and "points".
    """
  end

  defp parse_response(%{"content" => [%{"type" => "text", "text" => text} | _]}) do
    # Claude may wrap JSON in code fences, strip them
    json_text =
      text
      |> String.trim()
      |> strip_code_fences()

    case Jason.decode(json_text) do
      {:ok, %{"corrected_nodes" => nodes, "points" => points}}
      when is_list(nodes) and is_number(points) ->
        {:ok, %{corrected_nodes: nodes, points: normalize_points(points)}}

      {:ok, _other} ->
        Logger.error("Claude returned unexpected JSON structure: #{json_text}")
        {:error, "Unerwartetes Antwortformat von Claude."}

      {:error, decode_error} ->
        Logger.error(
          "Failed to parse Claude response as JSON: #{inspect(decode_error)}, text: #{json_text}"
        )

        {:error, "Claude-Antwort konnte nicht als JSON gelesen werden."}
    end
  end

  defp parse_response(other) do
    Logger.error("Unexpected Claude response structure: #{inspect(other)}")
    {:error, "Unerwartete Antwortstruktur von Claude."}
  end

  defp strip_code_fences(text) do
    text
    |> String.replace(~r/\A```(?:json)?\s*\n?/, "")
    |> String.replace(~r/\n?```\s*\z/, "")
  end

  defp normalize_points(points) when is_float(points) do
    # Round to nearest 0.5
    rounded = Float.round(points * 2) / 2

    if rounded == trunc(rounded) do
      trunc(rounded)
    else
      rounded
    end
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
