#include <signal.h>

// Forward declaration of the custom handler
void handler(int sig) {
    // Logic to reap child processes goes here 
    // This requires <signal.h>. I have included a dummy handler function to represent where the malware would likely call waitpid() to clean up dead child processes.
}

void handle_children() {
    signal(SIGCHLD, handler);
}
