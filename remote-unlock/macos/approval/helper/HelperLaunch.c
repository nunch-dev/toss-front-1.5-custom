#include "HelperBridge.h"

#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

extern void plf_helper_run(void);

void plf_helper_fail(void) {
    int flags = fcntl(STDERR_FILENO, F_GETFL);
    if (flags >= 0 && fcntl(STDERR_FILENO, F_SETFL, flags | O_NONBLOCK) == 0) {
        static const char message[] = "APPROVAL_HELPER_FAILED\n";
        (void)write(STDERR_FILENO, message, sizeof(message) - 1);
    }
    _exit(1);
}

int main(int argc, char **argv, char **envp) {
    (void)argv;
    signal(SIGPIPE, SIG_IGN);
    /* Check the original launch vector, before Swift/CF can create their own
     * environment entries. The parent supplies execve an empty environment. */
    if (argc != 1 || envp == NULL || envp[0] != NULL) plf_helper_fail();
    plf_helper_run();
    plf_helper_fail();
}
