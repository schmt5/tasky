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

### Adding Tasks to a Course (Teacher)

1. Navigate to the course detail page (`/courses/:id`)
2. Click "Add Task" in the Tasks section
3. Fill in task details:
   - Name (required)
   - Link (required)
   - Position (required)
   - Status (draft/published/archived)
4. Click "Save Task"

**Note:** Tasks are automatically associated with the course.

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
- Course cloning/templates
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