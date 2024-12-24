Get-WmiObject MSAcpi_ThermalZoneTemperature -Namespace "root\WMI" | ForEach-Object {
    [Math]::Round(($_.CurrentTemperature - 2732) / 10.0, 1)
}
# Crashes when VM, providing a temp as number (C)
# works great on baremetal
