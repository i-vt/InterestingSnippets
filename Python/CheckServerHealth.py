import os
import shutil
import platform
import socket
import time
import subprocess

def get_cpu_load_status():
    try:
        load = os.getloadavg()  # (1, 5, 15 min)
        cores = os.cpu_count()
        status = all(l <= cores for l in load)
        return {
            "load_1_5_15": tuple(round(l, 3) for l in load),
            "cpu_cores": cores,
            "status": "Healthy" if status else "Overloaded"
        }
    except (AttributeError, OSError):
        return {"error": "CPU load not available on this OS"}

def get_disk_usage(path="/"):
    total, used, free = shutil.disk_usage(path)
    return {
        "total_GB": round(total / (1024 ** 3), 2),
        "used_GB": round(used / (1024 ** 3), 2),
        "free_GB": round(free / (1024 ** 3), 2),
        "usage_percent": round((used / total) * 100, 2)
    }

def get_memory_usage():
    try:
        with open('/proc/meminfo') as f:
            meminfo = {line.split(':')[0]: int(line.split()[1]) for line in f if ':' in line}
        total = meminfo['MemTotal']
        free = meminfo['MemFree'] + meminfo.get('Buffers', 0) + meminfo.get('Cached', 0)
        used = total - free
        return {
            "total_MB": round(total / 1024, 2),
            "used_MB": round(used / 1024, 2),
            "free_MB": round(free / 1024, 2),
            "usage_percent": round((used / total) * 100, 2)
        }
    except Exception as e:
        return {"error": str(e)}

def get_uptime():
    try:
        with open('/proc/uptime') as f:
            uptime_seconds = float(f.readline().split()[0])
        return time.strftime("%H:%M:%S", time.gmtime(uptime_seconds))
    except Exception:
        return "Unavailable"

def check_network(host="8.8.8.8"):
    try:
        subprocess.check_output(["ping", "-c", "1", "-W", "1", host], stderr=subprocess.DEVNULL)
        return "Online"
    except subprocess.CalledProcessError:
        return "Offline"

def get_os_info():
    return {
        "system": platform.system(),
        "release": platform.release(),
        "version": platform.version(),
        "hostname": socket.gethostname()
    }

def health_check():
    return {
        "OS Info": get_os_info(),
        "Uptime": get_uptime(),
        "CPU Load": get_cpu_load_status(),
        "Disk Usage": get_disk_usage(),
        "Memory Usage": get_memory_usage(),
        "Network": check_network()
    }

if __name__ == "__main__":
    from pprint import pprint
    pprint(health_check())
