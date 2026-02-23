# Tally Integration Flow Diagram

## Complete System Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           TEACHER SETUP PHASE                            │
└─────────────────────────────────────────────────────────────────────────┘

1. Teacher creates form in Tally.so
   ├── Adds questions/content
   ├── Adds Hidden Fields:
   │   ├── user_id
   │   ├── task_id
   │   └── user_name (optional)
   └── Publishes form → Gets URL: https://tally.so/r/abc123

2. Teacher configures webhook
   └── Tally → Integrations → Webhooks
       ├── URL: https://yourdomain.com/api/webhooks/tally
       └── (Optional) Signing Secret: "your-secret"

3. Teacher creates task in Tasky
   ├── Name: "Complete Survey"
   ├── Link: https://tally.so/r/abc123
   └── Assigns to students
       └── Creates task_submissions records (status: "not_started")

┌─────────────────────────────────────────────────────────────────────────┐
│                          STUDENT USAGE PHASE                             │
└─────────────────────────────────────────────────────────────────────────┘

4. Student logs in → Goes to "My Tasks"
   └── Sees task card with clickable link

5. Student clicks task link
   ├── Link includes URL parameters:
   │   https://tally.so/r/abc123?user_id=5&task_id=10&user_name=student@example.com
   ├── Opens in new tab
   └── Status updates: "not_started" → "in_progress"

6. Student sees Tally form
   └── Hidden fields automatically capture:
       ├── user_id = 5
       ├── task_id = 10
       └── user_name = student@example.com

7. Student completes and submits form

┌─────────────────────────────────────────────────────────────────────────┐
│                          WEBHOOK PROCESSING                              │
└─────────────────────────────────────────────────────────────────────────┘

8. Tally sends webhook POST request
   POST https://yourdomain.com/api/webhooks/tally
   Content-Type: application/json
   Tally-Signature: <hmac-sha256-signature>
   
   {
     "eventType": "FORM_RESPONSE",
     "data": {
       "responseId": "tally-response-123",
       "fields": [
         {"label": "user_id", "value": "5"},
         {"label": "task_id", "value": "10"},
         {"label": "Question 1", "value": "Student's answer"}
       ]
     }
   }

9. Phoenix receives webhook
   └── Router: POST /api/webhooks/tally
       └── TallyWebhookController.receive/2

10. Controller processes webhook
    ├── Verifies signature (if configured)
    ├── Extracts user_id and task_id from hidden fields
    ├── Finds submission: WHERE student_id=5 AND task_id=10
    └── Updates submission:
        ├── status = "completed"
        ├── completed_at = NOW()
        └── tally_response_id = "tally-response-123"

11. Controller responds
    └── HTTP 200 OK {"status": "ok"}

┌─────────────────────────────────────────────────────────────────────────┐
│                           RESULT & GRADING                               │
└─────────────────────────────────────────────────────────────────────────┘

12. Student sees updated status
    └── My Tasks page shows: ✅ "Completed"

13. Teacher reviews submissions
    ├── Tasks → View Task → Submissions
    ├── Sees "completed" submissions
    └── Can grade and provide feedback
        ├── Points: 0-100
        ├── Feedback: text
        └── Status: "completed" → "review_approved"
```

## Database Changes Flow

```
task_submissions table
───────────────────────────────────────────────────────────────────────

BEFORE student starts:
┌────────────┬────────────┬──────────┬──────────────┬────────────────────┐
│ student_id │ task_id    │ status   │ completed_at │ tally_response_id  │
├────────────┼────────────┼──────────┼──────────────┼────────────────────┤
│ 5          │ 10         │ not_     │ NULL         │ NULL               │
│            │            │ started  │              │                    │
└────────────┴────────────┴──────────┴──────────────┴────────────────────┘

AFTER clicking link (optional, depends on implementation):
┌────────────┬────────────┬──────────┬──────────────┬────────────────────┐
│ student_id │ task_id    │ status   │ completed_at │ tally_response_id  │
├────────────┼────────────┼──────────┼──────────────┼────────────────────┤
│ 5          │ 10         │ in_      │ NULL         │ NULL               │
│            │            │ progress │              │                    │
└────────────┴────────────┴──────────┴──────────────┴────────────────────┘

AFTER webhook received:
┌────────────┬────────────┬──────────┬──────────────────┬────────────────┐
│ student_id │ task_id    │ status   │ completed_at     │ tally_response │
├────────────┼────────────┼──────────┼──────────────────┼────────────────┤
│ 5          │ 10         │ completed│ 2024-01-15 10:30 │ tally-resp-123 │
└────────────┴────────────┴──────────┴──────────────────┴────────────────┘

AFTER teacher grades:
┌────────────┬────────────┬─────────────┬──────────┬────────┬───────────┐
│ student_id │ task_id    │ status      │ points   │ graded │ graded_by │
├────────────┼────────────┼─────────────┼──────────┼────────┼───────────┤
│ 5          │ 10         │ review_     │ 95       │ 2024-  │ 1         │
│            │            │ approved    │          │ 01-15  │ (teacher) │
└────────────┴────────────┴─────────────┴──────────┴────────┴───────────┘
```

## Status Progression

```
Task Assignment Flow:
═══════════════════════════════════════════════════════════════════════

