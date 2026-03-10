#include <windows.h>
#include <tlhelp32.h>
#include <sddl.h>
#include <iostream>
#include <string>
#include <vector>
#include <sstream>

// x86_64-w64-mingw32-g++ HandleScanner.cpp -o handles.exe -static -s -ladvapi32

struct RT_AccessRule {
    DWORD access;
    const char* name;
    const char* reason;
    int score;
};

struct RT_ProcessInfo {
    std::string name;
    DWORD pid;
    std::string owner;
    std::string integrity;
    std::string arch;
    DWORD sessionId;
    bool canVmWrite;
    bool canVmOperation;
    bool canCreateThread;
    bool canDupHandle;
    bool canQueryInfo;
    bool canAllAccess;
    bool injectionCapable;
    bool privescWorthy;
    int score;
    std::vector<std::string> enabledPrivs;
};

static RT_AccessRule g_rules[] = {
    { PROCESS_VM_WRITE,          "PROCESS_VM_WRITE",          "Write shellcode into remote memory", 3 },
    { PROCESS_VM_OPERATION,      "PROCESS_VM_OPERATION",      "Allocate/change remote memory", 3 },
    { PROCESS_CREATE_THREAD,     "PROCESS_CREATE_THREAD",     "Start remote thread", 4 },
    { PROCESS_DUP_HANDLE,        "PROCESS_DUP_HANDLE",        "Duplicate handles from target", 2 },
    { PROCESS_QUERY_INFORMATION, "PROCESS_QUERY_INFORMATION", "Query process information", 1 },
    { PROCESS_ALL_ACCESS,        "PROCESS_ALL_ACCESS",        "Full process control", 6 }
};

static bool NameEq(const char* a, const char* b) {
    return _stricmp(a, b) == 0;
}

static bool IsServiceLikeTarget(const char* name) {
    const char* targets[] = {
        "svchost.exe",
        "services.exe",
        "winlogon.exe",
        "wininit.exe",
        "spoolsv.exe",
        "dllhost.exe",
        "taskhostw.exe",
        "wmiprvse.exe",
        "trustedinstaller.exe",
        "expressvpn.systemservice.exe",
        "expressvpn.vpnservice.exe",
        "expressvpnnotificationservice.exe"
    };

    for (size_t i = 0; i < sizeof(targets) / sizeof(targets[0]); i++) {
        if (NameEq(name, targets[i])) {
            return true;
        }
    }
    return false;
}

static bool IsUserStableTarget(const char* name) {
    const char* targets[] = {
        "explorer.exe",
        "runtimebroker.exe",
        "searchapp.exe",
        "startmenuexperiencehost.exe",
        "firefox.exe",
        "msedgewebview2.exe",
        "notepad.exe",
        "cmd.exe",
        "sihost.exe",
        "taskhostw.exe",
        "dllhost.exe"
    };

    for (size_t i = 0; i < sizeof(targets) / sizeof(targets[0]); i++) {
        if (NameEq(name, targets[i])) {
            return true;
        }
    }
    return false;
}

static std::string Join(const std::vector<std::string>& items) {
    if (items.empty()) return "None";
    std::ostringstream oss;
    for (size_t i = 0; i < items.size(); i++) {
        if (i) oss << ", ";
        oss << items[i];
    }
    return oss.str();
}

static std::string GetProcessOwner(HANDLE hProc) {
    HANDLE hToken = NULL;
    if (!OpenProcessToken(hProc, TOKEN_QUERY, &hToken)) {
        return "UNKNOWN";
    }

    DWORD len = 0;
    GetTokenInformation(hToken, TokenUser, NULL, 0, &len);
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || len == 0) {
        CloseHandle(hToken);
        return "UNKNOWN";
    }

    std::vector<BYTE> buf(len);
    if (!GetTokenInformation(hToken, TokenUser, &buf[0], len, &len)) {
        CloseHandle(hToken);
        return "UNKNOWN";
    }

    TOKEN_USER* tu = reinterpret_cast<TOKEN_USER*>(&buf[0]);
    char name[256] = {0};
    char domain[256] = {0};
    DWORD cchName = sizeof(name);
    DWORD cchDomain = sizeof(domain);
    SID_NAME_USE use;

    if (!LookupAccountSidA(NULL, tu->User.Sid, name, &cchName, domain, &cchDomain, &use)) {
        CloseHandle(hToken);
        return "UNKNOWN";
    }

    CloseHandle(hToken);
    return std::string(domain) + "\\" + std::string(name);
}

