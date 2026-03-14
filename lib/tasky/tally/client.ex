defmodule Tasky.Tally.Client do
  @moduledoc """
  Client for interacting with the Tally.so API.

  Handles forms, webhooks, submissions, and response parsing.
  """

  require Logger

  @base_url "https://api.tally.so"

  @doc """
  Lists all forms from Tally.

  Returns `{:ok, forms}` on success or `{:error, reason}` on failure.
  """
  def list_forms(current_scope) do
    case make_request(current_scope, :get, "/forms") do
      {:ok, %{status: 200, body: %{"items" => forms}}} ->
        {:ok, forms}

      {:ok, %{status: 401}} ->
        Logger.error("Tally API: Unauthorized")
        {:error, :unauthorized}

      {:ok, %{status: status}} ->
        Logger.error("Tally API returned status code: #{status}")
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a single form by ID.

  Returns `{:ok, form}` on success or `{:error, reason}` on failure.
  """
  def get_form(current_scope, form_id) do
    case make_request(current_scope, :get, "/forms/#{form_id}") do
      {:ok, %{status: 200, body: form}} ->
        {:ok, form}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: status}} ->
        Logger.error("Tally API returned status code: #{status}")
        {:error, :api_error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches all submissions for a form.

  Returns `{:ok, %{"submissions" => [...], "questions" => [...]}}` on success.
  """
  def fetch_submissions(current_scope, form_id) do
    case make_request(current_scope, :get, "/forms/#{form_id}/submissions") do
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
  Fetches a single submission by form ID and submission ID.

  Returns `{:ok, %{"submission" => %{...}, "questions" => [...]}}` on success.
  """
  def fetch_submission(current_scope, form_id, submission_id) do
    case make_request(current_scope, :get, "/forms/#{form_id}/submissions/#{submission_id}") do
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
  Creates a webhook for a form.

  Returns `{:ok, webhook}` on success or `{:error, reason}` on failure.

  ## Options
    * `:signing_secret` - Optional secret used to sign webhook payloads
    * `:http_headers` - Optional custom HTTP headers (list of maps with "name" and "value" keys)
    * `:external_subscriber` - Optional identifier for the external subscriber
  """
  def create_webhook(current_scope, form_id, webhook_url, opts \\ []) do
    api_key = get_api_key(current_scope)

    if is_nil(api_key) || api_key == "" do
      {:error, :api_key_not_configured}
    else
      body =
        %{
          "formId" => form_id,
          "url" => webhook_url,
          "eventTypes" => ["FORM_RESPONSE"]
        }
        |> maybe_put("signingSecret", Keyword.get(opts, :signing_secret))
        |> maybe_put("httpHeaders", Keyword.get(opts, :http_headers))
        |> maybe_put("externalSubscriber", Keyword.get(opts, :external_subscriber))

      case Req.post("#{@base_url}/webhooks", auth: {:bearer, api_key}, json: body) do
        {:ok, %Req.Response{status: 201, body: webhook}} ->
          {:ok, webhook}

        {:ok, %Req.Response{status: 401}} ->
          Logger.error("Tally API: Unauthorized")
          {:error, :unauthorized}

        {:ok, %Req.Response{status: 400, body: error_body}} ->
          Logger.error("Tally API: Bad request - #{inspect(error_body)}")
          {:error, :bad_request}

        {:ok, %Req.Response{status: status, body: resp_body}} ->
          Logger.error("Tally API returned status code: #{status}, body: #{inspect(resp_body)}")
          {:error, :api_error}

        {:error, exception} ->
          Logger.error("Failed to connect to Tally API: #{inspect(exception)}")
          {:error, :connection_error}
      end
    end
  end

  @doc """
  Builds the public form URL for a given form ID.
  """
  def form_url(form_id) do
    "https://tally.so/r/#{form_id}"
  end

  @doc """
  Fetches a form and returns its structured content blocks.

  Returns `{:ok, %{title: string, blocks: [block]}}` where each block is a map
  with `:type`, and type-specific fields:
    - `%{type: :heading2, text: string, id: string}`
    - `%{type: :heading3, text: string, id: string}`
    - `%{type: :text, html: string}`
    - `%{type: :image, url: string, alt: string, caption: string}`
    - `%{type: :video, url: string, provider: string}`
    - `%{type: :divider}`
    - `%{type: :page_break}`
  """
  def fetch_form_content(current_scope, form_id) do
    case get_form(current_scope, form_id) do
      {:ok, form} ->
        blocks = Map.get(form, "blocks", [])
        title = extract_form_title(blocks)
        content_blocks = blocks |> Enum.map(&parse_block/1) |> Enum.reject(&is_nil/1)
        {:ok, %{title: title, blocks: content_blocks}}

      {:error, reason} ->
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
  Extracts the submission metadata (id, submitted_at, is_completed, created_at).
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

  Returns a list of maps with question_id, question_title, question_type, and answer.
  Hidden field questions are excluded.
  """
  def extract_all_responses(%{
        "submission" => %{"responses" => responses},
        "questions" => questions
      }) do
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

  # Private helpers

  defp extract_form_title(blocks) do
    title_block = Enum.find(blocks, fn b -> b["type"] == "FORM_TITLE" end)

    case title_block do
      %{"payload" => %{"html" => html}} when is_binary(html) and html != "" ->
        strip_html(html)

      _ ->
        nil
    end
  end

  defp parse_block(%{"type" => "HEADING_2", "uuid" => id, "payload" => %{"html" => html}})
       when is_binary(html) and html != "" do
    %{type: :heading2, text: strip_html(html), id: id}
  end

  defp parse_block(%{"type" => "HEADING_2", "uuid" => id, "payload" => payload}) do
    text = extract_safe_html_text(payload)
    if text != "", do: %{type: :heading2, text: text, id: id}, else: nil
  end

  defp parse_block(%{"type" => "HEADING_3", "uuid" => id, "payload" => %{"html" => html}})
       when is_binary(html) and html != "" do
    %{type: :heading3, text: strip_html(html), id: id}
  end

  defp parse_block(%{"type" => "HEADING_3", "uuid" => id, "payload" => payload}) do
    text = extract_safe_html_text(payload)
    if text != "", do: %{type: :heading3, text: text, id: id}, else: nil
  end

  defp parse_block(%{"type" => "TEXT", "payload" => %{"html" => html}}) when html != "" do
    %{type: :text, html: html}
  end

  defp parse_block(%{"type" => "TEXT", "payload" => payload}) do
    html = safe_html_schema_to_html(payload)
    if html != "", do: %{type: :text, html: html}, else: nil
  end

  defp parse_block(%{"type" => type, "payload" => %{"html" => html}})
       when type in ["LABEL", "TITLE", "HEADING_1"] and is_binary(html) and html != "" do
    %{type: :text, html: html}
  end

  defp parse_block(%{"type" => type, "payload" => payload})
       when type in ["LABEL", "TITLE", "HEADING_1"] do
    html = safe_html_schema_to_html(payload)
    if html != "", do: %{type: :text, html: html}, else: nil
  end

  defp parse_block(%{"type" => "CHECKBOX", "payload" => %{"text" => text}})
       when is_binary(text) and text != "" do
    %{type: :checkbox, text: text}
  end

  defp parse_block(%{"type" => "IMAGE", "payload" => %{"images" => [first | _]} = payload}) do
    %{
      type: :image,
      url: first["url"],
      alt: Map.get(payload, "altText", ""),
      caption: Map.get(payload, "caption", "")
    }
  end

  defp parse_block(%{"type" => "EMBED_VIDEO", "payload" => payload}) do
    raw_url = Map.get(payload, "inputUrl") || Map.get(payload, "url", "")
    provider = Map.get(payload, "provider", "")

    watch_url = to_watch_url(raw_url, provider)

    %{
      type: :video,
      url: watch_url,
      provider: provider
    }
  end

  defp parse_block(%{"type" => "DIVIDER"}) do
    %{type: :divider}
  end

  defp parse_block(%{"type" => "PAGE_BREAK"}) do
    %{type: :page_break}
  end

  defp parse_block(_), do: nil

  # inputUrl contains the original user-pasted URL (e.g. https://youtu.be/VIDEO_ID)
  # which is already a valid watchable link — no conversion needed.
  defp to_watch_url(url, _provider), do: url

  # Converts a safeHTMLSchema array to a plain-text string.
  # Each segment is either ["text"] or ["text", [["tag", "p"], ...]].
  # Empty segments and newline-only segments are skipped.
  defp extract_safe_html_text(payload) do
    payload
    |> Map.get("safeHTMLSchema", [])
    |> Enum.map(fn
      [text | _] when is_binary(text) -> String.trim(text)
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  # Converts a safeHTMLSchema array to an HTML string for rendering.
  # Segments tagged with "p" become <p> elements; plain segments are joined inline.
  defp safe_html_schema_to_html(payload) do
    segments = Map.get(payload, "safeHTMLSchema", [])

    if segments == [] do
      ""
    else
      segments
      |> Enum.map(fn
        [text, tags] when is_binary(text) and is_list(tags) ->
          tag_names = Enum.map(tags, fn [tag | _] -> tag end)

          if "p" in tag_names do
            "<p>#{escape_html(text)}</p>"
          else
            escape_html(text)
          end

        [text] when is_binary(text) and text != "\n" ->
          escape_html(text)

        _ ->
          ""
      end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("")
    end
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp strip_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&nbsp;", " ")
    |> String.trim()
  end

  defp strip_html(_), do: ""

  defp make_request(current_scope, method, path) do
    api_key = get_api_key(current_scope)

    if is_nil(api_key) || api_key == "" do
      Logger.error("Tally API key not configured")
      {:error, :api_key_not_configured}
    else
      apply(Req, method, ["#{@base_url}#{path}", [auth: {:bearer, api_key}]])
    end
  end

  defp get_question_title(%{"title" => title}) when is_binary(title) and title != "", do: title

  defp get_question_title(%{"fields" => fields}) when is_list(fields) do
    case List.first(fields) do
      %{"title" => title} when is_binary(title) -> title
      _ -> "Question"
    end
  end

  defp get_question_title(_), do: "Question"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp get_api_key(%{user: %{tally_api_key: api_key}}) when is_binary(api_key), do: api_key
  defp get_api_key(_), do: nil
end
