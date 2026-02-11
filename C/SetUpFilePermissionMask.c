#include <sys/stat.h>

void set_secure_umask() {
    // 077 octal == 0x3F hex
    umask(077); 
}
