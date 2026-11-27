/* TEST ONLY: transport fixture, never signed or installed as a helper. */
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 2) return 8;
    char byte;
    while (read(0, &byte, 1) == 1 && byte != '\n') {}
    if (write(3, "R", 1) != 1) return 9;
    close(3);
    if (strcmp(argv[1], "stall") == 0) {
        while (read(0, &byte, 1) > 0) {}
        return 2;
    }
    if (strcmp(argv[1], "flood") == 0) {
        char data[9000];
        memset(data, 'x', sizeof(data));
        (void)write(1, data, sizeof(data));
        return 0;
    }
    if (write(1, "bound\nresult\n", 13) != 13) return 10;
    return strcmp(argv[1], "crash") == 0 ? 7 : 0;
}
