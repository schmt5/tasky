# Course Management Guide

## Overview

The Course Management feature allows teachers to organize tasks into courses and assign students to courses rather than individual tasks. This provides a more structured learning experience where students automatically get access to all tasks within their enrolled courses.

## Architecture

### Database Schema

The course system uses the following database structure:

- **courses** - Stores course information
  - `id` - Primary key
  - `name` - Course name (required)
  - `description` - Course description (optional)
  - `teacher_id` - Foreign key to users table
  - `inserted_at`, `updated_at` - Timestamps

- **tasks** - Updated to include course relationship
  - `course_id` - Foreign key to courses table (optional)
  - All existing fields remain unchanged

- **course_enrollments** - Join table for many-to-many relationship
  - `id` - Primary key
  - `course_id` - Foreign key to courses table
  - `student_id` - Foreign key to users table
  - Unique constraint on `[course_id, student_id]`
  - `inserted_at`, `updated_at` - Timestamps

### Relationships

- A **Course** belongs to a **Teacher** (User)
- A **Course** has many **Tasks**
- A **Course** has many **Students** through **CourseEnrollments**
- A **Task** belongs to a **Course** (optional)
- A **Student** can be enrolled in many **Courses**

## Features

### For Teachers

#### Course Management
- Create, edit, and delete courses
- View all courses they teach
- Add descriptions to courses

#### Task Management within Courses
- Create tasks directly within a course
- View all tasks associated with a course
- Edit and delete tasks
- Tasks can have statuses: draft, published, archived

#### Student Enrollment
- Enroll students in courses
- Unenroll students from courses
- View all enrolled students per course
- See which students are not yet enrolled

### For Students

#### Course Access
- View all courses they're enrolled in
- See course details and descriptions
- View their teacher's information

#### Task Access
- Automatically see all published tasks in enrolled courses
- Access tasks by course organization
- View task completion status

### For Admins

- View all courses across all teachers
- Full access to course management features

## Kurs-Katalog

Der Katalog ist der Weg, einen fertigen Kurs an andere Lehrpersonen
weiterzugeben. Er teilt nichts — er kopiert.

**Veröffentlichen.** Auf der Kursseite (`/courses/:id`) stellt die Lehrperson
den Kurs über "Im Katalog veröffentlichen" bereit; ein Chip neben dem Titel
zeigt danach, seit wann er drin ist, und derselbe Ort nimmt ihn wieder heraus.
Ein Kurs ohne Lerneinheiten wird abgewiesen. `courses.catalog_published_at`
trägt den Zustand und wird — wie `share_slug` — nicht aus Formulardaten
gecastet: nur `Courses.publish_to_catalog/2` und `unpublish_from_catalog/2`
setzen das Feld, damit eine Kopie die Veröffentlichung nicht erben kann.

**Sehen.** `/catalog` listet alle veröffentlichten Kurse (Autorname, Anzahl
Lerneinheiten, Datum), `/catalog/:id` zeigt sie als Read-only-Vorschau samt
gerendertem Inhalt und Anhängen. Beides steht allen Lehrpersonen und Admins
offen, Lernenden nicht. Im Katalog sind **alle** Lerneinheiten sichtbar, auch
Entwürfe, archivierte und gesperrte — das Publish-Modal sagt das.

**Übernehmen.** "In meine Kurse übernehmen" legt einen neuen Kurs im Konto der
importierenden Person an. Kopiert werden Name, Beschreibung und jede
Lerneinheit mit Inhalt, Bildern, Anhängen und Datei-Abgabefeldern. **Jede
kopierte Einheit entsteht als Entwurf und entsperrt** (`status: "draft"`,
`locked: false`) — die importierende Lehrperson gibt selbst frei. `extended`
bleibt erhalten: ein freiwilliger Zusatzauftrag ist eine inhaltliche
Eigenschaft, keine Freigabe. Nicht kopiert werden Lernende, Abgaben, der
Feedback-Briefkasten, der KI-Link und die Katalog-Veröffentlichung selbst.

Die Kopie ist ab dem Import eigenständig und besitzt ihre eigenen Dateien:
nimmt die Autorin den Kurs später aus dem Katalog oder löscht ihn, bleiben
bestehende Kopien intakt. Umgekehrt kostet jeder Import den vollen
Speicherplatz — das ist Absicht, geteilte Objekte würden beim Löschen einer
Kopie die anderen zerstören.

Autorisierung: `Courses.import_catalog_course_records/3` ist der einzige Pfad,
auf dem eine Lehrperson Inhalte einer anderen kopieren darf. Die
Veröffentlichung IST dort die Berechtigung, und sie wird beim Import frisch
gelesen — eine Vorschauseite, die offen stand, während die Autorin den Kurs
zurückgezogen hat, bekommt `{:error, :not_found}`.