static std::string GetIntegrityLevel(HANDLE hProc) {
    HANDLE hToken = NULL;
    if (!OpenProcessToken(hProc, TOKEN_QUERY, &hToken)) {
        return "UNKNOWN";
    }

    DWORD len = 0;
    GetTokenInformation(hToken, TokenIntegrityLevel, NULL, 0, &len);
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || len == 0) {
        CloseHandle(hToken);
        return "UNKNOWN";
    }

    std::vector<BYTE> buf(len);
    if (!GetTokenInformation(hToken, TokenIntegrityLevel, &buf[0], len, &len)) {
        CloseHandle(hToken);
        return "UNKNOWN";
    }

    TOKEN_MANDATORY_LABEL* tml = reinterpret_cast<TOKEN_MANDATORY_LABEL*>(&buf[0]);
    DWORD rid = *GetSidSubAuthority(
        tml->Label.Sid,
        static_cast<DWORD>(*GetSidSubAuthorityCount(tml->Label.Sid) - 1)
    );

    CloseHandle(hToken);

    if (rid >= SECURITY_MANDATORY_SYSTEM_RID) return "SYSTEM";
    if (rid >= SECURITY_MANDATORY_HIGH_RID)   return "HIGH";
    if (rid >= SECURITY_MANDATORY_MEDIUM_RID) return "MEDIUM";
    if (rid >= SECURITY_MANDATORY_LOW_RID)    return "LOW";
    return "UNKNOWN";
}

static DWORD GetProcSessionId(DWORD pid) {
    DWORD sessionId = static_cast<DWORD>(-1);
    if (!ProcessIdToSessionId(pid, &sessionId)) {
        return static_cast<DWORD>(-1);
    }
    return sessionId;
}

static bool Is64BitOS() {
    SYSTEM_INFO si;
    GetNativeSystemInfo(&si);
    return si.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_AMD64 ||
           si.wProcessorArchitecture == PROCESSOR_ARCHITECTURE_ARM64;
}

static std::string GetProcessArch(HANDLE hProc) {
    BOOL wow64 = FALSE;

    typedef BOOL (WINAPI *LPFN_ISWOW64PROCESS)(HANDLE, PBOOL);
    HMODULE hKernel = GetModuleHandleA("kernel32.dll");
    LPFN_ISWOW64PROCESS pIsWow64Process =
        reinterpret_cast<LPFN_ISWOW64PROCESS>(GetProcAddress(hKernel, "IsWow64Process"));

    if (!pIsWow64Process) {
        return "UNKNOWN";
    }

    if (!pIsWow64Process(hProc, &wow64)) {
        return "UNKNOWN";
    }

    if (!Is64BitOS()) {
        return "x86";
    }

    return wow64 ? "x86" : "x64";
}

static std::vector<std::string> GetInterestingPrivileges(HANDLE hProc) {
    std::vector<std::string> out;
    HANDLE hToken = NULL;

    if (!OpenProcessToken(hProc, TOKEN_QUERY, &hToken)) {
        return out;
    }

    DWORD len = 0;
    GetTokenInformation(hToken, TokenPrivileges, NULL, 0, &len);
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || len == 0) {
        CloseHandle(hToken);
        return out;
    }

    std::vector<BYTE> buf(len);
    if (!GetTokenInformation(hToken, TokenPrivileges, &buf[0], len, &len)) {
        CloseHandle(hToken);
        return out;
    }

    TOKEN_PRIVILEGES* tp = reinterpret_cast<TOKEN_PRIVILEGES*>(&buf[0]);

    for (DWORD i = 0; i < tp->PrivilegeCount; i++) {
        if ((tp->Privileges[i].Attributes & SE_PRIVILEGE_ENABLED) == 0) {
            continue;
        }

        char privName[256] = {0};
        DWORD cchName = sizeof(privName);

        if (LookupPrivilegeNameA(NULL, &tp->Privileges[i].Luid, privName, &cchName)) {
            if (_stricmp(privName, "SeDebugPrivilege") == 0 ||
                _stricmp(privName, "SeImpersonatePrivilege") == 0 ||
                _stricmp(privName, "SeAssignPrimaryTokenPrivilege") == 0 ||
                _stricmp(privName, "SeTcbPrivilege") == 0 ||
                _stricmp(privName, "SeBackupPrivilege") == 0 ||
                _stricmp(privName, "SeRestorePrivilege") == 0 ||
                _stricmp(privName, "SeLoadDriverPrivilege") == 0) {
                out.push_back(privName);
            }
        }
    }

    CloseHandle(hToken);
    return out;
}

