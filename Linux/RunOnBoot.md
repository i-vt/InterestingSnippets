# Auto-Start a Program on Linux Boot or Logon with High Privileges

To automatically execute a program during system **boot** or **user logon** on a **Linux** system with **root privileges**, you can use the following methods:

---

## 1. Using `systemd` (Recommended for boot-time execution)

### Step-by-step:

1. **Create a systemd service file:**
   ```bash
   sudo nano /etc/systemd/system/myprogram.service
   ```

2. **Add the following content:**
   ```ini
   [Unit]
   Description=My Program Startup
   After=network.target

   [Service]
   ExecStart=/path/to/your/program
   Restart=always
   User=root

   [Install]
   WantedBy=multi-user.target
   ```

3. **Enable and start the service:**
   ```bash
   sudo systemctl daemon-reexec        # Optional: refresh systemd itself
   sudo systemctl daemon-reload        # Reload systemd units
   sudo systemctl enable myprogram.service
   sudo systemctl start myprogram.service
   ```

---

## 2. Using `cron` with `@reboot` (Simple method)

### Step-by-step:

1. **Edit root’s crontab:**
   ```bash
   sudo crontab -e
   ```

2. **Add this line:**
   ```bash
   @reboot /path/to/your/program
   ```

> This will execute the program as **root** every time the system reboots.

---

## 3. Using `/etc/rc.local` (Legacy method)

> Only works on systems that still support `rc.local`.

### Step-by-step:

1. **Edit the file:**
   ```bash
   sudo nano /etc/rc.local
   ```

2. **Add your command before `exit 0`:**
   ```bash
   /path/to/your/program &
   ```

3. **Make the script executable:**
   ```bash
   sudo chmod +x /etc/rc.local
   ```

---

## 4. Run on User Login (GUI or Terminal)

### Option A: `.bash_profile` or `.profile`

Add your command to the user’s profile script:
```bash
sudo /path/to/your/program
```

### Option B: `sudoers` + NOPASSWD

1. **Add sudo permission without password:**
   ```bash
   sudo visudo -f /etc/sudoers.d/myscript
   ```

   Add this line:
   ```
   yourusername ALL=(ALL) NOPASSWD: /path/to/your/program
   ```

2. **Then call in login script:**
   ```bash
   sudo /path/to/your/program
   ```