## Routes

### Teacher/Admin Routes

```elixir
GET    /courses              # List all courses
GET    /courses/new          # New course form
POST   /courses              # Create course
GET    /courses/:id          # View course details
GET    /courses/:id/edit     # Edit course form
PATCH  /courses/:id          # Update course
DELETE /courses/:id          # Delete course
GET    /catalog              # Kurs-Katalog: alle veröffentlichten Kurse
GET    /catalog/:id          # Read-only-Vorschau + Übernehmen
```

### Student Routes

```elixir
GET /student/courses         # List enrolled courses
GET /student/courses/:id     # View course and its tasks
```

## Usage Examples

### Creating a Course (Teacher)

1. Navigate to `/courses`
2. Click "New Course"
3. Enter course name (required)
4. Enter course description (optional)
5. Click "Save Course"

### Adding Learning Units to a Course (Teacher)

1. Navigate to the course detail page (`/courses/:id`)
2. Click "Lerneinheit hinzufügen" in the Tasks section
3. Enter the unit's name — it is created as a **draft** (invisible to students)
   and optionally tick **"Erweiterte Lerneinheit"** to make it a voluntary
   extension (see below)
4. Author the content in the Tiptap editor (`/tasks/:id/content`), including
   interactive answer fields (answer blocks, Lückentext, checkboxes)
5. Optionally add teacher attachments and student upload fields in the
   "Dateien" tab
6. Publish the unit via the "Veröffentlichen" toggle on the course page

**Note:** Tasks are automatically associated with the course. Students fill
in their answers directly in the unit, upload required files, and mark the
unit complete; the teacher then reviews it and either approves it or sends
it back for revision with feedback.

### Enrolling Students (Teacher)

1. Navigate to the course detail page (`/courses/:id`)
2. Click "Enroll Students" in the Students section
3. A modal appears showing all unenrolled students
4. Click "Enroll" next to each student you want to add
5. Close the modal when done

### Unenrolling Students (Teacher)

1. Navigate to the course detail page (`/courses/:id`)
2. Find the student in the "Enrolled Students" section
3. Click "Unenroll" next to their name
4. Confirm the action

### Viewing Courses (Student)

1. Navigate to `/student/courses`
2. Click on any course card to view details
3. See all published tasks for that course
4. Click "View Task" to access individual tasks

## Context Functions

### Tasky.Courses

```elixir
# List courses based on user role
list_courses(scope)

# List courses a student is enrolled in
list_enrolled_courses(scope)

# Get a single course (with authorization)
get_course!(scope, id)

# Get a course for a student (only if enrolled)
get_course_for_student!(student_id, course_id)

# Create a new course
create_course(scope, attrs)

# Update a course
update_course(course, attrs)

# Delete a course
delete_course(course)

# Get changeset for course
change_course(course, attrs \\ %{})

# Enroll a student in a course
enroll_student(course_id, student_id)

# Unenroll a student from a course
unenroll_student(course_id, student_id)

# List students enrolled in a course
list_enrolled_students(course_id)

# List students not enrolled in a course
list_unenrolled_students(course_id)

# Check if a student is enrolled
enrolled?(course_id, student_id)
```

## Authorization

### Teacher Access
- Can only create courses for themselves
- Can only view/edit/delete their own courses
- Can manage enrollments for their courses
- Can manage tasks within their courses

### Student Access
- Can only view courses they're enrolled in
- Can only see published tasks
- Cannot modify course or enrollment data

### Admin Access
- Full access to all courses
- Can view courses from all teachers
- Cannot create courses (teachers must create their own)

## Task Status Behavior

Tasks have three statuses that affect student visibility:

- **draft** - Not visible to students (work in progress)
- **published** - Visible to all enrolled students
- **archived** - Not visible to students (completed/outdated)

Only published tasks appear on student course pages.

## Erweiterte Lerneinheiten (voluntary extensions)

Independently of its status, a learning unit carries an `extended` flag:

- **Basis-Lerneinheit** (`extended: false`, the default) — mandatory work.
- **Erweiterte Lerneinheit** (`extended: true`) — a voluntary extra for
  students who have enough time. It is offered, never required.

The flag is set when creating a unit and can be flipped afterwards via
"Bearbeiten" in the row's actions menu. It is copied when a unit or a whole
course is duplicated. Extended units are marked with a violet "Erweitert"
chip for teachers and an "Erweitert · freiwillig" chip for students, both on
the course timeline and in the unit itself.

### How it affects the progress bar

`Tasks.course_progress/1` is the single place this is computed:

- **100 % means all published mandatory units are done** — a student never
  needs an extension to reach a full bar.
- Completed extensions are reported separately as a `+N Erweiterungen` chip
  next to the bar.
