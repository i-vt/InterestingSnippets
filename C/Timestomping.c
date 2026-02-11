#include <sys/stat.h>
#include <utime.h>

void timestomp(const char* target_file, const char* reference_file) {
    struct stat ref_stat;
    struct utimbuf new_times;

    // 1. Read the metadata from the legitimate reference file
    stat(reference_file, &ref_stat);

    // 2. Copy the original access and modification times into our struct
    new_times.actime = ref_stat.st_atime;
    new_times.modtime = ref_stat.st_mtime;

    // 3. Apply the forged timestamps to the file
    utime(target_file, &new_times);
}
