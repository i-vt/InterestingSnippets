#include <signal.h>

void ignore_kill_signals() {
    signal(SIGQUIT, SIG_IGN);
    signal(SIGTERM, SIG_IGN);
    signal(SIGHUP,  SIG_IGN);
    signal(SIGINT,  SIG_IGN);
    signal(SIGPIPE, SIG_IGN);
}
