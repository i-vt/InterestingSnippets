using System;
using Microsoft.Win32.TaskScheduler;

namespace TaskSchedulerExample
{
    class Program
    {
        static void Main(string[] args)
        {
            // Check for the correct number of arguments
            if(args.Length != 2)
            {
                Console.WriteLine("Usage: cliTaskScheduler.exe [jobPath] [timeToRun]");
                Console.WriteLine("Example: cliTaskScheduler.exe C:\\backup\\backup.exe 1:00:00");
                return;
            }

            string jobPath = args[0];
            string timeToRun = args[1];

            // Validate jobPath and timeToRun here, if necessary...
            
            try
            {
                using (TaskService ts = new TaskService())
                {
                    TaskDefinition td = ts.NewTask();
                    td.RegistrationInfo.Description = "MyTaskDescription";

                    // Setting the task to run with the highest privileges
                    td.Principal.RunLevel = TaskRunLevel.Highest;
                    
                    // Trying to parse the time to run and create a trigger
                    if(TimeSpan.TryParse(timeToRun, out TimeSpan triggerTime))
                    {
                        td.Triggers.Add(new TimeTrigger { StartBoundary = DateTime.Now + triggerTime });
                    }
                    else
                    {
                        Console.WriteLine("Invalid time format.");
                        return;
                    }
                    
                    td.Actions.Add(new ExecAction(jobPath, null, null));
                    
                    ts.RootFolder.RegisterTaskDefinition(@"MyTask", td);
                    
                    Console.WriteLine("Task scheduled successfully!");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"An error occurred: {ex.Message}");
            }
        }
    }
}
