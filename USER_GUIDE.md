# Task Submission System - User Guide

## 🎓 Overview

This system allows teachers to assign tasks and students to complete them. Teachers can then review and grade student submissions.

## 👨‍🎓 Student Guide

### Getting Started

1. **Log in** to your account at `/users/log-in`
2. **Navigate to My Tasks** - Click "My Tasks" in the navigation bar

### Viewing Your Tasks

**My Tasks Page** (`/student/my-tasks`)

You'll see a list of all tasks assigned to you with:
- Task name and link
- Current status (Not Started, In Progress, Completed)
- Completion date (if completed)
- Your grade (if graded)
- Summary statistics at the bottom

### Working on a Task

**Step 1: Click "View"** on any task to see its details

**Step 2: Start the Task**
- When you first view a task, you'll see a "Start Task" button
- Click it to mark the task as "In Progress"
- This lets your teacher know you're working on it

**Step 3: Complete Your Work**
- Do the work required for the task
- Use the task link if provided
- When finished, click "Mark as Complete"

**Step 4: Wait for Grading**
- After completing, you'll see "Waiting for teacher to grade..."
- Your teacher will review and grade your submission

**Step 5: View Your Grade**
- Once graded, you'll see:
  - Your points (out of 100)
  - Teacher's feedback
  - Date graded

### Task Status Colors

- **Gray (Not Started)** - You haven't started yet
- **Yellow (In Progress)** - You're currently working on it
- **Green (Completed)** - You've submitted it for grading

### Tips for Students

✅ Start tasks early to avoid last-minute rushes
✅ Read task details carefully before starting
✅ Use the task link if your teacher provided one
✅ Check back regularly to see your grades
✅ Read feedback to improve on future tasks

## 👨‍🏫 Teacher Guide

### Getting Started

1. **Log in** to your account at `/users/log-in`
2. **Navigate to Tasks** - Click "Tasks" in the navigation bar

### Managing Tasks

**Tasks List Page** (`/tasks`)

- View all your created tasks
- Create new tasks with the "New Task" button
- Edit or delete existing tasks
- See task status (Draft, Published, Archived)
- Quick access to submissions via "View" link

### Creating a Task

1. Click "New Task" button
2. Fill in:
   - **Name** - Task title (required)
   - **Link** - Optional URL to external resources
   - **Position** - Sort order (optional)
   - **Status** - Draft, Published, or Archived
3. Click "Save Task"

### Viewing Task Details

**Task Show Page** (`/tasks/:id`)

You'll see:
- Complete task information
- Submission statistics:
  - Total students who have submissions
  - Number completed
  - Number graded
  - Number pending (completed but not graded)
- "View Submissions" button to see all students
- "Edit" button to modify task details

### Managing Submissions

**Submissions List** (`/tasks/:id/submissions`)

This page shows all student submissions for a task:

**Student Information:**
- Student name/email
- Avatar with initials
- Current submission status
- Completion date
- Current grade (if graded)
- Who graded it (if graded)

**Summary Statistics:**
- Total students with submissions
- Completed submissions
- Graded submissions
- Pending submissions (need grading)

**Actions:**
- **Grade** button - For completed, ungraded submissions
- **Edit Grade** button - For already graded submissions

### Grading a Submission

**Grade Page** (`/tasks/:task_id/grade/:id`)

1. Click "Grade" next to a completed submission
2. Review the submission details:
   - Student information
   - Task details and link
   - Completion date
   - Previous grade (if updating)
3. Enter grading information:
   - **Points** (0-100, required)
   - **Feedback** (optional, multi-line text)
4. Click "Save Grade"

**The system automatically tracks:**
- Who graded the submission (your user ID)
- When it was graded (timestamp)

### Updating Grades

If you need to change a grade:
1. Go to the submissions list
2. Click "Edit Grade" next to the student
3. Update points and/or feedback
4. Click "Update Grade"

The system preserves the grading history.

### Tips for Teachers

✅ Create tasks with clear, descriptive names
✅ Provide links to external resources when helpful
✅ Use Draft status while creating tasks
✅ Check submissions regularly to grade promptly
✅ Provide constructive feedback to help students improve
✅ Use the statistics to track class progress

## 🎨 Visual Reference

### Student Workflow

