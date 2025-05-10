$total_physical_memory = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
$free_physical_memory = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
$used_physical_memory = $total_physical_memory - $free_physical_memory
if ($total_physical_memory -lt 4 -or $used_physical_memory -lt 1.5) {
	exit 0
}
