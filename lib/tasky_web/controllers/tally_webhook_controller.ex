defmodule TaskyWeb.TallyWebhookController do
  use TaskyWeb, :controller

  require Logger

  alias Tasky.Tasks
  alias Tasky.Repo

  @doc """
  Receives webhook POST requests from Tally when a student submits a form.

  Expected payload structure:
  {
    "eventId": "...",
    "eventType": "FORM_RESPONSE",
    "data": {
      "responseId": "2wgx4n",
      "fields": [
        {"key": "question_xxx", "label": "user_id", "type": "HIDDEN_FIELDS", "value": "1"},
        {"key": "question_yyy", "label": "task_id", "type": "HIDDEN_FIELDS", "value": "5"},
        ...
      ]
    }
  }
  """
  def receive(conn, %{"eventType" => "FORM_RESPONSE"} = params) do
    Logger.info("Received Tally webhook")

    # Verify signature if configured
    case verify_signature(conn, params) do
      :ok ->
        process_webhook(conn, params)

      {:error, reason} ->
        Logger.error("Webhook signature verification failed: #{reason}")

        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid signature"})
    end
  end

  def receive(conn, %{"eventType" => event_type}) do
    Logger.info("Ignoring Tally webhook event type: #{event_type}")
    json(conn, %{status: "ignored"})
  end

  def receive(conn, _params) do
    Logger.warning("Received Tally webhook with missing eventType")
    json(conn, %{status: "ignored"})
  end

  defp process_webhook(conn, params) do
    result =
      with {:ok, data} <- extract_webhook_data(params),
           :not_duplicate <- check_duplicate(data),
           {:ok, submission} <- find_submission(data),
           {:ok, updated_submission} <- mark_completed(submission, data) do
        Logger.info(
          "Successfully marked submission #{submission.id} as completed for student #{data.user_id}, task #{data.task_id}"
        )

        # Preload task to get course_id for broadcasts
        updated_submission = Repo.preload(updated_submission, :task)

        {:ok, updated_submission, data}
      else
        error -> error
      end

    case result do
      {:ok, updated_submission, data} ->
        # Send response first
        response = json(conn, %{status: "ok"})

        # Then broadcast updates asynchronously (don't block response)
        Task.start(fn ->
          Phoenix.PubSub.broadcast(
            Tasky.PubSub,
            "student:#{data.user_id}:submissions",
            {:submission_updated, updated_submission}
          )

          Phoenix.PubSub.broadcast(
            Tasky.PubSub,
            "course:#{updated_submission.task.course_id}:progress",
            {:submission_updated, updated_submission}
          )
        end)

        response

      {:error, :missing_fields} ->
        Logger.error("Missing required fields (user_id, task_id) in webhook payload")

        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing required fields (user_id, task_id)"})

      {:error, :duplicate_response} ->
        Logger.info("Duplicate Tally webhook response_id — ignoring")
        json(conn, %{status: "ok"})

      {:error, :submission_not_found} ->
        Logger.error("Submission not found in webhook processing")

        conn
        |> put_status(:not_found)
        |> json(%{error: "Submission not found"})

      {:error, changeset} ->
        Logger.error("Failed to update submission: #{inspect(changeset.errors)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to update submission"})

      error ->
        Logger.error("Unexpected error in webhook processing: #{inspect(error)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Internal server error"})
    end
  end

  defp verify_signature(conn, _params) do
    signing_secret = Application.get_env(:tasky, :tally_signing_secret)

    if is_nil(signing_secret) || signing_secret == "" do
      Logger.warning("Tally signing secret not configured - skipping signature verification")
      :ok
    else
      signature = get_req_header(conn, "tally-signature") |> List.first()

      if is_nil(signature) do
        {:error, "Missing Tally-Signature header"}
      else
        raw_body = conn.private[:raw_body] || ""
        calculated = :crypto.mac(:hmac, :sha256, signing_secret, raw_body) |> Base.encode64()

        if Plug.Crypto.secure_compare(calculated, signature) do
          :ok
        else
          {:error, "Signature mismatch"}
        end
      end
    end
  end

  defp check_duplicate(%{response_id: response_id}) do
    case Repo.get_by(Tasks.TaskSubmission, tally_response_id: response_id) do
      nil -> :not_duplicate
      _existing -> {:error, :duplicate_response}
    end
  end

  defp extract_webhook_data(%{"data" => %{"fields" => fields, "responseId" => response_id}}) do
    # Extract user_id and task_id from hidden fields
    user_id = find_field_value(fields, "user_id")
    task_id = find_field_value(fields, "task_id")

    with {:ok, uid} <- parse_int(user_id || ""),
         {:ok, tid} <- parse_int(task_id || "") do
      {:ok, %{user_id: uid, task_id: tid, response_id: response_id}}
    else
      _ -> {:error, :missing_fields}
    end
  end

  defp extract_webhook_data(_params) do
    {:error, :missing_fields}
  end

  defp find_field_value(fields, label) when is_list(fields) do
    Enum.find_value(fields, fn field ->
      case field do
        %{"label" => ^label, "value" => value} -> value
        _ -> nil
      end
    end)
  end

  defp find_field_value(_fields, _label), do: nil

  defp parse_int(value) when is_integer(value), do: {:ok, value}

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, :invalid_integer}
    end
  end

  defp find_submission(%{user_id: user_id, task_id: task_id}) do
    case Repo.get_by(Tasks.TaskSubmission, student_id: user_id, task_id: task_id) do
      nil ->
        {:error, :submission_not_found}

      submission ->
        {:ok, submission}
    end
  end

  defp mark_completed(submission, %{response_id: response_id}) do
    result =
      submission
      |> Ecto.Changeset.change(%{
        status: "completed",
        completed_at: DateTime.utc_now(:second),
        tally_response_id: response_id
      })
      |> Repo.update()

    case result do
      {:ok, updated} ->
        Logger.info("Successfully completed submission #{submission.id}")
        {:ok, updated}

      {:error, changeset} ->
        Logger.error("Failed to update submission: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end
end
