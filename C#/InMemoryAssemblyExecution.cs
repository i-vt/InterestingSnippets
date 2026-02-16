using System.Reflection;

byte[] payload = File.ReadAllBytes("file.dll");
Assembly asm = Assembly.Load(payload);
asm.EntryPoint.Invoke(null, null);