static int AddStabilityBonus(const char* procName) {
    if (NameEq(procName, "explorer.exe")) return 4;
    if (NameEq(procName, "svchost.exe")) return 5;
    if (NameEq(procName, "dllhost.exe")) return 3;
    if (NameEq(procName, "taskhostw.exe")) return 2;
    if (NameEq(procName, "runtimebroker.exe")) return 2;
    if (NameEq(procName, "firefox.exe")) return 1;
    if (NameEq(procName, "msedgewebview2.exe")) return 1;
    return 0;
}

static bool OwnerLooksPrivileged(const std::string& owner) {
    return owner.find("NT AUTHORITY\\SYSTEM") != std::string::npos ||
           owner.find("NT AUTHORITY\\LOCAL SERVICE") != std::string::npos ||
           owner.find("NT AUTHORITY\\NETWORK SERVICE") != std::string::npos;
}

static void PrintProcessSummary(const RT_ProcessInfo& p) {
    std::cout << "\n[+] Process: " << p.name << " PID: " << p.pid << "\n";
    std::cout << "   Owner:     " << p.owner << "\n";
    std::cout << "   Integrity: " << p.integrity << "\n";
    std::cout << "   Arch:      " << p.arch << "\n";
    std::cout << "   Session:   ";
    if (p.sessionId == static_cast<DWORD>(-1)) std::cout << "UNKNOWN\n";
    else std::cout << p.sessionId << "\n";

    std::cout << "   Privileges: " << Join(p.enabledPrivs) << "\n";

    if (p.canVmWrite)      std::cout << "   [ACCESS] PROCESS_VM_WRITE\n";
    if (p.canVmOperation)  std::cout << "   [ACCESS] PROCESS_VM_OPERATION\n";
    if (p.canCreateThread) std::cout << "   [ACCESS] PROCESS_CREATE_THREAD\n";
    if (p.canDupHandle)    std::cout << "   [ACCESS] PROCESS_DUP_HANDLE\n";
    if (p.canQueryInfo)    std::cout << "   [ACCESS] PROCESS_QUERY_INFORMATION\n";
    if (p.canAllAccess)    std::cout << "   [ACCESS] PROCESS_ALL_ACCESS\n";

    if (p.injectionCapable) {
        std::cout << "   [!] Injection-capable target\n";
    }

    if (p.privescWorthy) {
        std::cout << "   [PRIVESC] Likely privesc-worthy target\n";
    }

    if (p.score >= 8) {
        std::cout << "   [!!!] HIGH VALUE TARGET (Score: " << p.score << ")\n";
    }
}

