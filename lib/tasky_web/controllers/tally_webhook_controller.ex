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
  def receive(conn, params) do
    Logger.info("Received Tally webhook: #{inspect(params)}")

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

  defp process_webhook(conn, params) do
    with {:ok, data} <- extract_webhook_data(params),
         {:ok, submission} <- find_submission(data),
         {:ok, _updated_submission} <- mark_completed(submission, data) do
      Logger.info(
        "Successfully marked submission #{submission.id} as completed for student #{data.user_id}, task #{data.task_id}"
      )

      json(conn, %{status: "ok"})
    else
      {:error, :missing_fields} ->
        Logger.error("Missing required fields in webhook payload")

        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing required fields (user_id, task_id)"})

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
    end
  end

  defp verify_signature(conn, params) do
    # Get the signing secret from config
    signing_secret = Application.get_env(:tasky, :tally_signing_secret)

    # If no signing secret is configured, skip verification (dev mode)
    if is_nil(signing_secret) || signing_secret == "" do
      Logger.warning("Tally signing secret not configured - skipping signature verification")
      :ok
    else
      # Get the signature from headers
      signature = get_req_header(conn, "tally-signature") |> List.first()

      if is_nil(signature) do
        {:error, "Missing Tally-Signature header"}
      else
        # Calculate the expected signature
        payload = Jason.encode!(params)
        calculated = :crypto.mac(:hmac, :sha256, signing_secret, payload) |> Base.encode64()

        if signature == calculated do
          :ok
        else
          {:error, "Signature mismatch"}
        end
      end
    end
  end

  defp extract_webhook_data(%{"data" => %{"fields" => fields, "responseId" => response_id}}) do
    # Extract user_id and task_id from hidden fields
    user_id = find_field_value(fields, "user_id")
    task_id = find_field_value(fields, "task_id")

    if user_id && task_id do
      {:ok,
       %{
         user_id: parse_int(user_id),
         task_id: parse_int(task_id),
         response_id: response_id
       }}
    else
      {:error, :missing_fields}
    end
  end

  defp extract_webhook_data(_params), do: {:error, :missing_fields}

  defp find_field_value(fields, label) when is_list(fields) do
    Enum.find_value(fields, fn field ->
      case field do
        %{"label" => ^label, "value" => value} -> value
        _ -> nil
      end
    end)
  end

  defp find_field_value(_fields, _label), do: nil

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(value) when is_binary(value), do: String.to_integer(value)

  defp find_submission(%{user_id: user_id, task_id: task_id}) do
    case Repo.get_by(Tasks.TaskSubmission, student_id: user_id, task_id: task_id) do
      nil -> {:error, :submission_not_found}
      submission -> {:ok, submission}
    end
  end

  defp mark_completed(submission, %{response_id: response_id}) do
    submission
    |> Ecto.Changeset.change(%{
      status: "completed",
      completed_at: DateTime.utc_now(:second),
      tally_response_id: response_id
    })
    |> Repo.update()
  end
end
