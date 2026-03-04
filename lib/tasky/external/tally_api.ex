defmodule Tasky.External.TallyApi do
  @moduledoc """
  Client for interacting with the Tally.so API.

  Handles fetching form submissions and their details.
  """

  require Logger

  @base_url "https://api.tally.so"

  @doc """
  Fetches a single submission by form ID and submission ID.

  ## Examples

      iex> TallyApi.fetch_submission(current_scope, "ODzq8K", "WOvKy4v")
      {:ok, %{
        "submission" => %{
          "id" => "WOvKy4v",
          "submittedAt" => "2026-03-04T02:52:26.000Z",
          "responses" => [...]
        },
        "questions" => [...]
      }}

      iex> TallyApi.fetch_submission(current_scope, "invalid", "invalid")
      {:error, :not_found}
  """
  def fetch_submission(current_scope, form_id, submission_id) do
    url = "#{@base_url}/forms/#{form_id}/submissions/#{submission_id}"

    case make_request(current_scope, url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: status}} ->
        Logger.error("Tally API returned unexpected status: #{status}")
        {:error, :unexpected_response}

      {:error, reason} ->
        Logger.error("Failed to fetch Tally submission: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Fetches all submissions for a form.

  ## Examples

      iex> TallyApi.fetch_submissions(current_scope, "ODzq8K")
      {:ok, %{
        "submissions" => [...],
        "questions" => [...]
      }}
  """
  def fetch_submissions(current_scope, form_id) do
    url = "#{@base_url}/forms/#{form_id}/submissions"

    case make_request(current_scope, url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: status}} ->
        Logger.error("Tally API returned unexpected status: #{status}")
        {:error, :unexpected_response}

      {:error, reason} ->
        Logger.error("Failed to fetch Tally submissions: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Extracts file uploads from a submission response.

  Returns a list of file upload objects with name, url, mimeType, and size.
  """
  def extract_file_uploads(%{
        "submission" => %{"responses" => responses},
        "questions" => questions
      }) do
    file_question_ids =
      questions
      |> Enum.filter(fn q -> q["type"] == "FILE_UPLOAD" end)
      |> Enum.map(fn q -> q["id"] end)

    responses
    |> Enum.filter(fn response -> response["questionId"] in file_question_ids end)
    |> Enum.flat_map(fn response ->
      case response["answer"] do
        files when is_list(files) -> files
        _ -> []
      end
    end)
  end

  def extract_file_uploads(_), do: []

  @doc """
  Extracts the submission metadata (date, completion status, etc.)
  """
  def extract_metadata(%{"submission" => submission}) do
    %{
      id: submission["id"],
      submitted_at: submission["submittedAt"],
      is_completed: submission["isCompleted"],
      created_at: submission["createdAt"]
    }
  end

  def extract_metadata(_), do: nil

  @doc """
  Extracts all responses from a submission, grouped by question.

  Returns a list of maps with question title, type, and answer.
  """
  def extract_all_responses(%{
        "submission" => %{"responses" => responses},
        "questions" => questions
      }) do
    # Create a map of question IDs to question details
    question_map =
      questions
      |> Enum.map(fn q -> {q["id"], q} end)
      |> Map.new()

    responses
    |> Enum.map(fn response ->
      question = Map.get(question_map, response["questionId"])

      if question do
        %{
          question_id: response["questionId"],
          question_title: get_question_title(question),
          question_type: question["type"],
          answer: response["answer"]
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(fn r -> r.question_type == "HIDDEN_FIELDS" end)
  end

  def extract_all_responses(_), do: []

  # Private Functions

  defp get_question_title(%{"title" => title}) when is_binary(title) and title != "", do: title

  defp get_question_title(%{"fields" => fields}) when is_list(fields) do
    case List.first(fields) do
      %{"title" => title} when is_binary(title) -> title
      _ -> "Question"
    end
  end

  defp get_question_title(_), do: "Question"

  defp make_request(current_scope, url) do
    api_key = get_api_key(current_scope)

    if is_nil(api_key) || api_key == "" do
      Logger.error("Tally API key not configured")
      {:error, :api_key_not_configured}
    else
      Req.get(url,
        headers: [
          {"Authorization", "Bearer #{api_key}"},
          {"Content-Type", "application/json"}
        ]
      )
    end
  end

  defp get_api_key(current_scope) do
    case current_scope do
      %{user: %{tally_api_key: api_key}} when is_binary(api_key) -> api_key
      _ -> nil
    end
  end
end
