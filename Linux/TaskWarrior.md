# Task Warrior

## Main Functionality

### Add Tasks
- Add task due daily with a completion date: `task add "Study for exams" due:eod recur:daily tag:study until:2025-07-25`
- Basic recurring task: `task add Work due:eod recur:daily tag:job`
- Add priority to tasks: Available options `H,M,L` and a task is as follows `task add vacuume4 priority:L`

### Complete Tasks
- One task: `task 54 done`
- Multiple tasks: `task 123 432 done`
- All expired tasks: `task +PENDING due.before:now done`

### Modify Tasks
`task 412 modify priority:H`
Works even for recurring

### Delete Tasks
`task 22 delete`

## Other

### Using Linux "WATCH" command
`watch task`
