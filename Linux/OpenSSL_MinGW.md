# The Issue
```
x86_64-w64-mingw32-gcc 1.c -o output.exe \
  -I ~/builds/openssl-1.1.1u/install/include \
  -L ~/builds/openssl-1.1.1u/install/lib \
  -lssl -lcrypto -lws2_32 -lcrypt32 -static -municode

/usr/bin/x86_64-w64-mingw32-ld: /tmp/ccHpnxFf.o:1.c:(.text+0x7d): undefined reference to `OPENSSL_init_ssl'
/usr/bin/x86_64-w64-mingw32-ld: /tmp/ccHpnxFf.o:1.c:(.text+0x8c): undefined reference to `OPENSSL_init_ssl'
/usr/bin/x86_64-w64-mingw32-ld: /tmp/ccHpnxFf.o:1.c:(.text+0xa0): undefined reference to `TLS_client_method'
/usr/bin/x86_64-w64-mingw32-ld: /tmp/ccHpnxFf.o:1.c:(.text+0xa8): undefined reference to `SSL_CTX_new'
/usr/bin/x86_64-w64-mingw32-ld: /tmp/ccHpnxFf.o:1.c:(.text+0x19f): undefined reference to `SSL_new'
/usr/bin/x86_64-w64-mingw32-ld: /tmp/ccHpnxFf.o:1.c:(.text+0x1be): undefined reference to `SSL_set_fd'
/usr/bin/x86_64-w64-mingw32-ld: /tmp/ccHpnxFf.o:1.c:(.text+0x1cd): undefined reference to `SSL_connect'
/usr/bin/x86_64-w64-mingw32-ld: /tmp/ccHpnxFf.o:1.c:(.text+0x1e0): undefined reference to `SSL_free'
/usr/bin/x86_64-w64-mingw32-ld: /tmp/ccHpnxFf.o:1.c:(.text+0x1ef): undefined reference to `SSL_CTX_free'
/usr/bin/x86_64-w64-mingw32-ld: /tmp/ccHpnxFf.o:1.c:(.text+0x375): undefined reference to `SSL_read'
/usr/bin/x86_64-w64-mingw32-ld: /tmp/ccHpnxFf.o:1.c:(.text+0x444): undefined reference to `SSL_write'
/usr/bin/x86_64-w64-mingw32-ld: /usr/lib/gcc/x86_64-w64-mingw32/12-win32/../../../../x86_64-w64-mingw32/lib/libmingw32.a(lib64_libmingw32_a-crt0_c.o): in function `main':
/build/./mingw-w64-crt/crt/crt0_c.c:18: undefined reference to `WinMain'
collect2: error: ld returned 1 exit status

```


# Solution
run as root
```
mkdir ~/builds
wget https://www.openssl.org/source/openssl-1.1.1u.tar.gz
tar -xvzf openssl-1.1.1u.tar.gz
cd ~/builds/openssl-1.1.1u
make clean

export CC=x86_64-w64-mingw32-gcc
export AR=x86_64-w64-mingw32-ar
export RANLIB=x86_64-w64-mingw32-ranlib

./Configure mingw64 no-shared no-dso no-engine --prefix=$PWD/install

make build_libs -j$(nproc)
make install_dev

```
fix the permissions

