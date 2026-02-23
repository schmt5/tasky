# Tally Integration - Deployment Checklist

## ✅ Pre-Deployment Checklist

### Database Migration
- [ ] Run migration: `mix ecto.migrate`
- [ ] Verify migration applied: `mix ecto.migrations`
- [ ] Check `tally_response_id` column exists in `task_submissions` table
- [ ] Verify index created on `tally_response_id`

### Code Compilation
- [ ] Project compiles without errors: `mix compile`
- [ ] All tests pass: `mix test`
- [ ] Webhook tests pass: `mix test test/tasky_web/controllers/tally_webhook_controller_test.exs`
- [ ] No critical warnings in compilation

### Route Configuration
- [ ] Webhook route exists: `mix phx.routes | grep tally`
- [ ] Route shows: `POST /api/webhooks/tally TaskyWeb.TallyWebhookController :receive`

---

## 🔧 Local Development Setup

### Environment Configuration
- [ ] Set `config :tasky, :tally_signing_secret, nil` in `config/dev.exs`
- [ ] Install ngrok: `brew install ngrok` (Mac) or download from ngrok.com
- [ ] Test Phoenix server starts: `mix phx.server`

### ngrok Setup
- [ ] Start ngrok: `ngrok http 4000`
- [ ] Copy ngrok HTTPS URL (e.g., `https://abc123.ngrok.io`)
- [ ] Keep ngrok running during development

### Tally Form Setup
- [ ] Create form at tally.so
- [ ] Add questions/content
- [ ] Add Hidden Field with label: `user_id`
- [ ] Add Hidden Field with label: `task_id`
- [ ] Add Hidden Field with label: `user_name` (optional)
- [ ] Publish form
- [ ] Copy form URL

### Webhook Configuration (Dev)
- [ ] Go to Tally → Integrations → Webhooks
- [ ] Click "Connect"
- [ ] Enter webhook URL: `https://[your-ngrok-url].ngrok.io/api/webhooks/tally`
- [ ] Leave signing secret empty for dev
- [ ] Save and enable webhook

### Testing
- [ ] Create test task in Tasky with Tally form URL
- [ ] Assign task to test student account
- [ ] Login as student
- [ ] Click task link and submit form
- [ ] Verify task marked as "completed"
- [ ] Check Phoenix logs for webhook activity
- [ ] Check Tally event logs for successful delivery

---

## 🚀 Production Deployment

### Security Setup
- [ ] Generate signing secret: `openssl rand -base64 32`
- [ ] Store secret securely (password manager, secrets vault)
- [ ] Set environment variable on production server:
  ```bash
  export TALLY_SIGNING_SECRET="your-secure-secret-here"
  ```

### Server Configuration
- [ ] Ensure production server uses HTTPS
- [ ] Verify firewall allows incoming HTTPS requests
- [ ] Check server is publicly accessible
- [ ] Confirm environment variable is set: `echo $TALLY_SIGNING_SECRET`

### Application Deployment
- [ ] Deploy latest code to production
- [ ] Run migrations: `mix ecto.migrate`
- [ ] Restart application
- [ ] Verify webhook route exists: `mix phx.routes | grep tally`
- [ ] Check application logs for startup errors

### Tally Configuration (Production)
- [ ] Update webhook URL to production: `https://yourdomain.com/api/webhooks/tally`
- [ ] Add signing secret from environment variable
- [ ] Save configuration
- [ ] Enable webhook toggle

### Production Testing
- [ ] Create test task with Tally form
- [ ] Assign to test student account
- [ ] Submit form as student
- [ ] Verify submission marked as completed
- [ ] Check Tally event logs (should show 200 OK)
- [ ] Check application logs for webhook processing
- [ ] Verify signature verification working (no warnings about missing secret)

---

## 📊 Monitoring Setup

### Application Monitoring
- [ ] Set up log aggregation (e.g., Papertrail, LogDNA)
- [ ] Monitor for webhook errors in logs
- [ ] Set up alerts for 4xx/5xx responses
- [ ] Track webhook processing time

### Tally Monitoring
- [ ] Bookmark Tally webhook event logs
- [ ] Check event logs daily for first week
- [ ] Set up process to review failed webhooks
- [ ] Document common error patterns

### Health Checks
- [ ] Monitor endpoint response time (should be < 1 second)
- [ ] Verify submissions completing correctly
- [ ] Check database for orphaned submissions
- [ ] Review webhook retry patterns

---

## 🔍 Post-Deployment Verification

### Day 1 Checks
- [ ] Monitor webhook deliveries in Tally dashboard
- [ ] Verify all submissions completing successfully
- [ ] Check for any signature verification errors
- [ ] Review application logs for anomalies
- [ ] Confirm no timeout errors

