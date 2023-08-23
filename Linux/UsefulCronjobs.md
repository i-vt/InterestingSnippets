# Auto updates
(Requires sudo crontab -e)
```
0 */6 * * * apt update; apt dist-upgrade -y; apt-get autoremove -y
```