- A unit counts as done from `completed` on; it does not have to be approved.
- A course made up of nothing but extensions reports 100 % and shows
  "Keine Pflichtaufgaben" instead of dividing by zero.
- **Locked** mandatory units stay in the denominator and cannot be completed,
  so the bar stays below 100 % while any of them is locked. This is
  pre-existing behaviour, deliberately left unchanged.
- The "Jetzt dran" pointer in the student timeline prefers mandatory units and
  only falls through to an extension once all mandatory work is done.

## Seed Data

The included seed file (`priv/repo/seeds.exs`) creates:

- 1 teacher account
- 3 student accounts
- 1 admin account
- 3 courses with descriptions
- Multiple tasks per course
- Various student enrollments

### Running Seeds

```bash
mix run priv/repo/seeds.exs
```

### Test Accounts

After running seeds, you can log in with:

- **Teacher:** teacher@example.com
- **Student1:** student1@example.com
- **Student2:** student2@example.com
- **Student3:** student3@example.com
- **Admin:** admin@example.com

## Migration

If you have existing tasks that were created before the course system:

1. Tasks can exist without a `course_id` (it's nullable)
2. You can manually assign tasks to courses by setting `course_id`
3. Consider creating a "General" or "Uncategorized" course for orphaned tasks

### Migrating Existing Tasks

```elixir
# In iex -S mix
alias Tasky.Repo
alias Tasky.Tasks.Task
alias Tasky.Courses.Course

# Create a default course
{:ok, general_course} = Tasky.Courses.create_course(scope, %{
  name: "General Tasks",
  description: "Tasks created before course system"
})

# Update orphaned tasks
from(t in Task, where: is_nil(t.course_id))
|> Repo.update_all(set: [course_id: general_course.id])
```

## Future Enhancements

Potential additions to the course system:

- Course categories/tags
- Course start/end dates
- Maximum enrollment limits
- Course completion tracking
- Bulk student enrollment (CSV import)
- Course archives
- Student progress reports per course
- Course-level announcements
- Course materials/resources section

## Troubleshooting

### Students can't see tasks

**Problem:** Student views empty task list despite being enrolled.

**Solutions:**
- Check task status - only "published" tasks are visible
- Verify student is actually enrolled in the course
- Ensure tasks have a `course_id` set

### Enrollment fails

**Problem:** Cannot enroll student in course.

**Solutions:**
- Check if student is already enrolled (unique constraint)
- Verify student has "student" role
- Ensure course exists and is accessible

### Teacher can't see their course

**Problem:** Course doesn't appear in teacher's course list.

**Solutions:**
- Verify `teacher_id` matches the logged-in user
- Check that course hasn't been deleted
- Ensure user has "teacher" or "admin" role

## Code Examples

### Creating a course with tasks programmatically

```elixir
# Get a teacher scope
teacher = Tasky.Accounts.get_user!(1)
scope = %Tasky.Accounts.Scope{user: teacher}

# Create course
{:ok, course} = Tasky.Courses.create_course(scope, %{
  name: "Phoenix LiveView Basics",
  description: "Learn LiveView from scratch"
})

# Add tasks
Tasky.Repo.insert!(%Tasky.Tasks.Task{
  name: "Setup LiveView Project",
  link: "https://example.com/setup",
  position: 1,
  status: "published",
  user_id: teacher.id,
  course_id: course.id
})

# Enroll students
student_ids = [2, 3, 4]
Enum.each(student_ids, fn student_id ->
  Tasky.Courses.enroll_student(course.id, student_id)
end)
```

### Querying course data

```elixir
# Get all published tasks for a course
course = Tasky.Repo.get!(Tasky.Courses.Course, 1)
|> Tasky.Repo.preload(:tasks)

published_tasks = Enum.filter(course.tasks, &(&1.status == "published"))

# Get all courses a student is enrolled in
student = Tasky.Repo.get!(Tasky.Accounts.User, 2)
|> Tasky.Repo.preload(:enrolled_courses)

courses = student.enrolled_courses

# Check enrollment
enrolled? = Tasky.Courses.enrolled?(course_id, student_id)
```

## Best Practices

1. **Always set task status appropriately**
   - Use "draft" while developing tasks
   - Only publish when ready for students
   - Archive when no longer relevant

2. **Provide clear course descriptions**
   - Help students understand what they'll learn
   - Include prerequisites if applicable
   - Mention expected time commitment

3. **Organize tasks by position**
   - Use position field for logical ordering
   - Consider 10, 20, 30... for easy reordering
   - Keep related tasks together

4. **Manage enrollments proactively**
   - Enroll students at course start
   - Remove students who drop
   - Check for enrollment issues

5. **Use meaningful course names**
   - Be specific and descriptive
   - Include level or difficulty if relevant
   - Consider naming conventions for multiple courses