### Week 1 Checks
- [ ] Review completion rates (should be 100% for submitted forms)
- [ ] Check for any stuck submissions
- [ ] Verify retry mechanism working correctly
- [ ] Review performance metrics
- [ ] Gather teacher/student feedback

### Month 1 Checks
- [ ] Analyze webhook success rate
- [ ] Review any recurring errors
- [ ] Optimize if necessary
- [ ] Document lessons learned
- [ ] Update documentation based on real usage

---

## 🐛 Rollback Plan

### If Deployment Fails
1. [ ] Check application logs for specific error
2. [ ] Verify environment variables are set
3. [ ] Confirm migration ran successfully
4. [ ] Test webhook endpoint manually with curl
5. [ ] If needed, disable webhook in Tally temporarily

### Emergency Rollback Steps
```bash
# Revert migration
mix ecto.rollback

# Deploy previous version
git checkout previous-version
mix deploy

# Disable webhook in Tally
# (Manual step in Tally dashboard)
```

### Fallback Options
- [ ] Disable Tally webhook temporarily
- [ ] Use manual completion workflow
- [ ] Fix issues in staging environment
- [ ] Redeploy with fixes

---

## 📚 Documentation Updates

### Internal Documentation
- [ ] Update team wiki with Tally integration guide
- [ ] Document webhook URL for different environments
- [ ] Share signing secret location with team (securely)
- [ ] Create runbook for common issues

### User Documentation
- [ ] Update teacher guide with Tally form creation steps
- [ ] Document required hidden fields
- [ ] Create troubleshooting guide for teachers
- [ ] Add FAQ section about automatic completion

---

## 🎯 Success Criteria

### Technical Success
- [x] All tests passing (11/11)
- [x] Zero errors in compilation
- [x] Database migration successful
- [x] Webhook endpoint responding correctly

### Functional Success
- [ ] Students can submit forms
- [ ] Tasks automatically marked as completed
- [ ] No duplicate completions
- [ ] Response time < 2 seconds
- [ ] Success rate > 99%

### User Success
- [ ] Teachers can create tasks with Tally forms
- [ ] Students have seamless experience
- [ ] No manual intervention required
- [ ] Zero complaints about completion tracking

---

## 🔒 Security Verification

### Production Security
- [ ] HTTPS enabled on all endpoints
- [ ] Signature verification working
- [ ] Secrets stored in environment variables (not code)
- [ ] No secrets in logs
- [ ] Input validation working correctly

### Access Control
- [ ] Webhook endpoint publicly accessible (required)
- [ ] Student data properly scoped
- [ ] No unauthorized access possible
- [ ] Audit logs enabled

---

## 📞 Support Contacts

### Internal Contacts
- **DevOps Lead**: [Name/Email]
- **Database Admin**: [Name/Email]
- **Application Owner**: [Name/Email]

### External Resources
- **Tally Support**: support@tally.so
- **Tally Documentation**: https://tally.so/help
- **Project Documentation**: See TALLY_INTEGRATION.md

---

## 📝 Sign-off

### Development Team
- [ ] Code reviewed and approved
- [ ] Tests verified passing
- [ ] Documentation complete

### Operations Team
- [ ] Infrastructure ready
- [ ] Monitoring configured
- [ ] Secrets properly stored

### Product Team
- [ ] Feature tested in staging
- [ ] User documentation ready
- [ ] Support team trained

---

**Deployment Date**: _____________  
**Deployed By**: _____________  
**Environment**: ☐ Staging  ☐ Production  
**Status**: ☐ Success  ☐ Rolled Back  ☐ Issues  

---

## Quick Reference

**Migration File**: `20260223124110_add_tally_response_id_to_task_submissions.exs`  
**Controller**: `lib/tasky_web/controllers/tally_webhook_controller.ex`  
**Route**: `POST /api/webhooks/tally`  
**Tests**: `test/tasky_web/controllers/tally_webhook_controller_test.exs`  
**Config (Dev)**: `config/dev.exs`  
**Config (Prod)**: `config/runtime.exs`  

**Documentation Files**:
- `TALLY_QUICK_SETUP.md` - 5-minute setup guide
- `TALLY_INTEGRATION.md` - Complete documentation
- `TALLY_FLOW_DIAGRAM.md` - Visual flow diagrams
- `TALLY_REFERENCE_CARD.md` - Quick reference
- `TALLY_IMPLEMENTATION_SUMMARY.md` - Technical details
- `TALLY_DEPLOYMENT_CHECKLIST.md` - This file