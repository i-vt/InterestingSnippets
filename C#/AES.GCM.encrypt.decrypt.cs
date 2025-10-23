using System;
using System.Security.Cryptography;
using System.Text;

internal class Program
{
	private static void Main(string[] args)
	{
		// --- Simple AES-GCM encrypt/decrypt helpers ---
		static byte[] EncryptMessage(byte[] key, string plaintext)
		{
			using var aes = new AesGcm(key);
			byte[] nonce = RandomNumberGenerator.GetBytes(12);
			byte[] pt = Encoding.UTF8.GetBytes(plaintext);
			byte[] ct = new byte[pt.Length];
			byte[] tag = new byte[16];
			aes.Encrypt(nonce, pt, ct, tag);

			// Format: nonce(12) | tag(16) | ciphertext
			var outb = new byte[12 + 16 + ct.Length];
			Buffer.BlockCopy(nonce, 0, outb, 0, 12);
			Buffer.BlockCopy(tag, 0, outb, 12, 16);
			Buffer.BlockCopy(ct, 0, outb, 28, ct.Length);
			return outb;
		}

		static bool TryDecryptMessage(byte[] key, byte[] blob, out string? plaintext)
		{
			plaintext = null;
			try
			{
				if (blob.Length < 28) return false;
				byte[] nonce = new byte[12];
				byte[] tag = new byte[16];
				Buffer.BlockCopy(blob, 0, nonce, 0, 12);
				Buffer.BlockCopy(blob, 12, tag, 0, 16);
				byte[] ct = new byte[blob.Length - 28];
				Buffer.BlockCopy(blob, 28, ct, 0, ct.Length);
				using var aes = new AesGcm(key);
				byte[] pt = new byte[ct.Length];
				aes.Decrypt(nonce, ct, tag, pt);
				plaintext = Encoding.UTF8.GetString(pt);
				return true;
			}
			catch { return false; }
		}

		byte[] key = RandomNumberGenerator.GetBytes(32);
		string message = "SECRET! ! !! ";
		byte[] encrypted = EncryptMessage(key, message);

		if (TryDecryptMessage(key, encrypted, out string? decrypted))
		{
			Console.WriteLine(decrypted);
		}
		else
		{
			Console.WriteLine("ERR");
		}
	}
}