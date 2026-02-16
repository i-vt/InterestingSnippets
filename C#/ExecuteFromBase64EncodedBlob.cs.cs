using System;
using System.IO;

string base64 = "base64offilegoeshere"; 
byte[] payload = Convert.FromBase64String(base64);

File.WriteAllBytes("file.exe", payload);
