using System;
using System.Diagnostics;

class EventLogExample
{
    static void Main()
    {
        string source = "AaaaaAaaaaaa";
        string log = "Application";
        string eventText = "MMmmm. Hello:))";

        if (!EventLog.SourceExists(source))
        {
            EventLog.CreateEventSource(source, log);
        }

        EventLog.WriteEntry(source, eventText, EventLogEntryType.Warning);
    }
}
