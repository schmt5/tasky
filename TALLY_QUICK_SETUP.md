# Tally Webhook Integration - Quick Setup Guide

This guide will help you quickly set up Tally.so forms to automatically mark student tasks as completed.

## 🚀 Quick Start (5 Minutes)

### Step 1: Create Your Tally Form

1. Go to [tally.so](https://tally.so) (no account required to start)
2. Create a new form with your questions
3. **CRITICAL**: Add these **Hidden Fields** to your form:
   - Add field → Hidden Field → Label: `user_id`
   - Add field → Hidden Field → Label: `task_id`
   - Add field → Hidden Field → Label: `user_name` (optional)

### Step 2: Publish and Get Form URL

1. Click **Publish** in Tally
2. Copy your form URL (looks like: `https://tally.so/r/abc123`)

### Step 3: Configure Webhook

1. In Tally, go to **Integrations** → **Webhooks**
2. Click **Connect**
3. Enter webhook URL:
   - **Production**: `https://yourdomain.com/api/webhooks/tally`
   - **Local Dev**: `https://your-ngrok-url.ngrok.io/api/webhooks/tally`
4. *(Optional)* Add a signing secret for security
5. Click **Save**

### Step 4: Create Task in Tasky

1. Log in as teacher/admin
2. Go to **Tasks** → **New Task**
3. Enter task details
4. Paste your Tally form URL in the **Link** field
5. Save and assign to students

### Step 5: Test It!

1. Log in as a student
2. Go to **My Tasks**
3. Click on your task
4. Complete and submit the form
5. Task should automatically be marked as "completed" ✅

## 🔧 Local Development with ngrok

To test webhooks locally:

```bash
# Terminal 1: Start Phoenix
mix phx.server

# Terminal 2: Start ngrok
ngrok http 4000

# Copy the ngrok URL (e.g., https://abc123.ngrok.io)
# Use this in your Tally webhook settings:
# https://abc123.ngrok.io/api/webhooks/tally
```

## 🔒 Security (Production)

For production, enable signature verification:

1. Generate a secure secret:
   ```bash
   openssl rand -base64 32
   ```

2. Add to Tally webhook settings (in the "Signing Secret" field)

3. Set environment variable on your server:
   ```bash
   export TALLY_SIGNING_SECRET="your-secure-secret-here"
   ```

## 📝 How It Works

```
Student clicks task → Opens Tally form with URL parameters
                      ↓
                      ?user_id=5&task_id=10&user_name=student@example.com
                      ↓
                      Hidden fields capture these values
                      ↓
Student submits form → Tally sends webhook POST
                      ↓
                      POST /api/webhooks/tally
                      ↓
Your app receives webhook → Finds submission by user_id + task_id
                      ↓
                      Marks status as "completed"
                      ↓
Student sees ✅ on dashboard
```

## ✅ Checklist

Before going live, verify:

- [ ] Hidden fields added to Tally form: `user_id`, `task_id`
- [ ] Form is published (not in draft mode)
- [ ] Webhook configured with correct URL
- [ ] Webhook is enabled (toggle is ON)
- [ ] Task created with Tally form URL in Link field
- [ ] Task assigned to students
- [ ] Tested with a real submission
- [ ] (Production) Signing secret configured

## 🐛 Troubleshooting

**Webhook not firing?**
- Check form is published
- Verify webhook URL is correct
- Ensure webhook toggle is ON
- Check Events Log in Tally webhook settings

**"Submission not found" error?**
- Verify task was assigned to student
- Check hidden fields are named exactly: `user_id`, `task_id`
- Ensure student has a submission record in database

**Signature verification fails?**
- Verify secret matches in both Tally and your config
- For local dev, set `config :tasky, :tally_signing_secret, nil` in `config/dev.exs`

## 📊 View Logs

In Tally:
1. Go to form → Integrations → Webhooks
2. Click 🕔 icon next to webhook
3. View delivery status, payloads, responses

In Your App:
- Check Phoenix console logs for webhook activity
- Look for: "Successfully marked submission X as completed"

## 🎯 Example Form URL

When a student clicks a task link, it looks like:

```
https://tally.so/r/abc123?user_id=5&task_id=10&user_name=student@example.com
```

The hidden fields automatically capture these URL parameters!

## 💡 Tips

1. **Test First**: Use ngrok to test locally before deploying
2. **Monitor Logs**: Check Tally's webhook event log regularly
3. **Unique Forms**: Create separate Tally forms for different task types
4. **Keep URLs Simple**: Use the standard Tally URL format
5. **Document Secrets**: Store signing secrets securely (use environment variables)

## 📚 More Info

For detailed documentation, see `TALLY_INTEGRATION.md`

---

**Need Help?**
- Check webhook event logs in Tally dashboard
- Verify submission exists: `mix ecto.query "select * from task_submissions where student_id = X and task_id = Y"`
- Test manually with curl (see `TALLY_INTEGRATION.md`)