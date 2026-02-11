#include <sys/resource.h>

void disable_core_dumps() {
    struct rlimit rlimits;
    rlimits.rlim_cur = 0;
    rlimits.rlim_max = 0;
    
    setrlimit(RLIMIT_CORE, &rlimits);
}
