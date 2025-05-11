#include <iostream>
#include <string>
#include <algorithm>
#include <memory>
//g++ -std=c++17 -o encrypt3 encrypt3.cpp -lcryptopp
//sudo apt-get install libcrypto++-dev libcrypto++-doc libcrypto++-utils -y

// Crypto++
#include <cryptopp/osrng.h>
#include <cryptopp/hex.h>
#include <cryptopp/aes.h>
#include <cryptopp/des.h>
#include <cryptopp/modes.h>
#include <cryptopp/filters.h>

using namespace std;
using namespace CryptoPP;

// === Classical Cipher Functions ===

string reverseCipher(const string& input) {
    string result = input;
    reverse(result.begin(), result.end());
    return result;
}

string rot13Cipher(const string& input) {
    string result;
    for (char c : input) {
        if (isalpha(c)) {
            char base = isupper(c) ? 'A' : 'a';
            result += static_cast<char>((c - base + 13) % 26 + base);
        } else {
            result += c;
        }
    }
    return result;
}

string atbashCipher(const string& input) {
    string result;
    for (char c : input) {
        if (isalpha(c)) {
            char base = isupper(c) ? 'A' : 'a';
            result += static_cast<char>(base + (25 - (c - base)));
        } else {
            result += c;
        }
    }
    return result;
}

// === Crypto++ Encryptor Base Class and Implementations ===

class Encryptor {
public:
    virtual string encrypt(const string& plaintext) = 0;
    virtual string getKeyHex() const = 0;
    virtual string getIVHex() const = 0;
    virtual ~Encryptor() {}
};

class AESEncryptor : public Encryptor {
private:
    SecByteBlock key, iv;
public:
    AESEncryptor() : key(AES::DEFAULT_KEYLENGTH), iv(AES::BLOCKSIZE) {
        AutoSeededRandomPool prng;
        prng.GenerateBlock(key, key.size());
        prng.GenerateBlock(iv, iv.size());
    }

    string encrypt(const string& plaintext) override {
        string ciphertext;
        CBC_Mode<AES>::Encryption encryption(key, key.size(), iv);
        StringSource(plaintext, true,
            new StreamTransformationFilter(encryption, new StringSink(ciphertext)));
        return ciphertext;
    }

    string getKeyHex() const override {
        return encodeHex(key);
    }

    string getIVHex() const override {
        return encodeHex(iv);
    }

private:
    string encodeHex(const SecByteBlock& data) const {
        string encoded;
        StringSource(data, data.size(), true, new HexEncoder(new StringSink(encoded)));
        return encoded;
    }
};

class DESEncryptor : public Encryptor {
private:
    SecByteBlock key, iv;
public:
    DESEncryptor() : key(DES::DEFAULT_KEYLENGTH), iv(DES::BLOCKSIZE) {
        AutoSeededRandomPool prng;
        prng.GenerateBlock(key, key.size());
        prng.GenerateBlock(iv, iv.size());
    }

    string encrypt(const string& plaintext) override {
        string ciphertext;
        CBC_Mode<DES>::Encryption encryption(key, key.size(), iv);
        StringSource(plaintext, true,
            new StreamTransformationFilter(encryption, new StringSink(ciphertext)));
        return ciphertext;
    }

    string getKeyHex() const override {
        return encodeHex(key);
    }

    string getIVHex() const override {
        return encodeHex(iv);
    }

private:
    string encodeHex(const SecByteBlock& data) const {
        string encoded;
        StringSource(data, data.size(), true, new HexEncoder(new StringSink(encoded)));
        return encoded;
    }
};

// === Dispatcher ===

string applyClassicalCipher(const string& method, const string& input) {
    if (method == "reverse") return reverseCipher(input);
    if (method == "rot13") return rot13Cipher(input);
    if (method == "atbash") return atbashCipher(input);
    return "";
}

unique_ptr<Encryptor> createEncryptor(const string& method) {
    if (method == "aes") return make_unique<AESEncryptor>();
    if (method == "des") return make_unique<DESEncryptor>();
    throw invalid_argument("Unsupported cipher type: " + method);
}

// === Main ===

int main(int argc, char* argv[]) {
    if (argc < 3) {
        cerr << "Usage: " << argv[0] << " <cipher> <plaintext>\n";
        cerr << "Supported ciphers: reverse, rot13, atbash, aes, des\n";
        return 1;
    }

    string method = argv[1];
    string plaintext = argv[2];

    try {
        if (method == "aes" || method == "des") {
            auto encryptor = createEncryptor(method);
            string ciphertext = encryptor->encrypt(plaintext);
            string hexCipher;
            StringSource(ciphertext, true, new HexEncoder(new StringSink(hexCipher)));

            cout << "Cipher: " << method << endl;
            cout << "Ciphertext (hex): " << hexCipher << endl;
            cout << "Key (hex): " << encryptor->getKeyHex() << endl;
            cout << "IV (hex): " << encryptor->getIVHex() << endl;
        } else {
            string encrypted = applyClassicalCipher(method, plaintext);
            if (encrypted.empty()) {
                cerr << "Error: Unsupported cipher method.\n";
                return 1;
            }
            cout << "Cipher: " << method << endl;
            cout << "Encrypted string: " << encrypted << endl;
        }
    } catch (const exception& e) {
        cerr << "Error: " << e.what() << endl;
        return 1;
    }

    return 0;
}