```
1. My Tasks List
   ┌─────────────────────────────────────┐
   │ My Tasks                            │
   │                                     │
   │ Task 1          [Not Started] [View]│
   │ Task 2          [In Progress] [View]│
   │ Task 3          [Completed]   [View]│
   │                                     │
   │ Stats: 3 Total | 1 Completed | 0 Graded
   └─────────────────────────────────────┘

2. Click "View" → Task Detail Page
   ┌─────────────────────────────────────┐
   │ Task Name                   [Back]  │
   │ Status: Not Started                 │
   │                                     │
   │ Task Details:                       │
   │ - Link: https://...                 │
   │ - Description here                  │
   │                                     │
   │ [Start Task]                        │
   └─────────────────────────────────────┘

3. After Starting
   ┌─────────────────────────────────────┐
   │ Task Name                   [Back]  │
   │ Status: In Progress                 │
   │                                     │
   │ [Mark as Complete]                  │
   └─────────────────────────────────────┘

4. After Completing
   ┌─────────────────────────────────────┐
   │ Task Name                   [Back]  │
   │ Status: Completed                   │
   │                                     │
   │ ⏰ Waiting for teacher to grade...  │
   └─────────────────────────────────────┘

5. After Teacher Grades
   ┌─────────────────────────────────────┐
   │ Task Name                   [Back]  │
   │ Status: Completed                   │
   │                                     │
   │ ✅ Your Grade: 95/100               │
   │                                     │
   │ Teacher Feedback:                   │
   │ "Excellent work! Your analysis      │
   │  was thorough and well-written."    │
   │                                     │
   │ Graded: Jan 15, 2024                │
   └─────────────────────────────────────┘
```

### Teacher Workflow

```
1. Tasks List
   ┌─────────────────────────────────────┐
   │ Listing Tasks          [+ New Task] │
   │                                     │
   │ Name      Status    Submissions     │
   │ Task 1    Published [View]          │
   │ Task 2    Draft     [View]          │
   │                                     │
   └─────────────────────────────────────┘

2. Click Task → Task Details
   ┌─────────────────────────────────────┐
   │ Task Name           [Back] [Edit]   │
   │                                     │
   │ Task Details: ...                   │
   │                                     │
   │ [View Submissions (3)]              │
   │                                     │
   │ Submission Statistics:              │
   │ 3 Total | 2 Completed | 1 Graded    │
   └─────────────────────────────────────┘

3. Click "View Submissions"
   ┌─────────────────────────────────────┐
   │ Submissions for Task Name   [Back]  │
   │                                     │
   │ Stats: 3 Total | 2 Completed |      │
   │        1 Graded | 1 Pending         │
   │                                     │
   │ Student     Status      Score  Actions
   │ student1@.. Completed   95    [Edit Grade]
   │ student2@.. Completed   -     [Grade]
   │ student3@.. In Progress -     Not ready
   │                                     │
   └─────────────────────────────────────┘

4. Click "Grade"
   ┌─────────────────────────────────────┐
   │ Grade Submission            [Back]  │
   │                                     │
   │ Student: student2@test.com          │
   │ Task: Task Name                     │
   │ Completed: Jan 15, 2024 10:30 AM    │
   │                                     │
   │ Points (0-100): [____]              │
   │                                     │
   │ Feedback (optional):                │
   │ [________________________]          │
   │ [________________________]          │
   │                                     │
   │ [Cancel]  [Save Grade]              │
   └─────────────────────────────────────┘

5. After Saving
   ┌─────────────────────────────────────┐
   │ ✅ Submission graded successfully!  │
   │                                     │
   │ Back to Submissions List            │
   │ (Stats updated: 2 Graded)           │
   └─────────────────────────────────────┘
```

## 🔐 Access Control

### Who Can Do What

| Action | Student | Teacher | Admin |
|--------|---------|---------|-------|
| View own tasks/submissions | ✅ | ✅ | ✅ |
| Complete tasks | ✅ | ❌ | ❌ |
| Create tasks | ❌ | ✅ | ✅ |
| View all submissions | ❌ | ✅ (own tasks) | ✅ (all) |
| Grade submissions | ❌ | ✅ (own tasks) | ✅ (all) |
| Edit tasks | ❌ | ✅ (own tasks) | ✅ (all) |
| Delete tasks | ❌ | ✅ (own tasks) | ✅ (all) |

### Privacy & Security

- **Students** can only see their own submissions
- **Teachers** can only see/grade submissions for tasks they created
- **Admins** have full access to everything
- All pages require authentication
- Role-based authorization enforced at router and context levels

## 📊 Understanding Statistics

### Student Stats (My Tasks Page)

- **Total Tasks** - How many task submissions you have
- **Completed** - How many you've marked as complete
- **Graded** - How many your teacher has graded

### Teacher Stats (Submissions Page)

- **Total Students** - Students who have submissions for this task
- **Completed** - Students who have finished the task
- **Graded** - Submissions you've already graded
- **Pending** - Completed submissions waiting for grades