Teacher assigns → not_started (or draft/open)
                      ↓
Student clicks   → in_progress (LiveView updates on click)
                      ↓
Student submits  → completed (Webhook updates via POST)
                      ↓
Teacher grades   → review_approved OR review_denied
```

## Error Handling Flow

```
Webhook receives POST
    ↓
┌───────────────────────┐
│ Verify Signature      │
│ (if secret configured)│
└───────┬───────────────┘
        ↓
    [Invalid?] → Return 401 Unauthorized
        ↓ [Valid]
┌───────────────────────┐
│ Extract user_id &     │
│ task_id from fields   │
└───────┬───────────────┘
        ↓
    [Missing?] → Return 400 Bad Request
        ↓ [Found]
┌───────────────────────┐
│ Find submission in DB │
└───────┬───────────────┘
        ↓
    [Not found?] → Return 404 Not Found
        ↓ [Found]
┌───────────────────────┐
│ Update submission     │
│ status = "completed"  │
└───────┬───────────────┘
        ↓
    [Update fails?] → Return 422 Unprocessable Entity
        ↓ [Success]
┌───────────────────────┐
│ Return 200 OK         │
└───────────────────────┘
```

## Retry Mechanism (Tally Side)

```
Webhook Delivery Attempt
    ↓
[Successful 2XX response?] → ✅ Done
    ↓ [No - timeout or error]
Wait 5 minutes → Retry #1
    ↓
[Successful?] → ✅ Done
    ↓ [No]
Wait 30 minutes → Retry #2
    ↓
[Successful?] → ✅ Done
    ↓ [No]
Wait 1 hour → Retry #3
    ↓
[Successful?] → ✅ Done
    ↓ [No]
Wait 6 hours → Retry #4
    ↓
[Successful?] → ✅ Done
    ↓ [No]
Wait 1 day → Retry #5 (Final attempt)
    ↓
[Successful?] → ✅ Done
    ↓ [No]
❌ Give up - check Tally event logs
```

## Security Flow with Signing Secret

```
Production Setup:
─────────────────

1. Generate secret:
   $ openssl rand -base64 32
   → "Xj8f9k2LmN5pQr7sT4vWxYz1A3bC6dE..."

2. Configure in Tally:
   Webhook settings → Signing Secret → Paste secret

3. Configure in Phoenix:
   Export TALLY_SIGNING_SECRET="Xj8f9k2LmN5pQr7sT4vWxYz1A3bC6dE..."

Webhook Request:
────────────────

Tally calculates signature:
   payload = JSON.stringify(request_body)
   signature = HMAC-SHA256(signing_secret, payload)
   signature_base64 = Base64.encode(signature)
   
Tally sends:
   Header: Tally-Signature: "abc123def456..."
   Body: { "data": {...} }

Phoenix verifies:
   received_signature = header["tally-signature"]
   calculated_signature = HMAC-SHA256(secret, request_body)
   
   IF received_signature == calculated_signature:
      ✅ Process webhook
   ELSE:
      ❌ Return 401 Unauthorized
```

## Local Development with ngrok

```
Development Machine:
────────────────────

Terminal 1:
$ mix phx.server
→ Server running on localhost:4000

Terminal 2:
$ ngrok http 4000
→ Forwarding: https://abc123.ngrok.io → localhost:4000

Tally Configuration:
────────────────────
Webhook URL: https://abc123.ngrok.io/api/webhooks/tally

Flow:
─────
Student submits form
    ↓
Tally → https://abc123.ngrok.io/api/webhooks/tally
    ↓
ngrok tunnel → localhost:4000/api/webhooks/tally
    ↓
Phoenix processes webhook
    ↓
You see logs in Terminal 1 ✅
```

## Key URLs Reference

```
Production:
───────────
Webhook endpoint: https://yourdomain.com/api/webhooks/tally
Task link format: https://tally.so/r/abc123?user_id=X&task_id=Y&user_name=email

Local Development:
──────────────────
Webhook endpoint: https://your-ngrok-url.ngrok.io/api/webhooks/tally
Phoenix server:   http://localhost:4000
```

## Quick Troubleshooting Decision Tree

```
Webhook not working?
    ↓
Is form published? ──[No]──→ Publish the form
    ↓ [Yes]
Is webhook enabled? ──[No]──→ Enable webhook toggle
    ↓ [Yes]
Check Tally event log ──→ See HTTP response
    ↓
[200 OK] ──→ Check Phoenix logs for processing
    ↓
[404] ──→ Check submission exists in DB
    ↓
[400] ──→ Check hidden fields: user_id, task_id
    ↓
[401] ──→ Check signing secret matches
    ↓
[timeout] ──→ Check server is accessible, ngrok running
```
