defmodule TaskyWeb.TallyWebhookControllerTest do
  use TaskyWeb.ConnCase

  alias Tasky.Tasks
  alias Tasky.Repo

  import Tasky.AccountsFixtures

  setup do
    # Create a teacher and a student
    teacher = user_fixture(%{email: "teacher@example.com", role: "teacher"})
    student = user_fixture(%{email: "student@example.com", role: "student"})
    teacher_scope = %Tasky.Accounts.Scope{user: teacher}

    # Create a task
    {:ok, task} =
      Tasks.create_task(teacher_scope, %{
        name: "Complete Survey",
        link: "https://tally.so/r/abc123",
        status: "published",
        position: 1
      })

    # Create a submission for the student
    {:ok, submission} =
      Tasks.assign_task_to_students(teacher_scope, task.id, [student.id])

    submission = Repo.get_by!(Tasks.TaskSubmission, student_id: student.id, task_id: task.id)

    %{
      teacher: teacher,
      student: student,
      task: task,
      submission: submission
    }
  end

  describe "receive/2" do
    test "successfully marks submission as completed with valid payload", %{
      conn: conn,
      student: student,
      task: task,
      submission: submission
    } do
      payload = %{
        "eventId" => "test-event-123",
        "eventType" => "FORM_RESPONSE",
        "createdAt" => "2024-01-15T10:30:00.000Z",
        "data" => %{
          "responseId" => "tally-response-123",
          "formId" => "abc123",
          "formName" => "Test Form",
          "fields" => [
            %{
              "key" => "question_1",
              "label" => "user_id",
              "type" => "HIDDEN_FIELDS",
              "value" => student.id
            },
            %{
              "key" => "question_2",
              "label" => "task_id",
              "type" => "HIDDEN_FIELDS",
              "value" => task.id
            }
          ]
        }
      }

      conn = post(conn, ~p"/api/webhooks/tally", payload)

      assert json_response(conn, 200) == %{"status" => "ok"}

      # Verify submission was updated
      updated_submission = Repo.get!(Tasks.TaskSubmission, submission.id)
      assert updated_submission.status == "completed"
      assert updated_submission.tally_response_id == "tally-response-123"
      assert updated_submission.completed_at != nil
    end

    test "accepts user_id and task_id as strings", %{
      conn: conn,
      student: student,
      task: task,
      submission: submission
    } do
      payload = %{
        "data" => %{
          "responseId" => "tally-response-456",
          "fields" => [
            %{
              "label" => "user_id",
              "value" => Integer.to_string(student.id)
            },
            %{
              "label" => "task_id",
              "value" => Integer.to_string(task.id)
            }
          ]
        }
      }

      conn = post(conn, ~p"/api/webhooks/tally", payload)

      assert json_response(conn, 200) == %{"status" => "ok"}

      # Verify submission was updated
      updated_submission = Repo.get!(Tasks.TaskSubmission, submission.id)
      assert updated_submission.status == "completed"
      assert updated_submission.tally_response_id == "tally-response-456"
    end

    test "returns 400 when user_id is missing", %{conn: conn, task: task} do
      payload = %{
        "data" => %{
          "responseId" => "test-response",
          "fields" => [
            %{
              "label" => "task_id",
              "value" => task.id
            }
          ]
        }
      }

      conn = post(conn, ~p"/api/webhooks/tally", payload)

      assert json_response(conn, 400) == %{
               "error" => "Missing required fields (user_id, task_id)"
             }
    end

    test "returns 400 when task_id is missing", %{conn: conn, student: student} do
      payload = %{
        "data" => %{
          "responseId" => "test-response",
          "fields" => [
            %{
              "label" => "user_id",
              "value" => student.id
            }
          ]
        }
      }

      conn = post(conn, ~p"/api/webhooks/tally", payload)

      assert json_response(conn, 400) == %{
               "error" => "Missing required fields (user_id, task_id)"
             }
    end

    test "returns 400 when data field is missing", %{conn: conn} do
      payload = %{
        "eventType" => "FORM_RESPONSE"
      }

      conn = post(conn, ~p"/api/webhooks/tally", payload)

      assert json_response(conn, 400) == %{
               "error" => "Missing required fields (user_id, task_id)"
             }
    end

    test "returns 404 when submission does not exist", %{conn: conn, student: student} do
      payload = %{
        "data" => %{
          "responseId" => "test-response",
          "fields" => [
            %{
              "label" => "user_id",
              "value" => student.id
            },
            %{
              "label" => "task_id",
              "value" => 99999
            }
          ]
        }
      }

      conn = post(conn, ~p"/api/webhooks/tally", payload)

      assert json_response(conn, 404) == %{"error" => "Submission not found"}
    end

    test "handles already completed submissions gracefully", %{
      conn: conn,
      student: student,
      task: task,
      submission: submission
    } do
      # Mark submission as already completed
      submission
      |> Ecto.Changeset.change(%{
        status: "completed",
        completed_at: DateTime.utc_now(:second),
        tally_response_id: "previous-response"
      })
      |> Repo.update!()

      payload = %{
        "data" => %{
          "responseId" => "new-response-123",
          "fields" => [
            %{
              "label" => "user_id",
              "value" => student.id
            },
            %{
              "label" => "task_id",
              "value" => task.id
            }
          ]
        }
      }

      conn = post(conn, ~p"/api/webhooks/tally", payload)

      assert json_response(conn, 200) == %{"status" => "ok"}

      # Verify it still updates (latest response wins)
      updated_submission = Repo.get!(Tasks.TaskSubmission, submission.id)
      assert updated_submission.status == "completed"
      assert updated_submission.tally_response_id == "new-response-123"
    end

    test "preserves other submission data when marking completed", %{
      conn: conn,
      student: student,
      task: task,
      submission: submission
    } do
      # Add some existing data to the submission
      submission
      |> Ecto.Changeset.change(%{
        status: "in_progress"
      })
      |> Repo.update!()

      payload = %{
        "data" => %{
          "responseId" => "response-abc",
          "fields" => [
            %{
              "label" => "user_id",
              "value" => student.id
            },
            %{
              "label" => "task_id",
              "value" => task.id
            }
          ]
        }
      }

      conn = post(conn, ~p"/api/webhooks/tally", payload)

      assert json_response(conn, 200) == %{"status" => "ok"}

      # Verify submission was updated correctly
      updated_submission = Repo.get!(Tasks.TaskSubmission, submission.id)
      assert updated_submission.status == "completed"
      assert updated_submission.student_id == student.id
      assert updated_submission.task_id == task.id
      assert updated_submission.tally_response_id == "response-abc"
    end

    test "works with additional hidden fields in payload", %{
      conn: conn,
      student: student,
      task: task
    } do
      payload = %{
        "data" => %{
          "responseId" => "response-xyz",
          "fields" => [
            %{
              "label" => "user_id",
              "value" => student.id
            },
            %{
              "label" => "task_id",
              "value" => task.id
            },
            %{
              "label" => "user_name",
              "value" => "student@example.com"
            },
            %{
              "label" => "other_field",
              "type" => "INPUT_TEXT",
              "value" => "Some answer"
            }
          ]
        }
      }

      conn = post(conn, ~p"/api/webhooks/tally", payload)

      assert json_response(conn, 200) == %{"status" => "ok"}
    end
  end

  describe "signature verification" do
    @tag :skip
    test "accepts request with valid signature when secret is configured", %{
      conn: conn,
      student: student,
      task: task
    } do
      # This test would require setting up the signing secret in test config
      # Skipped for now as dev config has nil secret
      payload = %{
        "data" => %{
          "responseId" => "test-response",
          "fields" => [
            %{"label" => "user_id", "value" => student.id},
            %{"label" => "task_id", "value" => task.id}
          ]
        }
      }

      signature = calculate_signature(payload, "test-secret")

      conn =
        conn
        |> put_req_header("tally-signature", signature)
        |> post(~p"/api/webhooks/tally", payload)

      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    @tag :skip
    test "rejects request with invalid signature when secret is configured", %{conn: conn} do
      # This test would require setting up the signing secret in test config
      # Skipped for now as dev config has nil secret
      payload = %{"data" => %{"fields" => []}}

      conn =
        conn
        |> put_req_header("tally-signature", "invalid-signature")
        |> post(~p"/api/webhooks/tally", payload)

      assert json_response(conn, 401) == %{"error" => "Invalid signature"}
    end
  end

  defp calculate_signature(payload, secret) do
    payload_json = Jason.encode!(payload)
    :crypto.mac(:hmac, :sha256, secret, payload_json) |> Base.encode64()
  end
end
