#!/bin/bash

# Test script for Tally webhook
# This simulates what Tally sends when a form is submitted

# Configuration
HOST="http://localhost:4000"
ENDPOINT="/api/webhooks/tally"
URL="${HOST}${ENDPOINT}"

# Test data - adjust these values to match your database
USER_ID="1"
TASK_ID="1"
RESPONSE_ID="test_response_$(date +%s)"

echo "Testing Tally webhook..."
echo "URL: $URL"
echo "User ID: $USER_ID"
echo "Task ID: $TASK_ID"
echo "Response ID: $RESPONSE_ID"
echo ""

# Send webhook request
curl -X POST "$URL" \
  -H "Content-Type: application/json" \
  -d '{
    "eventId": "test_event_123",
    "eventType": "FORM_RESPONSE",
    "createdAt": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
    "data": {
      "responseId": "'$RESPONSE_ID'",
      "submissionId": "'$RESPONSE_ID'",
      "respondentId": "test_respondent",
      "formId": "ODzq8K",
      "formName": "Test Form",
      "createdAt": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'",
      "fields": [
        {
          "key": "question_1",
          "label": "user_id",
          "type": "HIDDEN_FIELDS",
          "value": "'$USER_ID'"
        },
        {
          "key": "question_2",
          "label": "task_id",
          "type": "HIDDEN_FIELDS",
          "value": "'$TASK_ID'"
        },
        {
          "key": "question_3",
          "label": "submission",
          "type": "FILE_UPLOAD",
          "value": [
            {
              "id": "test_file_1",
              "name": "test.png",
              "url": "https://example.com/test.png",
              "mimeType": "image/png",
              "size": 12345
            }
          ]
        }
      ]
    }
  }' \
  -w "\n\nHTTP Status: %{http_code}\n" \
  -s -v

echo ""
echo "Check your Phoenix logs for detailed webhook processing information"
echo ""
echo "To use this script:"
echo "1. Make sure your Phoenix server is running (mix phx.server)"
echo "2. Update USER_ID and TASK_ID variables above to match existing records"
echo "3. Ensure a TaskSubmission record exists for this user/task combination"
echo "4. Run: bash test_webhook.sh"
