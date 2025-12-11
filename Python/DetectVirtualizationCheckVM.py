import os
import platform
import subprocess
import uuid

VM_KEYWORDS = [
    "vmware", "virtualbox", "vbox", "kvm", "qemu",
    "hyper-v", "microsoft corporation", "xen"
]

def _contains_vm_keyword(s: str) -> bool:
    s = s.lower()
    return any(k in s for k in VM_KEYWORDS)

def check_cpu_flags() -> bool:
    """Check if CPU flags indicate a hypervisor (Linux / Unix-like)."""
    if not os.path.exists("/proc/cpuinfo"):
        return False
    try:
        with open("/proc/cpuinfo", "r") as f:
            data = f.read().lower()
        return "hypervisor" in data
    except Exception:
        return False

def check_dmi_linux() -> bool:
    """Check DMI product info on Linux."""
    dmi_paths = [
        "/sys/devices/virtual/dmi/id/product_name",
        "/sys/devices/virtual/dmi/id/product_version",
        "/sys/devices/virtual/dmi/id/sys_vendor",
        "/sys/devices/virtual/dmi/id/board_vendor",
    ]
    for path in dmi_paths:
        if os.path.exists(path):
            try:
                with open(path, "r") as f:
                    content = f.read().strip()
                if _contains_vm_keyword(content):
                    return True
            except Exception:
                pass
    return False

def check_mac_prefix() -> bool:
    """Check MAC address vendor prefixes known for VMs."""
    # Known prefixes (not exhaustive)
    vm_prefixes = {
        "00:05:69",  # VMware
        "00:0C:29",  # VMware
        "00:1C:14",  # VMware
        "00:50:56",  # VMware
        "08:00:27",  # VirtualBox
    }

    mac = uuid.getnode()
    mac_str = ":".join(f"{(mac >> ele) & 0xff:02x}" for ele in range(40, -1, -8))
    prefix = mac_str[:8].lower()
    return prefix in {p.lower() for p in vm_prefixes}

def is_vm() -> bool:
    system = platform.system().lower()

    indicators = []

    # Cross-ish
    indicators.append(check_mac_prefix())

    # Linux-specific
    if system == "linux":
        indicators.append(check_cpu_flags())
        indicators.append(check_dmi_linux())

    # Windows-specific checks will be added below; keep placeholder:
    if system == "windows":
        try:
            import wmi
            c = wmi.WMI()
            for cs in c.Win32_ComputerSystem():
                if _contains_vm_keyword(cs.Manufacturer or "") or _contains_vm_keyword(cs.Model or ""):
                    indicators.append(True)
        except ImportError:
            # wmi not installed, skip
            pass
        except Exception:
            pass

    return any(indicators)

if __name__ == "__main__":
    if is_vm():
        print("Likely running inside a virtual machine.")
    else:
        print("Likely running on bare metal (or detection failed).")
