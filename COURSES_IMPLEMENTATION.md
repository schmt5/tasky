# Course Feature Implementation Summary

## What Was Built

A complete course management system that allows teachers to organize tasks into courses and assign students to courses rather than individual tasks.

## Key Changes

### Database Migrations

1. **courses table** - Stores course information (name, description, teacher_id)
2. **course_id added to tasks** - Links tasks to courses (nullable for backward compatibility)
3. **course_enrollments table** - Join table for student-course relationships

### New Schemas

- `Tasky.Courses.Course` - Course schema with relationships
- `Tasky.Courses.CourseEnrollment` - Enrollment join schema
- Updated `Tasky.Tasks.Task` - Added course relationship
- Updated `Tasky.Accounts.User` - Added course relationships

### New Context

`Tasky.Courses` - Complete CRUD operations for courses plus enrollment management:
- `list_courses/1` - List courses by role (teacher sees own, admin sees all)
- `list_enrolled_courses/1` - List courses a student is enrolled in
- `get_course!/2` - Get course with authorization
- `get_course_for_student!/2` - Get course for enrolled student only
- `create_course/2` - Create course with scope
- `update_course/2` - Update course
- `delete_course/1` - Delete course
- `enroll_student/2` - Enroll student in course
- `unenroll_student/2` - Remove student from course
- `list_enrolled_students/1` - Get all students in a course
- `list_unenrolled_students/1` - Get students not in a course
- `enrolled?/2` - Check enrollment status

### LiveView Components

**Teacher/Admin Views:**
- `TaskyWeb.CourseLive.Index` - Grid view of courses with create/edit/delete
- `TaskyWeb.CourseLive.Form` - Create/edit course form
- `TaskyWeb.CourseLive.Show` - Course detail with task management and student enrollment
  - Inline task creation form
  - Task list with edit/delete
  - Enrolled students list
  - Modal for enrolling new students

**Student Views:**
- `TaskyWeb.Student.CoursesLive` - Grid view of enrolled courses
- `TaskyWeb.Student.CourseLive` - Course detail showing published tasks with completion status

### Router Updates

**Teacher/Admin routes** (in `:tasks` live_session):
```elixir
live "/courses", CourseLive.Index, :index
live "/courses/new", CourseLive.Form, :new
live "/courses/:id", CourseLive.Show, :show
live "/courses/:id/edit", CourseLive.Form, :edit
```

**Student routes** (in `:student` live_session):
```elixir
live "/courses", CoursesLive, :index
live "/courses/:id", CourseLive, :show
```

## How It Works

### For Teachers

1. **Create a course** - Navigate to `/courses` and click "New Course"
2. **Add tasks to course** - In course detail page, click "Add Task" to create tasks inline
3. **Enroll students** - Click "Enroll Students" to see modal with available students
4. **Manage enrollments** - Unenroll students as needed

### For Students

1. **View enrolled courses** - Navigate to `/student/courses` to see all courses
2. **Access course tasks** - Click on a course to see all published tasks
3. **Complete tasks** - Tasks show completion status and link to task detail

### Key Features

- **Authorization**: Teachers only see/manage their courses, students only see enrolled courses
- **Task Status**: Only "published" tasks visible to students (draft/archived hidden)
- **Automatic Access**: Students enrolled in a course automatically see all its tasks
- **Cascading Deletes**: Deleting a course deletes all tasks and enrollments
- **Many-to-Many**: Students can be in multiple courses, courses can have multiple students

## Seed Data Included

Run `mix run priv/repo/seeds.exs` to create:
- 1 teacher, 3 students, 1 admin
- 3 courses with descriptions
- 9 tasks across courses (various statuses)
- Multiple student enrollments

**Test accounts:**
- teacher@example.com
- student1@example.com
- student2@example.com
- student3@example.com
- admin@example.com

## Migration Path for Existing Data

The `course_id` field on tasks is nullable, so existing tasks continue to work. To migrate:

1. Create a "General" course for orphaned tasks
2. Update tasks without course_id to point to the general course
3. Or leave them as-is (they won't appear in course views)

## What's Different from Before

**Before:** 
- Tasks existed independently
- No way to group/organize tasks
- Teachers had to manage individual task assignments

**After:**
- Tasks are organized within courses
- Students are enrolled at the course level
- One enrollment gives access to all course tasks
- Better organization and scalability