static void PrintCurrentExecutionContext() {
    HANDLE hProc = GetCurrentProcess();
    HANDLE hToken = NULL;

    std::cout << "\n========================================\n";
    std::cout << "CURRENT EXECUTION CONTEXT\n";
    std::cout << "========================================\n";

    std::cout << "Process ID: " << GetCurrentProcessId() << "\n";
    std::cout << "Session:    ";
    DWORD sessionId = GetProcSessionId(GetCurrentProcessId());
    if (sessionId == static_cast<DWORD>(-1)) std::cout << "UNKNOWN\n";
    else std::cout << sessionId << "\n";

    std::cout << "Owner:      " << GetProcessOwner(hProc) << "\n";
    std::cout << "Integrity:  " << GetIntegrityLevel(hProc) << "\n";
    std::cout << "Arch:       " << GetProcessArch(hProc) << "\n";

    if (!OpenProcessToken(hProc, TOKEN_QUERY, &hToken)) {
        std::cout << "Privileges: UNKNOWN\n";
        return;
    }

    DWORD len = 0;
    GetTokenInformation(hToken, TokenPrivileges, NULL, 0, &len);
    if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || len == 0) {
        CloseHandle(hToken);
        std::cout << "Privileges: UNKNOWN\n";
        return;
    }

    std::vector<BYTE> buf(len);
    if (!GetTokenInformation(hToken, TokenPrivileges, &buf[0], len, &len)) {
        CloseHandle(hToken);
        std::cout << "Privileges: UNKNOWN\n";
        return;
    }

    TOKEN_PRIVILEGES* tp = reinterpret_cast<TOKEN_PRIVILEGES*>(&buf[0]);

    std::cout << "Enabled Privileges:\n";
    bool printedAny = false;

    for (DWORD i = 0; i < tp->PrivilegeCount; i++) {
        if ((tp->Privileges[i].Attributes & SE_PRIVILEGE_ENABLED) == 0) {
            continue;
        }

        char privName[256] = {0};
        DWORD cchName = sizeof(privName);

        if (LookupPrivilegeNameA(NULL, &tp->Privileges[i].Luid, privName, &cchName)) {
            std::cout << "  - " << privName << "\n";
            printedAny = true;
        }
    }

    if (!printedAny) {
        std::cout << "  None\n";
    }

    CloseHandle(hToken);
}

