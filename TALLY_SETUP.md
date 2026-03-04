# Tally Integration Setup

This document explains how to set up the Tally integration for viewing student submissions.

## Overview

The application integrates with Tally.so to:
1. Receive webhook notifications when students submit forms
2. Fetch and display submission details (files, responses) to teachers

## Configuration

### 1. Get Your Tally API Key

1. Log in to [Tally.so](https://tally.so)
2. Go to [Account Settings → API](https://tally.so/account/api)
3. Generate a new API key
4. Copy the key for the next step

### 2. Set Environment Variables

#### Development

Add to your `.env` file or shell profile:

```bash
export TALLY_API_KEY="your-api-key-here"
```

#### Production

Set the environment variable on your server:

```bash
export TALLY_API_KEY="your-production-api-key"
export TALLY_SIGNING_SECRET="your-webhook-secret"
```

### 3. Configure Webhook (Optional but Recommended)

To verify webhook requests from Tally:

1. In Tally, go to your form settings
2. Navigate to **Integrations → Webhooks**
3. Add your webhook URL: `https://yourdomain.com/api/tally/webhook`
4. Generate a signing secret
5. Set `TALLY_SIGNING_SECRET` environment variable with this secret

**Note**: In development, signature verification is skipped if `TALLY_SIGNING_SECRET` is not set.

### 4. Link Tasks to Tally Forms

Each task must be associated with a Tally form:

1. Create a form in Tally with the following hidden fields:
   - `task_id` - The ID of the task
   - `user_id` - The ID of the student
   - `user_name` - The name of the student (optional)

2. In your application, edit the task and set the `tally_form_id` field to the Tally form ID
   - Find the form ID in the Tally URL: `https://tally.so/r/YOUR_FORM_ID`

## How It Works

### Webhook Flow

1. Student fills out and submits a Tally form
2. Tally sends a webhook to `/api/tally/webhook` with submission data
3. The webhook handler:
   - Extracts `user_id` and `task_id` from hidden fields
   - Finds the corresponding `TaskSubmission` record
   - Updates it with `status: "completed"` and `tally_response_id`
   - Broadcasts updates to LiveView for real-time UI updates

### Viewing Submissions

1. Teacher navigates to the task progress page
2. Completed submissions show as green checkmarks
3. Clicking a completed submission:
   - Fetches full submission data from Tally API
   - Displays student name, submission date, and uploaded files
   - Shows file previews for images
   - Provides download links for all files

## API Endpoints

### Tally API Endpoints Used

- `GET /forms/{formId}/submissions/{submissionId}` - Fetch a single submission
- `GET /forms/{formId}/submissions` - Fetch all submissions for a form

### Webhook Endpoint

- `POST /api/tally/webhook` - Receives submission notifications from Tally

## Troubleshooting

### "Tally API key not configured" error

**Solution**: Make sure `TALLY_API_KEY` environment variable is set and restart your application.

### "No Tally form configured for this task" error

**Solution**: Edit the task and set the `tally_form_id` field to your Tally form ID.

### "Unauthorized" error when fetching submissions

**Solution**: Verify your API key is correct and has the necessary permissions.

### Webhook signature verification fails

**Solution**: 
- Ensure `TALLY_SIGNING_SECRET` matches the secret in your Tally webhook settings
- In development, you can set it to `nil` to skip verification

### Submissions not showing up

**Checklist**:
1. Verify the webhook is configured correctly in Tally
2. Check that hidden fields (`task_id`, `user_id`) are included in the form
3. Ensure the `TaskSubmission` record exists before the student submits
4. Check application logs for webhook errors

## Testing

### Test Webhook Locally

Use a tool like [ngrok](https://ngrok.com) to expose your local server:

```bash
ngrok http 4000
```

Then configure the ngrok URL as your webhook endpoint in Tally.

### Test API Integration

1. Set your `TALLY_API_KEY` environment variable
2. Submit a test form in Tally
3. Navigate to the progress page for that task
4. Click the completed submission to view details

## Security Notes

- **Never commit API keys** to version control
- Use environment variables for all sensitive data
- In production, always set `TALLY_SIGNING_SECRET` to verify webhook authenticity
- API keys should be kept secure and rotated periodically