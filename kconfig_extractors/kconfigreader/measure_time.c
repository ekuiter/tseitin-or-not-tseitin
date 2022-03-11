#include <stdio.h>
#include <string.h>
#include <time.h>

int main(int argc, char* argv) {
    char *line = NULL;
    size_t len = 0;
    ssize_t lineSize = 0;
    long seconds, nanoseconds;
    unsigned long long elapsed;
    struct timespec begin_extraction, begin_transformation, end;
    clock_gettime(CLOCK_REALTIME, &begin_extraction);

    while (!feof(stdin)) {
        lineSize = getline(&line, &len, stdin);
        printf("%s", line);

        if (strcmp("writing dimacs\n", line) == 0)
            clock_gettime(CLOCK_REALTIME, &begin_transformation);

        if (strcmp("done.\n", line) == 0) {
            clock_gettime(CLOCK_REALTIME, &end);
            
            seconds = begin_transformation.tv_sec - begin_extraction.tv_sec;
            nanoseconds = begin_transformation.tv_nsec - begin_extraction.tv_nsec;
            elapsed = seconds * 1e+9 + nanoseconds;
            printf("#item time %llu\n", elapsed);
            
            seconds = end.tv_sec - begin_transformation.tv_sec;
            nanoseconds = end.tv_nsec - begin_transformation.tv_nsec;
            elapsed = seconds * 1e+9 + nanoseconds;
            printf("c time %llu\n", elapsed);
                        
            return 0;
        }
    }
}
