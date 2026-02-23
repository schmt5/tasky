# Assigning Tasks to Students

## Overview

In Tasky, creating a task is only the first step. To make a task visible to students, you need to **assign** it to them.

## How It Works

1. **Teachers create tasks** - These are the assignments/activities
2. **Tasks must be assigned to students** - This creates "task submissions" for each student
3. **Students see their assigned tasks** - Only tasks with submissions appear in "My Tasks"

## Assigning Tasks (Teacher Workflow)

### Step 1: Create a Task

1. Go to **Tasks** in the navigation
2. Click **New Task**
3. Fill in task details (name, link, status, position)
4. Click **Save**

### Step 2: Assign Students to the Task

After creating a task, you need to assign it to students:

1. Click on the task to view details
2. Click **View Submissions**
3. Click the **Assign Students** button
4. Choose one of the following options:

#### Option A: Assign to All Students
- Click **Assign All** button
- This immediately assigns the task to all students in the system

#### Option B: Assign to Specific Students
- Check the boxes next to specific student names
- Click **Assign Selected** button
- Only the selected students will see this task

### Step 3: Students Can Now See the Task

Once assigned, students will:
- See the task in their **My Tasks** page
- Be able to mark it as "in progress"
- Be able to mark it as "completed"
- Receive grades and feedback from you

## Student Workflow

1. Go to **My Tasks** in the navigation
2. See all assigned tasks with their status
3. Click on a task to view details
4. Update task status as work progresses:
   - Not Started
   - In Progress
   - Completed

## Grading Workflow (Teacher)

1. Go to **Tasks** → select a task
2. Click **View Submissions**
3. See all students assigned to this task
4. For completed submissions, click **Grade**
5. Enter points (0-100) and feedback
6. Save the grade

Students will see their grade and feedback in their task view.

## Quick Tips

- **Task Status**: Set to "published" to indicate the task is active
- **Multiple Assignments**: You can assign the same task to students at different times
- **No Double Assignment**: Students can only be assigned once per task (duplicate assignments are automatically ignored)
- **Bulk Operations**: Use "Assign All" for quick class-wide assignments

## Command Line Alternative

If you need to assign tasks programmatically (for testing or bulk operations), you can use the Elixir console:

```elixir
# Get the teacher scope
teacher = Tasky.Accounts.get_user_by_email("teacher@example.com")
scope = Tasky.Accounts.Scope.for_user(teacher)

# Assign task to all students
task_id = 1
Tasky.Tasks.assign_task_to_all_students(scope, task_id)

# Or assign to specific students
student_ids = [2, 3, 4]
Tasky.Tasks.assign_task_to_students(scope, task_id, student_ids)
```

## Troubleshooting

**Problem**: Students can't see tasks I created
**Solution**: Make sure you've assigned the task to them using the "Assign Students" button

**Problem**: I don't see any students in the assign modal
**Solution**: Ensure you have students registered in the system with the "student" role

**Problem**: A student already assigned doesn't appear in the list
**Solution**: This is expected - the assign modal only shows unassigned students