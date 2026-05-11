defmodule Tasky.AI.CorrectionClient do
  @moduledoc """
  Calls the Anthropic Claude API to auto-correct an exam submission part
  by comparing it against a sample solution.

  Uses tool-use to enforce the response shape, `temperature: 0` for
  repeatable grading, and prompt caching on the system block (rules +
  sample solution) so consecutive corrections of the same part within
  the cache TTL reuse the prefix.
  """

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-4-20250514"

  @tool_name "submit_correction"

  @tool %{
    "name" => @tool_name,
    "description" =>
      "Submit the corrected exam submission. Provide the full corrected_nodes array (the student submission with ✅/❌ markers prepended to answer text) and the awarded points.",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "corrected_nodes" => %{
          "type" => "array",
          "description" =>
            "The student submission nodes, structurally unchanged, with ✅ or ❌ prepended to text content within answer nodes."
        },
        "points" => %{
          "type" => "number",
          "description" =>
            "Awarded points in the range [0, max_points]. Integer or decimal with 0.5 steps."
        }
      },
      "required" => ["corrected_nodes", "points"]
    }
  }

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
    body = %{
      "model" => @model,
      "max_tokens" => 8192,
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

    cacheable_text = rules <> "\n\n" <> sample_block

    [
      %{
        "type" => "text",
        "text" => cacheable_text,
        "cache_control" => %{"type" => "ephemeral"}
      }
    ]
  end

  defp build_rules(opts) do
    base = """
    You are an exam correction assistant. The exam content is in German; spelling judgments must follow German orthography.

    You receive a student's submission (TipTap/ProseMirror JSON nodes array) and a sample solution (also TipTap JSON nodes) with a maximum point value.

    Your tasks:
    1. Identify which content represents ANSWERS (text the student wrote/selected, typically inside "answerBlock" nodes, filled-in "lueckentext" nodes, or checked "taskItem" nodes) versus structural CONTENT (headings, questions, instructions).
    2. Compare each student answer against the sample solution.
    3. For each answer: prepend ✅ to the text if correct, or ❌ if incorrect. Only modify text nodes that are part of answers. Do NOT modify structural content, headings, or question text.
    4. Determine a fair point score between 0 and the maximum points based on overall correctness. Partial credit is allowed.

    IMPORTANT RULES:
    - Submit the result by calling the `submit_correction` tool.
    - The `corrected_nodes` value must keep the exact same JSON structure as the submission nodes — same node order, same node types, same attributes. Only modify "text" values within answer nodes.
    - Do NOT remove or restructure any nodes.
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

  defp build_user_message(submission_nodes) do
    """
    STUDENT SUBMISSION (TipTap JSON nodes):
    #{Jason.encode!(submission_nodes)}

    Please correct the submission by calling the submit_correction tool.
    """
  end

  defp parse_response(%{"content" => blocks}) when is_list(blocks) do
    case Enum.find(blocks, &(&1["type"] == "tool_use" and &1["name"] == @tool_name)) do
      %{"input" => %{"corrected_nodes" => nodes, "points" => points}}
      when is_list(nodes) and is_number(points) ->
        {:ok, %{corrected_nodes: nodes, points: normalize_points(points)}}

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

  defp normalize_points(points) when is_float(points) do
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
