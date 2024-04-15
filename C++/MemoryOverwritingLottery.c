#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <stdint.h>

int main() {
    srand(time(NULL)); 
    while (1) {
        uintptr_t randAddress = (uintptr_t)rand() % UINTPTR_MAX; 
        uintptr_t *ptr = (uintptr_t *)randAddress;

        printf("Attempting to write to address: %p\n", (void *)ptr);

        *ptr = 0xDEADBEEF;

        printf("Successfully wrote to address: %p, Value: %lx\n", (void *)ptr, *ptr);

        sleep(120); // Wait for 2 minutes before next attempt, if it didn't coredump yet lmaooo
    }

    return 0;
}
