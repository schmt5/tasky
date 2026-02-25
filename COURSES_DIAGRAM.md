# Course System Relationship Diagram

## Entity Relationship Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Course System Architecture                       │
└─────────────────────────────────────────────────────────────────────────┘

┌──────────────┐
│    User      │
│──────────────│
│ id           │
│ email        │
│ role         │◄─────────┐
│  - teacher   │          │
│  - student   │          │
│  - admin     │          │
└──────┬───────┘          │
       │                  │
       │ has_many         │ belongs_to (teacher_id)
       │ taught_courses   │
       │                  │
       ▼                  │
┌──────────────┐          │
│   Course     │──────────┘
│──────────────│
│ id           │
│ name         │◄─────────────────┐
│ description  │                  │
│ teacher_id   │                  │
└──────┬───────┘                  │
       │                          │
       │ has_many                 │ belongs_to
       │ tasks                    │ (course_id)
       │                          │
       ▼                          │
┌──────────────┐                  │
│    Task      │──────────────────┘
│──────────────│
│ id           │
│ name         │
│ link         │
│ position     │
│ status       │
│ user_id      │
│ course_id    │ (nullable)
└──────────────┘


┌──────────────────────────────────────────────────────────────────────────┐
│                      Many-to-Many Enrollment                              │
└──────────────────────────────────────────────────────────────────────────┘

┌──────────────┐         ┌────────────────────┐         ┌──────────────┐
│    User      │         │ CourseEnrollment   │         │   Course     │
│  (Student)   │◄───────►│  (Join Table)      │◄───────►│              │
│──────────────│  many   │────────────────────│  many   │──────────────│
│ id           │         │ id                 │         │ id           │
│ email        │         │ course_id          │         │ name         │
│ role         │         │ student_id         │         │ teacher_id   │
└──────────────┘         │ inserted_at        │         └──────────────┘
                         │ updated_at         │
                         └────────────────────┘
                         Unique: [course_id, student_id]
```

## Access Flow Diagrams

### Teacher Workflow

```
┌─────────────┐
│   Teacher   │
│  Logs In    │
└──────┬──────┘
       │
       ▼
┌──────────────────┐
│  View Courses    │
│  /courses        │
└──────┬───────────┘
       │
       ├───► Create New Course ──────┐
       │                              │
       └───► Select Course ───────────┤
                                      │
                                      ▼
                            ┌──────────────────┐
                            │  Course Detail   │
                            │  /courses/:id    │
                            └────────┬─────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
                    ▼                ▼                ▼
            ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
            │  Add/Edit    │ │   Enroll     │ │  View/Edit   │
            │   Tasks      │ │  Students    │ │    Course    │
            └──────────────┘ └──────────────┘ └──────────────┘
```

### Student Workflow

```
┌─────────────┐
│   Student   │
│  Logs In    │
└──────┬──────┘
       │
       ▼
┌────────────────────┐
│ View Enrolled      │
│    Courses         │
│ /student/courses   │
└──────┬─────────────┘
       │
       │ Only shows courses
       │ student is enrolled in
       │
       ▼
┌────────────────────┐
│  Select Course     │
└──────┬─────────────┘
       │
       ▼
┌────────────────────────┐
│   Course Detail        │
│ /student/courses/:id   │
└──────┬─────────────────┘
       │
       │ Shows only
       │ "published" tasks
       │
       ▼
┌────────────────────────┐
│  View Published Tasks  │
│  + Completion Status   │
└──────┬─────────────────┘
       │
       ▼
┌────────────────────────┐
│   Click on Task        │
│  /student/tasks/:id    │
└────────────────────────┘
```

## Data Flow Example

### Scenario: Teacher Creates Course and Enrolls Students

```
Step 1: Create Course
─────────────────────
Teacher (id: 1) creates "Web Dev 101"
  ↓
Course created:
  - id: 1
  - name: "Web Dev 101"
  - teacher_id: 1
  - description: "Learn web development"


Step 2: Add Tasks to Course
───────────────────────────
Teacher adds tasks:
  ↓
Task 1:
  - name: "HTML Basics"
  - course_id: 1
  - status: "published"
  
Task 2:
  - name: "CSS Styling"
  - course_id: 1
  - status: "published"
  
Task 3:
  - name: "JavaScript Advanced"
  - course_id: 1
  - status: "draft"  ← NOT visible to students


Step 3: Enroll Students
──────────────────────
Teacher enrolls students:
  ↓
CourseEnrollment 1:
  - course_id: 1
  - student_id: 2
  
CourseEnrollment 2:
  - course_id: 1
  - student_id: 3


Step 4: Student Access
─────────────────────
Student 2 logs in:
  ↓
Sees "Web Dev 101" in their courses
  ↓
Clicks on course
  ↓
Sees 2 tasks (HTML Basics, CSS Styling)
  ↓
Does NOT see "JavaScript Advanced" (draft)
```

## Authorization Matrix

```
┌──────────────┬───────────┬──────────┬─────────┐
│   Action     │  Teacher  │ Student  │  Admin  │
├──────────────┼───────────┼──────────┼─────────┤
│ Create       │ Own Only  │    ✗     │    ✗    │
│ Course       │           │          │         │
├──────────────┼───────────┼──────────┼─────────┤
│ View         │ Own Only  │ Enrolled │   All   │
│ Course       │           │   Only   │         │
├──────────────┼───────────┼──────────┼─────────┤
│ Edit         │ Own Only  │    ✗     │   All   │
│ Course       │           │          │         │
├──────────────┼───────────┼──────────┼─────────┤
│ Delete       │ Own Only  │    ✗     │   All   │
│ Course       │           │          │         │
├──────────────┼───────────┼──────────┼─────────┤
│ Add Tasks    │ Own Only  │    ✗     │  Own    │
│              │           │          │  Only   │
├──────────────┼───────────┼──────────┼─────────┤
│ Enroll       │ Own Only  │    ✗     │  Any    │
│ Students     │           │          │ Course  │
├──────────────┼───────────┼──────────┼─────────┤
│ View Tasks   │    All    │Published │   All   │
│              │           │   Only   │         │
└──────────────┴───────────┴──────────┴─────────┘
```

## Task Status Visibility

```
┌────────────────┬──────────┬─────────┐
│  Task Status   │ Teacher  │ Student │
├────────────────┼──────────┼─────────┤
│ draft          │    ✓     │    ✗    │
├────────────────┼──────────┼─────────┤
│ published      │    ✓     │    ✓    │
├────────────────┼──────────┼─────────┤
│ archived       │    ✓     │    ✗    │
└────────────────┴──────────┴─────────┘
```

## Key Benefits

```
Before Courses:
┌───────────┐    ┌───────────┐    ┌───────────┐
│  Task 1   │    │  Task 2   │    │  Task 3   │
└─────┬─────┘    └─────┬─────┘    └─────┬─────┘
      │                │                │
      └────────────────┴────────────────┘
                       │
              Each task assigned
              to students individually
              (management nightmare)


After Courses:
┌─────────────────────────────────────────┐
│             Course                      │
│  ┌───────────┐  ┌───────────┐         │
│  │  Task 1   │  │  Task 2   │  ...    │
│  └───────────┘  └───────────┘         │
└────────────┬────────────────────────────┘
             │
    One enrollment gives
    access to all tasks
    (much easier!)
```
