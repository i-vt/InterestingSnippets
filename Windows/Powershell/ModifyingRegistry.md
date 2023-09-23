Change an existing registry key value:
```
$path = "HKCU:\Software\SampleKey"
$name = "SampleName"
$value = "NewValue"
Set-ItemProperty -Path $path -Name $name -Value $value
```

Add a new registry key value:
```
$path = "HKCU:\Software\SampleKey"
$name = "NewKeyName"
$value = "NewValue"
New-ItemProperty -Path $path -Name $name -Value $value -PropertyType "String"
# Note: -PropertyType can be "String", "ExpandString", "Binary", "DWord", "MultiString", "QWord", or "Unknown".
```

Delete a registry key value:
```
$path = "HKCU:\Software\SampleKey"$name = "KeyNameToDelete"
Remove-ItemProperty -Path $path -Name $name
```

Create a new registry key:
```
$path = "HKCU:\Software"
$newKey = "NewSampleKey"
New-Item -Path $path -Name $newKey
```

Delete a registry key:
```
$path = "HKCU:\Software\SampleKeyToDelete"
Remove-Item -Path $path -Recurse
```
