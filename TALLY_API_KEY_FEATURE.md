# Tally API Key Feature Documentation

## Overview

This feature allows teacher users to configure their own personal Tally.so API key, enabling them to use their own Tally account for form integrations within Tasky.

## Changes Made

### 1. Database Migration

**File:** `priv/repo/migrations/20260304113646_add_tally_api_key_to_users.exs`

- Added `tally_api_key` column to the `users` table (string type)
- This allows each user to store their personal Tally API key

### 2. User Schema Updates

**File:** `lib/tasky/accounts/user.ex`

- Added `tally_api_key` field to the User schema
- Created `tally_api_key_changeset/2` function for validating API key updates
- **Validates that API key is required and cannot be empty string**
- Automatically trims whitespace from API key input
- Validates length (min: 1, max: 255 characters)
- Allows `nil` value (for clearing/removing the API key)
- Custom validation messages in German

### 3. Accounts Context Functions

**File:** `lib/tasky/accounts.ex`

Added two new functions:
- `change_user_tally_api_key/2` - Returns a changeset for changing the API key
- `update_user_tally_api_key/2` - Updates the user's API key in the database

### 4. New LiveView for Tally Settings

**File:** `lib/tasky_web/live/user_live/tally_settings.ex`

A dedicated settings page for managing Tally API keys with:
- Form to input/update API key
- Button to clear/remove API key
- Status indicator showing if API key is configured
- Help section with instructions on obtaining an API key from Tally.so
- Only accessible to authenticated users

**Features:**
- Real-time validation of API key input
- Clear success/error messages
- Ability to remove API key
- Professional UI with German localization
- **Redirects to home page (`/`) after successful save**

### 5. Router Update

**File:** `lib/tasky_web/router.ex`

- Added route `/settings/tally` in a new `:teacher_settings` live_session
- Route points to `UserLive.TallySettings` LiveView
- Requires admin or teacher role but **does not require sudo mode/re-authentication**
- This allows teachers to update their API key without having to re-authenticate

### 6. Settings Page Integration

**File:** `lib/tasky_web/live/user_live/settings.ex`

- Added new section for Tally.so Integration (visible only to teachers)
- Shows current API key status (configured/not configured)
- Link to navigate to the dedicated Tally settings page

### 7. User Menu Update

**File:** `lib/tasky_web/components/layouts.ex`

- Added "Tally API Key" menu item to the user dropdown menu
- Appears between "Einstellungen" and "Abmelden"
- Only visible to users with teacher or admin role
- Links directly to `/settings/tally`
- Uses hero-key icon for visual consistency

### 8. API Client Updates

**File:** `lib/tasky/tally/client.ex`

Updated all functions to accept and use `current_scope`:
- `list_forms/1` - Now requires `current_scope` parameter
- `get_form/2` - Now requires `current_scope` parameter
- Extracts API key from `current_scope.user.tally_api_key`
- Returns `:api_key_not_configured` error if no key is found

**File:** `lib/tasky/external/tally_api.ex`

Updated all functions to accept and use `current_scope`:
- `fetch_submission/3` - Now requires `current_scope` parameter
- `fetch_submissions/2` - Now requires `current_scope` parameter
- Extracts API key from `current_scope.user.tally_api_key`
- Returns `:api_key_not_configured` error if no key is found

### 9. LiveView Call Updates

**File:** `lib/tasky_web/live/course_live/add.ex`
- Updated `Client.list_forms()` call to `Client.list_forms(socket.assigns.current_scope)`

**File:** `lib/tasky_web/live/task_live/progress.ex`
- Updated `TallyApi.fetch_submission(form_id, submission_id)` call to include `current_scope`

## Usage

### For Teachers

**Option 1: Via User Menu (Quick Access)**
1. Click on your email in the top-right user menu
2. Click "Tally API Key" in the dropdown
3. Enter your Tally API key in the form
4. Click "API Key speichern" to save
5. You'll be redirected to the home page with a success message

**Option 2: Via Settings Page**
1. Navigate to **Settings** (`/users/settings`)
2. Find the "Tally.so Integration" section
3. Click "API Key verwalten" to go to Tally settings (`/settings/tally`)
4. Enter your Tally API key in the form
5. Click "API Key speichern" to save
6. You'll be redirected to the home page with a success message

**Note:** The Tally settings page does NOT require re-authentication, so you can update your API key anytime without entering your password again. After saving, you're automatically redirected to the home page.

### Obtaining a Tally API Key

1. Log in to your Tally.so account
2. Open Settings
3. Navigate to the "API" section
4. Create a new API key or copy an existing one
5. Paste it into the Tasky Tally settings page

### Removing an API Key

On the Tally settings page, click the "API Key entfernen" button to clear your stored API key.

## Validation Rules

The Tally API key field has the following validation requirements:

1. **Required**: Cannot be submitted as an empty string
2. **Trimmed**: Whitespace is automatically removed from both ends
3. **Length**: Must be between 1 and 255 characters
4. **Can be cleared**: Setting to `nil` (via "API Key entfernen" button) is allowed
5. **Error messages**: All validation errors are displayed in German

## Security Notes

- API keys are stored securely in the database
- Keys are only accessible to the user who owns them
- Each API call uses the authenticated user's personal API key via `current_scope`
- No hardcoded API keys remain in the codebase

## Error Handling

The system handles the following scenarios:
- **No API key configured**: Returns `:api_key_not_configured` error
- **Invalid API key**: Returns `:unauthorized` error from Tally API
- **Connection errors**: Returns `:connection_error`
- **Not found**: Returns `:not_found` for missing forms/submissions

## Testing

After implementation, teachers should test:
1. **Valid API key**: Set a proper API key and verify it saves successfully
2. **Empty string**: Try submitting an empty string - should show error "darf nicht leer sein"
3. **Whitespace handling**: Enter "  key  " and verify it's trimmed to "key"
4. **Form integration**: Verify they can see their Tally forms when adding learning units
5. **Submission fetching**: Confirm form submissions are properly fetched and displayed
6. **Removal**: Test removing the API key via "API Key entfernen" button
7. **Error display**: Verify appropriate error messages appear in German

## Future Enhancements

Possible future improvements:
- API key validation on save (test connection to Tally)
- Encrypted storage of API keys
- API key expiration tracking
- Per-course API key configuration
- Bulk import of forms from Tally