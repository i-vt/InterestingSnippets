# .\1.ps1                      # curated files, per-module subfolders
# .\1.ps1 -Flat                # curated files, one folder, imageres_#10.ico style
# .\1.ps1 -FullScan -Flat      # everything Windows ships, flat + prefixed



# Extract-AllWindowsIcons.ps1
# Extracts complete, original multi-resolution .ico files from Windows 10/11
# system modules.
#   Default : one subfolder per module   -> WindowsIcons\imageres\#10.ico
#   -Flat   : single folder, prefixed    -> WindowsIcons\imageres_#10.ico
#   -FullScan : sweep ALL of System32 + SystemResources, not just known files

[CmdletBinding()]
param(
    [string]$OutputRoot = "$PSScriptRoot\WindowsIcons",
    [switch]$FullScan,
    [switch]$Flat
)

# Only compile the C# type once per PowerShell session (Add-Type can't
# replace an already-loaded type, and re-running would throw).
if (-not ('IconDumper' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;

public static class IconDumper
{
    const uint LOAD_LIBRARY_AS_DATAFILE = 0x00000002;
    static readonly IntPtr RT_ICON       = (IntPtr)3;
    static readonly IntPtr RT_GROUP_ICON = (IntPtr)14;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr LoadLibraryEx(string lpFileName, IntPtr hFile, uint dwFlags);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool FreeLibrary(IntPtr hModule);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate bool EnumResNameProc(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool EnumResourceNames(IntPtr hModule, IntPtr lpszType, EnumResNameProc lpEnumFunc, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr FindResource(IntPtr hModule, IntPtr lpName, IntPtr lpType);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr LoadResource(IntPtr hModule, IntPtr hResInfo);

    [DllImport("kernel32.dll")]
    static extern IntPtr LockResource(IntPtr hResData);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint SizeofResource(IntPtr hModule, IntPtr hResInfo);

    static bool IsIntResource(IntPtr p) { return ((long)p >> 16) == 0; }

    static byte[] ReadResource(IntPtr hMod, IntPtr name, IntPtr type)
    {
        IntPtr hRes = FindResource(hMod, name, type);
        if (hRes == IntPtr.Zero) return null;
        uint size = SizeofResource(hMod, hRes);
        IntPtr hData = LoadResource(hMod, hRes);
        if (hData == IntPtr.Zero) return null;
        IntPtr ptr = LockResource(hData);
        if (ptr == IntPtr.Zero || size == 0) return null;
        byte[] data = new byte[size];
        Marshal.Copy(ptr, data, 0, (int)size);
        return data;
    }

    public static int DumpAllIcons(string modulePath, string outDir, string filePrefix)
    {
        IntPtr hMod = LoadLibraryEx(modulePath, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
        if (hMod == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), modulePath);
        try
        {
            var groups = new List<IntPtr>();
            EnumResNameProc cb = delegate(IntPtr m, IntPtr t, IntPtr name, IntPtr lp)
            {
                try { groups.Add(name); } catch { }
                return true;
            };
            EnumResourceNames(hMod, RT_GROUP_ICON, cb, IntPtr.Zero);

            int written = 0;
            foreach (IntPtr gname in groups)
            {
                byte[] grp = ReadResource(hMod, gname, RT_GROUP_ICON);
                if (grp == null || grp.Length < 6) continue;
                int n = BitConverter.ToUInt16(grp, 4);   // image count in this icon
                if (n <= 0) continue;

                var ms = new MemoryStream();
                var w  = new BinaryWriter(ms);
                w.Write(grp, 0, 6);                      // ICONDIR header (reserved, type=1, count)
                uint offset = (uint)(6 + 16 * n);
                var images = new List<byte[]>();

                for (int i = 0; i < n; i++)
                {
                    int e = 6 + 14 * i;                  // GRPICONDIRENTRY = 14 bytes
                    ushort id = BitConverter.ToUInt16(grp, e + 12);   // -> RT_ICON resource ID
                    byte[] img = ReadResource(hMod, (IntPtr)id, RT_ICON);
                    if (img == null) img = new byte[0];

                    w.Write(grp[e]);                     // width  (0 = 256)
                    w.Write(grp[e + 1]);                 // height (0 = 256)
                    w.Write(grp[e + 2]);                 // color count
                    w.Write(grp[e + 3]);                 // reserved
                    w.Write(BitConverter.ToUInt16(grp, e + 4));  // planes
                    w.Write(BitConverter.ToUInt16(grp, e + 6));  // bit count
                    w.Write((uint)img.Length);           // bytes in image
                    w.Write(offset);                     // file offset of image
                    offset += (uint)img.Length;
                    images.Add(img);
                }
                foreach (byte[] img in images) w.Write(img);
                w.Flush();

                string iname = IsIntResource(gname)
                    ? "#" + (gname.ToInt64() & 0xFFFF)
                    : Marshal.PtrToStringUni(gname);
                foreach (char c in Path.GetInvalidFileNameChars())
                    iname = iname.Replace(c, '_');

                File.WriteAllBytes(
                    Path.Combine(outDir, filePrefix + iname + ".ico"), ms.ToArray());
                written++;
            }
            return written;
        }
        finally
        {
            FreeLibrary(hMod);
        }
    }
}
'@
}

# If an OLD version of IconDumper is already loaded in this session, its
# method signature won't match - fail loudly instead of skipping silently.
if (-not [IconDumper].GetMethod('DumpAllIcons', [type[]]@([string],[string],[string]))) {
    throw "A stale IconDumper type from a previous run is loaded in this session. Close and reopen PowerShell, then run again."
}

$sys = "$env:SystemRoot\System32"
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

if ($FullScan) {
    # Everything: all modules in System32 + the split resource files (Win10 1903+)
    $files  = @(Get-ChildItem "$sys\*" -File -Include *.dll,*.exe,*.cpl,*.ocx,*.scr |
                Select-Object -ExpandProperty FullName)
    $files += @(Get-ChildItem "$env:SystemRoot\SystemResources\*" -File -Filter *.mun `
                -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
}
else {
    # Curated: known icon-heavy files on Windows 10/11
    $known = @(
        'imageres.dll','shell32.dll','moricons.dll','ddores.dll',
        'netshell.dll','wmploc.dll','compstui.dll','accessibilitycpl.dll',
        'themecpl.dll','syncui.dll','pnidui.dll','networkexplorer.dll','ActionCenterCPL.dll',
        'setupapi.dll','stobject.dll','batmeter.dll','comctl32.dll','credui.dll','authui.dll',
        'ieframe.dll','wlanui.dll','xwizards.dll','DSUIExt.dll','devmgr.dll','urlmon.dll',
        'main.cpl','mmsys.cpl','ncpa.cpl','appwiz.cpl','desk.cpl','firewall.cpl','hdwwiz.cpl',
        'inetcpl.cpl','intl.cpl','joy.cpl','powercfg.cpl','sysdm.cpl','telephon.cpl','timedate.cpl','wscui.cpl',
        'notepad.exe','calc.exe','mspaint.exe','wordpad.exe','cleanmgr.exe'
    )
    $files = @("$env:SystemRoot\explorer.exe")
    $files += @(foreach ($k in $known) {
        $p = Join-Path $sys $k
        if (Test-Path $p) { $p } else { Write-Warning "Not found: $p" }
    })
}

$done   = @{}          # avoids extracting a .dll and its .mun twin twice
$result = @()
$i = 0

foreach ($file in $files) {
    $i++
    if ($FullScan -and ($i % 250 -eq 0)) { Write-Host "  scanned $i of $($files.Count) ..." }

    $base = [IO.Path]::GetFileName($file) -replace '\.mun$','' -replace '\.(exe|dll|cpl|ocx|scr)$',''
    if ($done.ContainsKey($base)) { continue }
    $done[$base] = $true

    if ($Flat) {
        $outDir = $OutputRoot
        $prefix = "${base}_"
    } else {
        $outDir = Join-Path $OutputRoot $base
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        $prefix = ""
    }

    try   { $n = [IconDumper]::DumpAllIcons($file, $outDir, $prefix) }
    catch {
        Write-Verbose "Skipped $($file): $($_.Exception.Message)"
        if (-not $Flat) { Remove-Item $outDir -Force -ErrorAction SilentlyContinue }
        continue
    }

    if ($n -eq 0) {
        if (-not $Flat) { Remove-Item $outDir -Force }
        continue
    }

    Write-Host ("{0,-22} {1,5} icons" -f $base, $n)
    $result += [pscustomobject]@{ Module = $base; Icons = $n }
}

Write-Host "`n==================== SUMMARY ===================="
$result | Sort-Object Icons -Descending | Format-Table -AutoSize
Write-Host ("Total: {0} icons from {1} modules`nSaved under: {2}" -f
    ($result | Measure-Object Icons -Sum).Sum, $result.Count, $OutputRoot)
