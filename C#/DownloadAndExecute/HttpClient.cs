using System.Net.Http;
using System.IO;
using System.Threading.Tasks;

var client = new HttpClient();
var data = await client.GetByteArrayAsync("http://example.com/file.exe");
File.WriteAllBytes("file.exe", data);
