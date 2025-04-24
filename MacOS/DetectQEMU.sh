/usr/bin/osascript <<EOF
set memData to do shell script "system_profiler SPMemoryDataType"
if memData contains "QEMU" or memData contains "VMware" then
    do shell script "exit 42"
else
    do shell script "exit 0"
end if
EOF
