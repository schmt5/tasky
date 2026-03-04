# Webhook Debugging Guide

This guide helps you debug issues with the Tally webhook integration.

## Current Issue: Submissions Not Completing

If you're experiencing issues where form submissions don't mark tasks as completed, follow these steps:

## Step 1: Check Prerequisites

### Database Records
Ensure a `TaskSubmission` record exists BEFORE the student submits the form:

```sql
-- Check if submission exists
SELECT id, student_id, task_id, status, tally_response_id 
FROM task_submissions 
WHERE student_id = YOUR_USER_ID AND task_id = YOUR_TASK_ID;
```

The submission must exist with status "draft", "open", or "in_progress" before Tally sends the webhook.

### Task Configuration
Ensure the task has a `tally_form_id` set:

```sql
SELECT id, name, tally_form_id FROM tasks WHERE id = YOUR_TASK_ID;
```

### Webhook URL
Your Tally webhook should point to:
```
https://yourdomain.com/api/webhooks/tally
```

For local development with ngrok:
```
https://YOUR_NGROK_ID.ngrok.io/api/webhooks/tally
```

## Step 2: Enable Debug Logging

The webhook controller now includes extensive debug logging. Watch your Phoenix logs while submitting a form:

```bash
# In your Phoenix terminal
mix phx.server
```

You should see logs like:
```
[info] Received Tally webhook: %{...}
[debug] Extracting webhook data from fields: [...]
[debug] Found user_id=1, task_id=5
[debug] Looking for submission with student_id=1, task_id=5
[debug] Found submission with id=123, current status=draft
[debug] Marking submission 123 as completed with tally_response_id=abc123
[info] Successfully updated submission 123 to completed status
```

## Step 3: Test Webhook Locally

Use the provided test script to simulate a webhook:

```bash
# Edit the script to match your data
nano test_webhook.sh

# Update these variables:
USER_ID="1"      # Your student user ID
TASK_ID="5"      # Your task ID

# Make it executable and run
chmod +x test_webhook.sh
./test_webhook.sh
```

Expected response:
```json
{"status":"ok"}
```

## Step 4: Check Common Issues

### Issue: "Missing required fields"
**Cause**: Hidden fields `user_id` or `task_id` are not in the Tally form.

**Solution**: 
1. Edit your Tally form
2. Add hidden fields named exactly: `user_id` and `task_id`
3. These fields should be populated when generating the form URL

### Issue: "Submission not found"
**Cause**: No `TaskSubmission` record exists for this user/task combination.

**Solution**: Create the submission record before students can access the form:
```elixir
# In your task creation/enrollment logic
Tasks.create_submission(%{
  student_id: student.id,
  task_id: task.id
})
```

### Issue: `:econnaborted` error
**Cause**: Webhook response is timing out.

**Solution**: 
- Webhook now responds immediately and broadcasts asynchronously
- Check if database queries are slow
- Ensure Postgres is running properly

### Issue: Webhook receives data but status doesn't update
**Cause**: The changeset or database update is failing silently.

**Solution**: Check logs for changeset errors:
```
[error] Failed to update submission: [field: {"error message", [...]}]
```

## Step 5: Verify Form Configuration

### Hidden Fields in Tally
Your Tally form MUST have these hidden fields:

1. **user_id** - Student's database ID
2. **task_id** - Task's database ID
3. **user_name** (optional) - Student's name for display

### Generate Form URL
When linking students to the form, include the hidden field values:

```elixir
# Example in your LiveView
def render(assigns) do
  ~H"""
  <a href={"https://tally.so/r/#{@task.tally_form_id}?user_id=#{@current_user.id}&task_id=#{@task.id}&user_name=#{@current_user.firstname}"}>
    Submit Task
  </a>
  """
end
```

## Step 6: Monitor Real-Time Updates

### Check PubSub Broadcasting
After a successful webhook, broadcasts are sent to:

1. **Student topic**: `"student:#{user_id}:submissions"`
2. **Course topic**: `"course:#{course_id}:progress"`

Check if LiveViews are subscribed:
```elixir
# In your LiveView mount/3
Phoenix.PubSub.subscribe(Tasky.PubSub, "student:#{user_id}:submissions")
```

### Verify Handle Info
Ensure your LiveView handles the update:
```elixir
def handle_info({:submission_updated, updated_submission}, socket) do
  # Rebuild progress map
  progress_map = build_progress_map(socket.assigns.task.id, socket.assigns.students)
  {:noreply, assign(socket, :progress_map, progress_map)}
end
```

## Step 7: Manual Testing

### Test the Full Flow

1. **Create a test submission**:
```elixir
# In IEx console (iex -S mix phx.server)
alias Tasky.{Repo, Tasks}
alias Tasky.Tasks.TaskSubmission

changeset = TaskSubmission.create_changeset(%TaskSubmission{}, %{
  student_id: 1,  # Replace with your student ID
  task_id: 5      # Replace with your task ID
})

{:ok, submission} = Repo.insert(changeset)
```

2. **Submit the Tally form** with the correct hidden fields

3. **Check the database**:
```elixir
submission = Repo.get(TaskSubmission, submission.id)
submission.status  # Should be "completed"
submission.tally_response_id  # Should have the response ID
```

4. **View in UI**: Navigate to the progress page and click "Anzeigen"

## Expected Webhook Payload

Tally sends this structure:
```json
{
  "eventId": "evt_123",
  "eventType": "FORM_RESPONSE",
  "createdAt": "2026-03-04T12:00:00.000Z",
  "data": {
    "responseId": "WOvKy4v",
    "submissionId": "WOvKy4v",
    "respondentId": "QK0LRbG",
    "formId": "ODzq8K",
    "formName": "My Form",
    "createdAt": "2026-03-04T12:00:00.000Z",
    "fields": [
      {
        "key": "question_jBz7L4",
        "label": "user_id",
        "type": "HIDDEN_FIELDS",
        "value": "1"
      },
      {
        "key": "question_24oJL9",
        "label": "task_id",
        "type": "HIDDEN_FIELDS",
        "value": "5"
      },
      {
        "key": "question_GrDZAQ",
        "label": "submission_file",
        "type": "FILE_UPLOAD",
        "value": [...]
      }
    ]
  }
}
```

## Troubleshooting Checklist

- [ ] TaskSubmission record exists before form submission
- [ ] Task has `tally_form_id` set
- [ ] Tally form has `user_id` and `task_id` hidden fields
- [ ] Webhook URL is correctly configured in Tally
- [ ] Form URL includes hidden field values in query params
- [ ] Phoenix server logs show webhook received
- [ ] No errors in changeset validation
- [ ] Database update succeeds
- [ ] LiveView is subscribed to PubSub topic
- [ ] Progress page refreshes after submission

## Getting Help

If you're still experiencing issues:

1. Copy the full webhook log output
2. Check the database state before and after submission
3. Verify the Tally webhook payload structure
4. Test with the provided `test_webhook.sh` script first

## Recent Changes

**Performance Optimization**: The webhook now responds immediately and broadcasts updates asynchronously. This prevents timeout issues where Tally might close the connection before receiving a response.