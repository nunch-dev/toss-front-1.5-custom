#import "ChildProcess.h"
#import "CodeTrust.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <unistd.h>

BOOL PLFMakePipe(int descriptors[2]) {
    int raw[2];
    descriptors[0] = descriptors[1] = -1;
    if (pipe(raw) != 0) return NO;
    descriptors[0] = fcntl(raw[0], F_DUPFD_CLOEXEC, 3);
    descriptors[1] = fcntl(raw[1], F_DUPFD_CLOEXEC, 3);
    close(raw[0]);
    close(raw[1]);
    if (descriptors[0] >= 0 && descriptors[1] >= 0) return YES;
    if (descriptors[0] >= 0) close(descriptors[0]);
    if (descriptors[1] >= 0) close(descriptors[1]);
    descriptors[0] = descriptors[1] = -1;
    return NO;
}

pid_t PLFSpawnHelper(int input, int output) {
    // Auto-reaping destroys PID ownership. Do not change host signal policy.
    struct sigaction disposition;
    if (sigaction(SIGCHLD, NULL, &disposition) != 0 ||
        disposition.sa_handler != SIG_DFL ||
        (disposition.sa_flags & SA_NOCLDWAIT)) return -1;
    if (getuid() != geteuid() || getgid() != getegid()) return -1;
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    if (posix_spawn_file_actions_init(&actions) != 0) return -1;
    if (posix_spawnattr_init(&attributes) != 0) {
        posix_spawn_file_actions_destroy(&actions);
        return -1;
    }
    sigset_t empty, defaults;
    sigemptyset(&empty);
    sigfillset(&defaults);
    int error = posix_spawn_file_actions_adddup2(&actions, input, STDIN_FILENO);
    if (!error) error = posix_spawn_file_actions_adddup2(&actions, output, STDOUT_FILENO);
    // Discard stderr: neither the host log nor any token-bearing diagnostic
    // becomes an authorization input.
    if (!error) error = posix_spawn_file_actions_addopen(&actions, STDERR_FILENO,
                                                        "/dev/null", O_WRONLY, 0);
    if (!error) {
        if (@available(macOS 26.0, *))
            error = posix_spawn_file_actions_addchdir(&actions, "/");
        else
            error = posix_spawn_file_actions_addchdir_np(&actions, "/");
    }
    short flags = POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_RESETIDS |
        POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF;
    if (!error) error = posix_spawnattr_setflags(&attributes, flags);
    if (!error) error = posix_spawnattr_setsigmask(&attributes, &empty);
    if (!error) error = posix_spawnattr_setsigdefault(&attributes, &defaults);
    char *arguments[] = {(char *)PLFHelperPath, NULL};
    // The helper checks the original launch vector before Swift/CF startup.
    // All paths are absolute; no inherited environment is needed.
    char *environment[] = {NULL};
    pid_t pid = -1;
    if (!error) error = posix_spawn(&pid, PLFHelperPath, &actions, &attributes,
                                    arguments, environment);
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    return error ? -1 : pid;
}