## 🎯 Best Practices

### For Students

**DO:**
- ✅ Start tasks promptly when assigned
- ✅ Complete tasks before viewing your grade
- ✅ Read teacher feedback carefully
- ✅ Ask questions if task requirements are unclear
- ✅ Check your "My Tasks" page regularly

**DON'T:**
- ❌ Mark tasks complete before finishing the work
- ❌ Ignore teacher feedback
- ❌ Wait until the last minute
- ❌ Skip reading task details and links

### For Teachers

**DO:**
- ✅ Create clear, descriptive task names
- ✅ Provide helpful resource links
- ✅ Grade promptly after students complete tasks
- ✅ Give constructive feedback
- ✅ Use statistics to track class progress
- ✅ Update grades if you made a mistake

**DON'T:**
- ❌ Leave completed tasks ungraded for long periods
- ❌ Grade tasks that aren't marked complete
- ❌ Forget to provide feedback
- ❌ Use unclear or confusing task names
- ❌ Delete tasks that have student submissions

## 🆘 Getting Help

### Common Questions

**Q: I can't see any tasks**
A: Tasks must be created by a teacher. If you're a student and see no tasks, ask your teacher to create and publish tasks.

**Q: The "Start Task" button doesn't work**
A: Make sure you're logged in and have the student role. Try refreshing the page.

**Q: I completed a task but see no grade**
A: Your teacher hasn't graded it yet. You'll see "Waiting for teacher to grade..." until they review your work.

**Q: Can I undo marking a task as complete?**
A: Currently no. Once marked complete, it stays complete. Contact your teacher if you need to make changes.

**Q: Can I see other students' grades?**
A: No. Students can only see their own submissions and grades.

**Q: Can I grade my own tasks?**
A: No. Only teachers and admins can grade submissions.

**Q: What if I want to change a grade?**
A: Teachers can click "Edit Grade" on any graded submission to update the points and feedback.

**Q: Are grades out of 100?**
A: Yes. All grades are scored on a 0-100 point scale.

**Q: Is feedback required when grading?**
A: No. Feedback is optional but recommended to help students improve.

## 📱 Navigation Quick Reference

### Student Pages
- **My Tasks**: `/student/my-tasks` - See all your task submissions
- **Task Detail**: `/student/tasks/:id` - View and complete a specific task

### Teacher Pages
- **Tasks List**: `/tasks` - Manage all your tasks
- **Task Detail**: `/tasks/:id` - View task with statistics
- **Submissions**: `/tasks/:id/submissions` - See all student submissions
- **Grade**: `/tasks/:task_id/grade/:id` - Grade a specific submission

### Common Pages
- **Login**: `/users/log-in` - Sign in to your account
- **Register**: `/users/register` - Create a new account
- **Settings**: `/users/settings` - Update your profile
- **Logout**: Click "Log out" in user menu

## 🎨 Status Badge Colors

Understanding the visual indicators:

### Submission Status
- 🔵 **Blue (Published)** - Task is published and active
- ⚪ **Gray (Draft)** - Task is still being created
- 🔴 **Red (Archived)** - Task is no longer active

### Student Progress
- ⚪ **Gray (Not Started)** - Student hasn't begun
- 🟡 **Yellow (In Progress)** - Student is working on it
- 🟢 **Green (Completed)** - Student has submitted

## ✨ Tips & Tricks

### For Students
- Use the task link to access required materials
- Check "My Tasks" regularly for new assignments
- Read feedback to understand how to improve
- Contact your teacher if you have questions about a task

### For Teachers
- Use the statistics to identify students who need help
- Grade completed submissions promptly
- Provide specific, actionable feedback
- Use "Draft" status while creating tasks to avoid confusion
- Check the submissions page to see who's falling behind

## 🎉 Success Stories

### Example Student Journey

**Monday:** Teacher creates "Essay Assignment"
**Tuesday:** Student sees it in "My Tasks", clicks "View"
**Wednesday:** Student clicks "Start Task", begins writing
**Thursday:** Student completes essay, clicks "Mark as Complete"
**Friday:** Teacher reviews, grades 92/100 with feedback
**Weekend:** Student checks "My Tasks", sees grade and feedback!

### Example Teacher Journey

**Start of Week:** Create new task "Chapter 5 Questions"
**Mid-Week:** Check submissions page, see 3 students completed
**End of Week:** Grade all 3 submissions with feedback
**Next Week:** Use statistics to identify students who haven't started

---

**Need more help?** Contact your system administrator or refer to the technical documentation in `SUBMISSION_UI_COMPLETE.md`.