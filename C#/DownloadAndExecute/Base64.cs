using System;
using System.IO;

string base64 = "aHR0cHM6Ly9leGFtcGxlLmNvbS9maWxlLmV4ZQ=="; 
byte[] payload = Convert.FromBase64String(base64);

File.WriteAllBytes("file.exe", payload);
