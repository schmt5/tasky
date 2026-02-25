# Quick Test Guide for Course Feature

## ✅ Verification: Routes ARE Implemented

The course routes are fully implemented and working. Here's how to test:

## Step-by-Step Testing

### 1. Start the Server

```bash
mix phx.server
```

The server should start on http://localhost:4000

### 2. Verify Routes Exist

Run this command to see all course routes:

```bash
mix phx.routes | grep course
```

You should see:
```
GET     /courses                               TaskyWeb.CourseLive.Index :index
GET     /courses/new                           TaskyWeb.CourseLive.Form :new
GET     /courses/:id                           TaskyWeb.CourseLive.Show :show
GET     /courses/:id/edit                      TaskyWeb.CourseLive.Form :edit
GET     /student/courses                       TaskyWeb.Student.CoursesLive :index
GET     /student/courses/:id                   TaskyWeb.Student.CourseLive :show
```

### 3. Test as Teacher

1. **Navigate to login**: http://localhost:4000/users/log-in
2. **Enter email**: `teacher@example.com`
3. **Check mailbox**: Go to http://localhost:4000/dev/mailbox
4. **Click the magic link** in the email
5. **Go to courses**: http://localhost:4000/courses
6. **You should see**:
   - 3 courses displayed in a grid
   - "Introduction to Programming"
   - "Web Development Fundamentals"
   - "Database Design"

#### Test Course Management

- **Create new course**: Click "New Course" button
- **Edit course**: Click "Edit" on any course card
- **View course**: Click on a course card to see details
- **Add tasks**: In course detail, click "Add Task"
- **Enroll students**: Click "Enroll Students" to see modal

### 4. Test as Student

1. **Log out**: Click log out in the menu
2. **Login as student**: Use `student1@example.com`
3. **Go to student courses**: http://localhost:4000/student/courses
4. **You should see**: 
   - 2 courses (student1 is enrolled in "Introduction to Programming" and "Web Development Fundamentals")
5. **Click on a course** to see all published tasks

### 5. Verify Database

Check that data exists:

```bash
mix run -e "IO.inspect(Tasky.Repo.aggregate(Tasky.Courses.Course, :count))"
# Should output: 3

mix run -e "IO.inspect(Tasky.Repo.aggregate(Tasky.Courses.CourseEnrollment, :count))"
# Should output: 6
```

## Expected Behaviors

### Teacher View (`/courses`)
✅ Grid of course cards
✅ "New Course" button in header
✅ Each card shows: name, description, teacher email, task count
✅ Edit and Delete buttons on each card
✅ Click card to go to course detail page

### Course Detail Page (`/courses/:id`)
✅ Course name and description at top
✅ "Edit Course" and "Back to Courses" buttons
✅ Tasks section with inline add form
✅ Students section with enroll/unenroll functionality
✅ Modal for enrolling new students

### Student View (`/student/courses`)
✅ Grid of enrolled courses only
✅ Cannot see courses they're not enrolled in
✅ Each card shows course info
✅ Click to view course tasks

### Student Course Detail (`/student/courses/:id`)
✅ Course name and description
✅ Only shows "published" tasks (not draft or archived)
✅ Shows completion status for each task
✅ Link to view individual tasks

## Troubleshooting

### "Route not found" error
- **Cause**: Server not running
- **Fix**: Run `mix phx.server`

### "You must log in to access this page"
- **Cause**: Not authenticated (this is correct!)
- **Fix**: Log in with one of the test accounts

### Empty course list
- **Cause**: Seed data not loaded
- **Fix**: Run `mix run priv/repo/seeds.exs`

### "not implemented" error on streams
- **Cause**: Fixed in latest code
- **Fix**: Make sure you have the latest changes compiled with `mix compile --force`

## Test Accounts

All accounts use magic link authentication (no passwords):

- **Teacher**: teacher@example.com
- **Student 1**: student1@example.com (enrolled in courses 1 & 2)
- **Student 2**: student2@example.com (enrolled in courses 1 & 3)
- **Student 3**: student3@example.com (enrolled in courses 2 & 3)
- **Admin**: admin@example.com

## Quick Verification Script

Run this to verify everything:

```bash
mix run verify_courses.exs
```

This will check:
- ✅ Routes are registered
- ✅ LiveView modules are loaded
- ✅ Database tables exist
- ✅ Seed data is present

## Conclusion

**The course routes ARE implemented!** 

If you see a redirect to login when accessing `/courses`, that's the correct behavior - the route exists and is working, it just requires authentication.