#include <openssl/aes.h>
#include <openssl/rand.h>
#include <iostream>
#include <string>
#include <cstring>

void encrypt(const std::string& plainText, std::string& cipherText, unsigned char* key, unsigned char* iv) {
    AES_KEY aesKey;
    AES_set_encrypt_key(key, 128, &aesKey);

    int cipherTextLen = ((plainText.length() + AES_BLOCK_SIZE) / AES_BLOCK_SIZE) * AES_BLOCK_SIZE;
    unsigned char* buffer = new unsigned char[cipherTextLen];
    memset(buffer, 0, cipherTextLen);
    AES_cbc_encrypt(reinterpret_cast<const unsigned char*>(plainText.c_str()), buffer, plainText.length(), &aesKey, iv, AES_ENCRYPT);

    cipherText.assign(reinterpret_cast<char*>(buffer), cipherTextLen);
    delete[] buffer;
}

void decrypt(const std::string& cipherText, std::string& decryptedText, unsigned char* key, unsigned char* iv) {
    AES_KEY aesKey;
    AES_set_decrypt_key(key, 128, &aesKey);

    unsigned char* buffer = new unsigned char[cipherText.length()];
    memset(buffer, 0, cipherText.length());
    AES_cbc_encrypt(reinterpret_cast<const unsigned char*>(cipherText.c_str()), buffer, cipherText.length(), &aesKey, iv, AES_DECRYPT);

    decryptedText.assign(reinterpret_cast<char*>(buffer));
    delete[] buffer;
}

int main() {
    const std::string plainText = "Hello, World!";
    std::string cipherText, decryptedText;

    // 128 bit key
    unsigned char key[16];
    // 128 bit IV
    unsigned char iv[AES_BLOCK_SIZE];
    // Generate random key and IV
    RAND_bytes(key, sizeof(key));
    RAND_bytes(iv, sizeof(iv));

    encrypt(plainText, cipherText, key, iv);
    decrypt(cipherText, decryptedText, key, iv);

    std::cout << "Original Text: " << plainText << std::endl;
    std::cout << "Decrypted Text: " << decryptedText << std::endl;

    return 0;
}