int main() {
    std::cout << "==== Advanced Red Team Process Recon Tool ====\n";

    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE) {
        std::cout << "Failed to create process snapshot\n";
        return 1;
    }

    PROCESSENTRY32 pe;
    ZeroMemory(&pe, sizeof(pe));
    pe.dwSize = sizeof(pe);

    if (!Process32First(hSnap, &pe)) {
        std::cout << "Failed to enumerate processes\n";
        CloseHandle(hSnap);
        return 1;
    }

    std::vector<RT_ProcessInfo> allTargets;
    RT_ProcessInfo bestInject = {};
    RT_ProcessInfo bestPrivEsc = {};
    bool haveBestInject = false;
    bool haveBestPrivEsc = false;

    do {
        RT_ProcessInfo pi;
        pi.name = pe.szExeFile;
        pi.pid = pe.th32ProcessID;
        pi.owner = "UNKNOWN";
        pi.integrity = "UNKNOWN";
        pi.arch = "UNKNOWN";
        pi.sessionId = GetProcSessionId(pi.pid);
        pi.canVmWrite = false;
        pi.canVmOperation = false;
        pi.canCreateThread = false;
        pi.canDupHandle = false;
        pi.canQueryInfo = false;
        pi.canAllAccess = false;
        pi.injectionCapable = false;
        pi.privescWorthy = false;
        pi.score = 0;

        HANDLE hMeta = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, pi.pid);
        if (!hMeta) {
            hMeta = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pi.pid);
        }

        if (hMeta) {
            pi.owner = GetProcessOwner(hMeta);
            pi.integrity = GetIntegrityLevel(hMeta);
            pi.arch = GetProcessArch(hMeta);
            pi.enabledPrivs = GetInterestingPrivileges(hMeta);
            CloseHandle(hMeta);
        }

        for (size_t i = 0; i < sizeof(g_rules) / sizeof(g_rules[0]); i++) {
            HANDLE hProc = OpenProcess(g_rules[i].access, FALSE, pi.pid);
            if (!hProc) {
                continue;
            }

            pi.score += g_rules[i].score;

            switch (g_rules[i].access) {
                case PROCESS_VM_WRITE:          pi.canVmWrite = true; break;
                case PROCESS_VM_OPERATION:      pi.canVmOperation = true; break;
                case PROCESS_CREATE_THREAD:     pi.canCreateThread = true; break;
                case PROCESS_DUP_HANDLE:        pi.canDupHandle = true; break;
                case PROCESS_QUERY_INFORMATION: pi.canQueryInfo = true; break;
                case PROCESS_ALL_ACCESS:        pi.canAllAccess = true; break;
            }

            CloseHandle(hProc);
        }

        pi.injectionCapable = pi.canVmWrite && pi.canVmOperation && pi.canCreateThread;

        if (pi.injectionCapable) {
            pi.score += 4;
        }

        if (pi.canAllAccess) {
            pi.score += 2;
        }

        pi.score += AddStabilityBonus(pi.name.c_str());

        if (IsUserStableTarget(pi.name.c_str())) {
            pi.score += 2;
        }

        bool privilegedOwner = OwnerLooksPrivileged(pi.owner);
        bool privilegedIntegrity = (pi.integrity == "SYSTEM" || pi.integrity == "HIGH");
        bool serviceLike = IsServiceLikeTarget(pi.name.c_str());

        if (privilegedOwner)     pi.score += 4;
        if (privilegedIntegrity) pi.score += 3;
        if (serviceLike)         pi.score += 2;

        if (!pi.enabledPrivs.empty()) {
            pi.score += 2;
        }

        pi.privescWorthy = pi.injectionCapable && (privilegedOwner || privilegedIntegrity || serviceLike);

        PrintProcessSummary(pi);

        allTargets.push_back(pi);

        if (pi.injectionCapable) {
            bool candidateForInject =
                !pi.privescWorthy &&
                (IsUserStableTarget(pi.name.c_str()) || pi.canAllAccess);

            if (candidateForInject) {
                if (!haveBestInject || pi.score > bestInject.score) {
                    bestInject = pi;
                    haveBestInject = true;
                }
            }
        }

        if (pi.privescWorthy) {
            if (!haveBestPrivEsc || pi.score > bestPrivEsc.score) {
                bestPrivEsc = pi;
                haveBestPrivEsc = true;
            }
        }

    } while (Process32Next(hSnap, &pe));

    CloseHandle(hSnap);

    std::cout << "\n========================================\n";
    std::cout << "BEST TARGETS SUMMARY\n";
    std::cout << "========================================\n";

    std::cout << "\nTop injection-capable user-context targets:\n";
    bool anyInject = false;
    for (size_t i = 0; i < allTargets.size(); i++) {
        const RT_ProcessInfo& p = allTargets[i];
        if (p.injectionCapable && !p.privescWorthy) {
            std::cout << "  [INJECT] " << p.name
                      << " PID=" << p.pid
                      << " Owner=" << p.owner
                      << " Integrity=" << p.integrity
                      << " Arch=" << p.arch
                      << " Score=" << p.score
                      << "\n";
            anyInject = true;
        }
    }
    if (!anyInject) {
        std::cout << "  None\n";
    }

    std::cout << "\nLikely privesc-worthy targets:\n";
    bool anyPriv = false;
    for (size_t i = 0; i < allTargets.size(); i++) {
        const RT_ProcessInfo& p = allTargets[i];
        if (p.privescWorthy) {
            std::cout << "  [PRIVESC] " << p.name
                      << " PID=" << p.pid
                      << " Owner=" << p.owner
                      << " Integrity=" << p.integrity
                      << " Arch=" << p.arch
                      << " Score=" << p.score
                      << "\n";
            anyPriv = true;
        }
    }
    if (!anyPriv) {
        std::cout << "  None\n";
    }

    std::cout << "\nAuto-selected best targets:\n";
    if (haveBestInject) {
        std::cout << "  Best injection target: "
                  << bestInject.name
                  << " PID=" << bestInject.pid
                  << " Owner=" << bestInject.owner
                  << " Integrity=" << bestInject.integrity
                  << " Arch=" << bestInject.arch
                  << " Score=" << bestInject.score
                  << "\n";
    } else {
        std::cout << "  Best injection target: None\n";
    }

    if (haveBestPrivEsc) {
        std::cout << "  Best privesc target: "
                  << bestPrivEsc.name
                  << " PID=" << bestPrivEsc.pid
                  << " Owner=" << bestPrivEsc.owner
                  << " Integrity=" << bestPrivEsc.integrity
                  << " Arch=" << bestPrivEsc.arch
                  << " Score=" << bestPrivEsc.score
                  << "\n";
    } else {
        std::cout << "  Best privesc target: None\n";
    }

    PrintCurrentExecutionContext();

    std::cout << "\nDone.\n";
    return 0;
}
