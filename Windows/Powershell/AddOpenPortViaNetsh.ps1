netsh advfirewall firewall add rule name="Allow TCP 2020 In" dir=in action=allow protocol=TCP localport=2021
netsh advfirewall firewall add rule name="Allow TCP 2020 Out" dir=out action=allow protocol=TCP localport=2021
