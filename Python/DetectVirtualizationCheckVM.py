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

def check_cpu_flags():
    """Check if CPU flags indicate a hypervisor (Linux / Unix-like)."""
    if not os.path.exists("/proc/cpuinfo"):
        return False, "cpuinfo missing"

    try:
        with open("/proc/cpuinfo", "r") as f:
            data = f.read().lower()
        detected = "hypervisor" in data
        return detected, "cpu flags contain 'hypervisor'" if detected else "no hypervisor flag"
    except Exception as e:
        return False, f"cpuinfo read error: {e}"

def check_dmi_linux():
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
                    return True, f"DMI match: {path} = '{content}'"
            except Exception as e:
                return False, f"DMI read error: {e}"

    return False, "no DMI entries matched"

def check_mac_prefix():
    """Check MAC address vendor prefixes known for VMs."""
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

    detected = prefix in {p.lower() for p in vm_prefixes}
    return detected, f"MAC prefix {prefix} {'matches VM vendor' if detected else 'not recognized'}"

def is_vm(debug=False):
    system = platform.system().lower()
    debug_info = {}

    # MAC detection
    mac_result, mac_info = check_mac_prefix()
    debug_info["mac_prefix"] = mac_info

    indicators = [mac_result]

    # Linux-specific
    if system == "linux":
        cpu_result, cpu_info = check_cpu_flags()
        dmi_result, dmi_info = check_dmi_linux()

        indicators.extend([cpu_result, dmi_result])

        debug_info["cpu_flags"] = cpu_info
        debug_info["dmi"] = dmi_info

    # Windows-specific
    if system == "windows":
        try:
            import wmi
            c = wmi.WMI()
            vm_detected = False
            for cs in c.Win32_ComputerSystem():
                if (_contains_vm_keyword(cs.Manufacturer or "") or
                        _contains_vm_keyword(cs.Model or "")):
                    vm_detected = True
                    debug_info["wmi"] = f"Manufacturer/Model matched ({cs.Manufacturer}, {cs.Model})"
                    break
            indicators.append(vm_detected)
            if not vm_detected:
                debug_info["wmi"] = "no VM indicators in WMI"
        except Exception as e:
            debug_info["wmi"] = f"WMI check error: {e}"

    is_virtual = any(indicators)

    if debug:
        return is_virtual, debug_info
    else:
        return is_virtual

if __name__ == "__main__":
    result, info = is_vm(debug=True)

    print("VM DETECTED:" if result else "No VM detected.")
    print("--- Debug Info ---")
    for key, value in info.items():
        print(f"{key}: {value}")
