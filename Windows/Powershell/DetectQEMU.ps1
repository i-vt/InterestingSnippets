$manufacturer = gwmi Win32_ComputerSystem | select -ExpandProperty Manufacturer
if ($manufacturer -eq "QEMU") {
	exit 0;
}
