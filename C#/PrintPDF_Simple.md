https://stackoverflow.com/questions/5566186/print-pdf-in-c-sharp
```
 Process p = new Process( );
p.StartInfo = new ProcessStartInfo( )
{
    CreateNoWindow = true,
    Verb = "print",
    FileName = path //put the correct path here
};
p.Start( );
```
