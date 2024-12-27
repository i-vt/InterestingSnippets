#include <stdio.h>
//In virtualized environments, the CPU sets the hypervisor bit (bit 31 of the ECX register) to 1 during a CPUID instruction. This is required for the virtual machine to function and is fundamental to how hypervisors interact with guest operating systems.
//No amount of additional coding or configuration can disable or hide this bit because it's essential for virtualization.
int main() {
    unsigned int eax, ebx, ecx, edx;
    eax = 1;  
    __asm__("cpuid"
            : "=c"(ecx)
            : "a"(eax)
            : "ebx", "edx");
    if (ecx & (1 << 31)) {
        printf("Hypervisor present\n");
    } else {
        printf("No hypervisor detected\n");
    }
    return 0;
}
