Sub RunProgram()
    Dim shell As Object
    Set shell = CreateObject("WScript.Shell")
    
    ' Open Calculator
    shell.Run "calc.exe"
End Sub
