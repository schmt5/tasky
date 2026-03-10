# Class System Implementation

## Overview

This document describes the implementation of the class/course management system for Tasky. The system allows teachers and administrators to create classes, generate registration links, and automatically assign students to classes during registration.

## Features Implemented

### 1. Database Schema

#### Classes Table
- `id` (primary key)
- `name` (string, required) - The display name of the class (e.g., "Klasse 5a", "Mathematik 2024")
- `slug` (string, required, unique) - URL-friendly identifier generated from name
- `inserted_at` (datetime)
- `updated_at` (datetime)

#### Users Table Updates
- Added `class_id` (foreign key to classes, nullable)
- Students can optionally belong to one class
- On delete: `nilify_all` (students are not deleted when class is deleted)

### 2. Core Modules

#### `Tasky.Classes` Context
Location: `lib/tasky/classes.ex`

Functions:
- `list_classes/0` - Returns all classes ordered by name
- `get_class!/1` - Gets class by ID (raises if not found)
- `get_class_by_slug/1` - Gets class by slug (returns nil if not found)
- `create_class/1` - Creates a new class with auto-generated slug
- `update_class/2` - Updates an existing class
- `delete_class/1` - Deletes a class (students remain but class_id is set to nil)
- `change_class/2` - Returns changeset for forms
- `count_students_in_class/1` - Counts students in a specific class
- `list_students_in_class/1` - Lists all students in a class

#### `Tasky.Classes.Class` Schema
Location: `lib/tasky/classes/class.ex`

Features:
- Automatic slug generation from class name
- Custom `slugify/1` function that:
  - Converts to lowercase
  - Removes special characters
  - Replaces spaces with hyphens
  - Handles Unicode characters (NFD normalization)
- Unique constraint on slug

Examples:
- "Klasse 5a" → "klasse-5a"
- "Mathematik 2024" → "mathematik-2024"
- "Deutsch & Englisch" → "deutsch-englisch"

### 3. User Interface

#### Class Management (Teachers/Admins)

**Index Page** (`TaskyWeb.ClassLive.Index`)
Location: `lib/tasky_web/live/class_live/index.ex`

Features:
- Grid view of all classes
- Student count per class
- Copy-to-clipboard registration link for each class
- Edit and delete actions
- Empty state when no classes exist
- Navigation link in header

**Form Page** (`TaskyWeb.ClassLive.Form`)
Location: `lib/tasky_web/live/class_live/form.ex`

Features:
- Create new classes
- Edit existing classes
- Live preview of auto-generated slug
- Form validation with error messages
- Cancel and save actions

#### Registration Flow

**Updated Registration LiveView**
Location: `lib/tasky_web/live/user_live/registration.ex`

Features:
- Accepts `?class=slug` query parameter
- Displays readonly class name field when class slug is provided
- Automatically assigns class_id during registration
- Shows error message if class slug is invalid
- Maintains class_id through form validation
- Works with or without class parameter (optional)

### 4. Routes

Added to `:tasks` live_session (requires teacher/admin authentication):
```elixir
live "/classes", ClassLive.Index, :index
live "/classes/new", ClassLive.Form, :new
live "/classes/:id/edit", ClassLive.Form, :edit
```

Registration route (public):
```elixir
live "/users/register", UserLive.Registration, :new
```

### 5. Navigation

Added "Klassen" link to the main navigation bar for authenticated teachers and admins.
Location: `lib/tasky_web/components/layouts.ex`

### 6. JavaScript Integration

**Copy to Clipboard**
Location: `assets/js/app.js`

Features:
- Handles `phx:copy-to-clipboard` events
- Modern Clipboard API with fallback for older browsers
- Executes when teacher clicks copy button on registration link

## Usage

### For Teachers/Admins

1. **Create a Class**
   - Navigate to `/classes`
   - Click "Neue Klasse"
   - Enter class name (slug is auto-generated)
   - Click "Klasse erstellen"

2. **Share Registration Link**
   - View class in `/classes` index
   - Copy registration link using copy button
   - Share link with students

3. **Manage Classes**
   - Edit class name (slug is regenerated)
   - Delete class (students remain, class_id becomes null)
   - View student count per class

### For Students

1. **Register with Class Link**
   - Receive registration link from teacher (e.g., `/users/register?class=klasse-5a`)
   - Fill out registration form
   - Class name is displayed as readonly field
   - Submit form - automatically assigned to class

2. **Register without Class**
   - Use standard registration link `/users/register`
   - No class assignment
   - Can be assigned to class later by admin

## Database Migrations

1. `20260310023127_create_classes.exs` - Creates classes table
2. `20260310023143_add_class_id_to_users.exs` - Adds class_id to users

## Testing

Test Location: `test/tasky_web/live/user_live/registration_test.exs`

Test Cases:
- ✅ Displays class name when valid slug is provided
- ✅ Shows error when invalid class slug is provided
- ✅ Registers user with class when slug is provided
- ✅ Registers user without class when no slug is provided

All tests passing.

## Seed Data

Updated: `priv/repo/seeds.exs`

Includes:
- 3 sample classes ("Klasse 5a", "Mathematik 2024", "Informatik Oberstufe")
- Students assigned to classes
- Registration URLs displayed after seed

## Design Decisions

### 1. Optional Class Assignment
- Students can register with or without a class
- Allows flexibility for different school scenarios
- Teachers can create invitation links for specific classes

### 2. One Class Per Student
- Simple `belongs_to` relationship (not many-to-many)
- Can be extended to many-to-many in future if needed
- Meets current requirements

### 3. No Class Creator Tracking
- Classes don't store who created them
- All teachers/admins can manage all classes
- Simpler authorization model

### 4. Automatic Slug Generation
- No manual slug entry required
- Reduces errors and improves UX
- Pure Elixir implementation (no external dependencies)

### 5. On Delete: Nilify
- When class is deleted, students remain
- Their `class_id` is set to null
- Prevents accidental student deletion

## Security Considerations

- Class management routes require teacher/admin authentication
- Registration is public (as intended)
- Class_id validation via foreign key constraint
- No authorization needed for viewing class via slug (public registration)

## Future Enhancements

Potential improvements:
- Many-to-many relationship (students in multiple classes)
- Class archives (soft delete)
- Student management per class
- Class-specific settings/permissions
- Bulk student import with class assignment
- Class enrollment/unenrollment by students
- Class capacity limits

## UI/UX Highlights

- Beautiful gradient backgrounds
- Card-based layout for class grid
- Inline copy-to-clipboard functionality
- Real-time slug preview during class creation
- Responsive design with Tailwind CSS
- German language interface (matching app locale)
- Clear visual feedback for all actions
- Empty states with helpful CTAs