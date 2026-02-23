# Tally.so Webhook Integration

This document explains how to integrate Tally.so forms with the Tasky application to automatically mark student tasks as completed when they submit forms.

## Overview

When a student clicks on a task link in their "My Tasks" page, they are directed to a Tally form. Upon submission, Tally sends a webhook to our application, which automatically marks the task as completed.

## How It Works

```
1. Student clicks task link → Opens Tally form with URL parameters
2. URL parameters are captured as hidden fields (user_id, task_id, user_name)
3. Student completes and submits the form
4. Tally sends webhook POST to: /api/webhooks/tally
5. Webhook controller processes the submission
6. Task is marked as completed in database
7. Student sees updated status on their dashboard
```

## Setting Up Tally Forms

### Step 1: Create Your Form

1. Go to [tally.so](https://tally.so) and create a new form
2. Add your questions/content as needed
3. **Important**: Add these **Hidden Fields** to capture student information:
   - Field label: `user_id`
   - Field label: `task_id`
   - Field label: `user_name` (optional, for identification)

These hidden fields will automatically capture values from URL parameters.

### Step 2: Configure the Webhook

1. Publish your form
2. Go to **Integrations** → **Webhooks**
3. Click **Connect**
4. Set the endpoint URL to:
   ```
   https://yourdomain.com/api/webhooks/tally
   ```
   
   For local development with ngrok:
   ```
   https://your-ngrok-url.ngrok.io/api/webhooks/tally
   ```

5. **(Optional but recommended)** Add a **Signing Secret**:
   - Generate a secure random string
   - Add it to your Tally webhook configuration
   - Add it to your application config (see Security section below)

6. **(Optional)** Add custom HTTP headers if needed

7. Click **Save**

### Step 3: Copy the Form URL

After creating your form, copy the form URL. It will look like:
```
https://tally.so/r/abc123
```

### Step 4: Create Task in Tasky

1. Log in as a teacher/admin
2. Go to **Tasks** → **New Task**
3. Enter task name and details
4. In the **Link** field, paste your Tally form URL:
   ```
   https://tally.so/r/abc123
   ```
5. Save the task
6. Assign it to students

## How Students Use It

1. Student logs in and goes to **My Tasks**
2. Clicks on a task card with a Tally link
3. The link automatically includes URL parameters:
   ```
   https://tally.so/r/abc123?user_id=5&task_id=10&user_name=student@example.com
   ```
4. Student completes the form and submits
5. Task is automatically marked as "completed" ✅
6. Teacher can review and grade the submission

## Technical Details

### Database Schema

The `task_submissions` table includes:
- `tally_response_id` - Stores the Tally response ID for reference
- `status` - Updated to "completed" when webhook is received
- `completed_at` - Timestamp when the form was submitted

### Webhook Endpoint

**URL**: `POST /api/webhooks/tally`

**Expected Payload**:
```json
{
  "eventId": "unique-event-id",
  "eventType": "FORM_RESPONSE",
  "createdAt": "2024-01-15T10:30:00.000Z",
  "data": {
    "responseId": "abc123",
    "submissionId": "abc123",
    "formId": "xyz789",
    "formName": "Task Form",
    "fields": [
      {
        "key": "question_xxx",
        "label": "user_id",
        "type": "HIDDEN_FIELDS",
        "value": "5"
      },
      {
        "key": "question_yyy",
        "label": "task_id",
        "type": "HIDDEN_FIELDS",
        "value": "10"
      },
      {
        "key": "question_zzz",
        "label": "user_name",
        "type": "HIDDEN_FIELDS",
        "value": "student@example.com"
      }
    ]
  }
}
```

**Response**:
- `200 OK` - Submission processed successfully
- `400 Bad Request` - Missing required fields (user_id or task_id)
- `401 Unauthorized` - Invalid signature (if signing secret is configured)
- `404 Not Found` - Submission not found
- `422 Unprocessable Entity` - Failed to update submission

### Security

#### Signature Verification

To verify that webhooks are actually coming from Tally:

1. Set a signing secret in your Tally webhook configuration
2. Add the secret to your application config:

**Development** (`config/dev.exs`):
```elixir
config :tasky, :tally_signing_secret, nil  # Skip verification in dev
```

**Production** (`config/runtime.exs`):
```elixir
config :tasky, :tally_signing_secret, System.get_env("TALLY_SIGNING_SECRET")
```

3. Set the environment variable in production:
```bash
export TALLY_SIGNING_SECRET="your-secure-secret-here"
```

The webhook controller automatically verifies signatures using SHA256 HMAC when a signing secret is configured.

### Retry Mechanism

Tally automatically retries failed webhook deliveries:
- 1st retry: after 5 minutes
- 2nd retry: after 30 minutes
- 3rd retry: after 1 hour
- 4th retry: after 6 hours
- 5th retry: after 1 day

Your endpoint must respond within **10 seconds** with a 2XX status code.

## Testing

### Local Development with ngrok

1. Install [ngrok](https://ngrok.com/)
2. Start your Phoenix server:
   ```bash
   mix phx.server
   ```
3. In another terminal, start ngrok:
   ```bash
   ngrok http 4000
   ```
4. Copy the ngrok URL (e.g., `https://abc123.ngrok.io`)
5. Use this URL in your Tally webhook configuration:
   ```
   https://abc123.ngrok.io/api/webhooks/tally
   ```

### Manual Testing

You can test the webhook endpoint manually using curl:

```bash
curl -X POST http://localhost:4000/api/webhooks/tally \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "FORM_RESPONSE",
    "data": {
      "responseId": "test123",
      "fields": [
        {
          "label": "user_id",
          "value": "1"
        },
        {
          "label": "task_id",
          "value": "1"
        }
      ]
    }
  }'
```

### Viewing Webhook Logs

Check your application logs to see webhook requests:

```bash
# Development
tail -f _build/dev/lib/tasky/consolidated/Elixir.Logger.beam

# Or just watch your terminal where mix phx.server is running
```

You'll see logs like:
```
[info] Received Tally webhook: %{...}
[info] Successfully marked submission 5 as completed for student 3, task 10
```

### Debugging in Tally

1. Go to your form's Integrations page
2. Click the 🕔 (clock) icon next to your webhook
3. View the **Events Log** to see:
   - Request payload
   - Response status
   - Response time
   - Error messages (if any)

## Troubleshooting

### Webhook Not Firing

- ✅ Check that the form is **published** (not in draft mode)
- ✅ Verify the webhook URL is correct
- ✅ Check that the webhook is **enabled** (toggle is on)
- ✅ Ensure your server is publicly accessible (use ngrok for local dev)

### "Submission Not Found" Error

- ✅ Verify the task has been assigned to the student
- ✅ Check that `user_id` and `task_id` are being passed correctly
- ✅ Ensure hidden fields in Tally match: `user_id`, `task_id`

### "Invalid Signature" Error

- ✅ Verify the signing secret matches in both Tally and your config
- ✅ Check that the secret doesn't have extra whitespace
- ✅ For local dev, set `tally_signing_secret` to `nil` to skip verification

### Submission Already Completed

The webhook will attempt to update even if already completed. This is safe but won't change the status. Check your logs to confirm.

### 10-Second Timeout

If your webhook processing takes longer than 10 seconds:
- ✅ Optimize database queries
- ✅ Move heavy processing to background jobs
- ✅ Ensure your database isn't overloaded

## Best Practices

1. **Always use HTTPS in production** for webhook endpoints
2. **Enable signature verification** with a strong signing secret
3. **Monitor webhook logs** in Tally's dashboard
4. **Handle duplicate webhooks** gracefully (Tally may retry)
5. **Return 200 OK quickly** (within 10 seconds)
6. **Test with ngrok** before deploying to production
7. **Use environment variables** for secrets, never hardcode them

## Example Task Creation Flow

```
Teacher:
1. Creates form in Tally with hidden fields: user_id, task_id
2. Configures webhook to point to: https://yourdomain.com/api/webhooks/tally
3. Creates task in Tasky with Tally form URL
4. Assigns task to students

Student:
1. Clicks task link in "My Tasks"
2. Sees link like: https://tally.so/r/abc123?user_id=5&task_id=10
3. Completes form and submits
4. Tally sends webhook to Tasky
5. Task automatically marked as "completed"
6. Can see completion on dashboard immediately
```

## Additional Resources

- [Tally Webhook Documentation](https://tally.so/help/webhooks)
- [Tally Hidden Fields](https://tally.so/help/hidden-fields)
- [ngrok Documentation](https://ngrok.com/docs)
- [Phoenix Controllers Guide](https://hexdocs.pm/phoenix/controllers.html)

## Support

If you encounter issues:
1. Check the logs in your Phoenix application
2. Check the webhook event logs in Tally
3. Verify all configuration settings
4. Test with the manual curl command above
5. Ensure the submission exists in the database before testing

---

**Last Updated**: 2024
**Version**: 1.0