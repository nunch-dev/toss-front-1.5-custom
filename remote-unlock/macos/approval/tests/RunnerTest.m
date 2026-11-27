#import "../native/Runner.h"
#import "../native/ChildProcess.h"
#import "../native/CodeTrust.h"
#include <errno.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <poll.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

// Test-link replacements for trust/launch boundaries only. Runner.m and its
// kqueue, cancellation, bounds, signal and waitpid logic are the real owner.
static const char *fixture;
static const char *mode;
static int readiness[2];
static pid_t child;
static unsigned checks;
static void require(BOOL value, const char *name) {
    if (!value) { fprintf(stderr, "FAIL %s\n", name); exit(1); }
    checks++;
}
int PLFOpenVerifiedHelper(void) {
    return open("/dev/null", O_RDONLY | O_CLOEXEC);
}
pid_t PLFSpawnHelper(int input, int output) {
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    require(posix_spawn_file_actions_init(&actions) == 0, "fixture actions");
    require(posix_spawnattr_init(&attributes) == 0, "fixture attributes");
    require(posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT) == 0,
            "fixture closes unrelated descriptors");
    require(posix_spawn_file_actions_adddup2(&actions, input, 0) == 0, "fixture input");
    require(posix_spawn_file_actions_adddup2(&actions, output, 1) == 0, "fixture output");
    require(posix_spawn_file_actions_adddup2(&actions, readiness[1], 3) == 0, "fixture readiness");
    char *arguments[] = {(char *)fixture, (char *)mode, NULL};
    char *environment[] = {NULL};
    int result = posix_spawn(&child, fixture, &actions, &attributes, arguments, environment);
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    return result == 0 ? child : -1;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        require(argc == 2, "fixture path supplied");
        fixture = argv[1];
        for (NSString *scenario in @[@"normal", @"crash", @"flood", @"stall"]) {
            mode = scenario.UTF8String;
            fprintf(stderr, "RUNNER_SCENARIO %s\n", mode);
            child = -1;
            require(PLFMakePipe(readiness), "readiness pipe");
            PLFRunner *runner = [[PLFRunner alloc] init];
            PLFInvocation *invocation = [[PLFInvocation alloc]
                initAtUnixTime:(int64_t)NSDate.date.timeIntervalSince1970
                continuousTime:mach_continuous_time() mode:PLFApprovalModeIsolated];
            require(runner != nil && invocation != nil, "runner created");
            dispatch_group_t work = dispatch_group_create();
            __block NSData *result = nil;
            __block int status = -1;
            dispatch_group_async(work, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                result = [runner run:invocation exitStatus:&status];
            });
            struct pollfd ready = {.fd = readiness[0], .events = POLLIN};
            require(poll(&ready, 1, 3000) == 1, "child entered actual pipe exchange");
            char byte;
            require(read(readiness[0], &byte, 1) == 1 && byte == 'R', "child ready");
            if ([scenario isEqual:@"stall"]) [runner cancel];
            require(dispatch_group_wait(work, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0,
                    "runner completes and drains");
            if ([scenario isEqual:@"normal"] || [scenario isEqual:@"crash"]) {
                require([result isEqual:[@"bound\nresult\n" dataUsingEncoding:NSUTF8StringEncoding]],
                        "actual child output preserved");
                require(status == ([scenario isEqual:@"crash"] ? 7 : 0), "child status preserved");
            } else {
                require(result == nil && status == -1, "cancelled or oversized child rejected");
            }
            int reaped;
            errno = 0;
            require(waitpid(child, &reaped, WNOHANG) == -1 && errno == ECHILD,
                    "owned child already reaped");
            close(readiness[0]);
            close(readiness[1]);
        }
        printf("NATIVE_RUNNER_OK checks=%u real_children_test_launch_adapter\n", checks);
    }
    return 0;
}
