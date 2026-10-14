Option Explicit
Dim service, name, rows, row, count
Set service = GetObject("winmgmts:\\.\root\cimv2")
For Each name In Array("Win32_TimeZone", "Win32_VideoController", "Win32_BIOS")
    Set rows = service.ExecQuery("SELECT * FROM " & name)
    count = 0
    For Each row In rows
        count = count + 1
    Next
    WScript.Echo name & ": " & count
    If count < 1 Then WScript.Quit 1
Next
WScript.Quit 0
