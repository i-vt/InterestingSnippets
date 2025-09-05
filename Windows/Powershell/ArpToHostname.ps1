arp -a | ForEach-Object {
    if ($_ -match "(\d+\.\d+\.\d+\.\d+)") {
        $ip = $matches[1]
        try {
            $name = [System.Net.Dns]::GetHostEntry($ip).HostName
            "$ip`t$name"
        } catch {}
    }
}
