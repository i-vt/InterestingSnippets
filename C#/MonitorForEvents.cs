using System;
using System.Diagnostics;

class EventLogMonitor
{
    static void Main()
    {
        string source = "InterestingEvent";
        string log = "Application";

        EventLog eventLog = new EventLog(log);
        eventLog.EntryWritten += new EntryWrittenEventHandler(OnEntryWritten);
        eventLog.EnableRaisingEvents = true;

        Console.WriteLine("Monitoring event log. Press 'Enter' to exit.");
        Console.ReadLine();
    }

    static void OnEntryWritten(object source, EntryWrittenEventArgs e)
    {
        if (e.Entry.Source == "InterestingEvent")
        {
            Console.WriteLine($"Event written: {e.Entry.Message}");
        }
    }
}
