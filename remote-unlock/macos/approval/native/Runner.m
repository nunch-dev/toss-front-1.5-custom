#import "Runner.h"
#import "ChildProcess.h"
#import "CodeTrust.h"
#include <errno.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <signal.h>
#include <stdatomic.h>
#include <sys/event.h>
#include <sys/wait.h>
#include <unistd.h>
#include <os/log.h>

@implementation PLFRunner {
    NSLock *_cancellationLock;
    atomic_bool _cancelled;
    int _cancelRead;
    int _cancelWrite;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _cancelRead = _cancelWrite = -1;
    _cancellationLock = [[NSLock alloc] init];
    atomic_init(&_cancelled, false);
    int descriptors[2];
    if (!PLFMakePipe(descriptors)) return nil;
    _cancelRead = descriptors[0];
    _cancelWrite = descriptors[1];
    return self;
}

- (void)cancel {
    [_cancellationLock lock];
    atomic_store(&_cancelled, true);
    if (_cancelWrite >= 0) { close(_cancelWrite); _cancelWrite = -1; }
    [_cancellationLock unlock];
}

- (void)dealloc {
    if (_cancelRead >= 0) close(_cancelRead);
    if (_cancelWrite >= 0) close(_cancelWrite);
}

- (NSData *)run:(PLFInvocation *)invocation exitStatus:(int *)exitStatus {
    *exitStatus = -1;
    int input[2] = {-1, -1}, output[2] = {-1, -1};
    int executable = -1, events = -1, status = -1;
    pid_t pid = -1;
    BOOL failed = YES, exited = NO, eof = NO;
    NSUInteger lines = 0, lineBytes = 0;
    NSMutableData *bytes = [NSMutableData data];
    mach_timebase_info_data_t timebase;
    if (atomic_load(&_cancelled) || mach_timebase_info(&timebase) != KERN_SUCCESS ||
        !timebase.numer || !timebase.denom) goto cleanup;
    executable = PLFOpenVerifiedHelper();
    if (executable < 0) os_log(OS_LOG_DEFAULT, "PLF_APPROVAL_HELPER_TRUST_REJECTED");
    if (executable < 0 || atomic_load(&_cancelled) ||
        mach_continuous_time() >= invocation.deadline) goto cleanup;
    if (!PLFMakePipe(input) || !PLFMakePipe(output)) goto cleanup;
    if (fcntl(input[1], F_SETNOSIGPIPE, 1) != 0 ||
        fcntl(input[1], F_SETFL, O_NONBLOCK) != 0 ||
        fcntl(output[0], F_SETFL, O_NONBLOCK) != 0) goto cleanup;
    events = kqueue();
    if (events < 0 || fcntl(events, F_SETFD, FD_CLOEXEC) != 0) goto cleanup;
    pid = PLFSpawnHelper(input[0], output[1]);
    if (pid < 0) os_log(OS_LOG_DEFAULT, "PLF_APPROVAL_HELPER_SPAWN_REJECTED");
    if (pid < 0) goto cleanup;
    close(input[0]); input[0] = -1;
    close(output[1]); output[1] = -1;
    {
        struct kevent changes[3];
        EV_SET(&changes[0], (uintptr_t)pid, EVFILT_PROC, EV_ADD | EV_ONESHOT,
               NOTE_EXIT, 0, NULL);
        EV_SET(&changes[1], (uintptr_t)output[0], EVFILT_READ, EV_ADD, 0, 0, NULL);
        EV_SET(&changes[2], (uintptr_t)_cancelRead, EVFILT_READ, EV_ADD, 0, 0, NULL);
        if (kevent(events, changes, 3, NULL, 0, NULL) != 0) goto cleanup;
    }
    // <= 4096 bytes fit in a newly empty pipe. A partial/nonblocking write is
    // a failure, never a truncated invocation. stdin stays open after this.
    if (atomic_load(&_cancelled) || invocation.wire.length == 0 ||
        invocation.wire.length > 4096) goto cleanup;
    {
        ssize_t written;
        do { written = write(input[1], invocation.wire.bytes, invocation.wire.length); }
        while (written < 0 && errno == EINTR && !atomic_load(&_cancelled));
        if (written != (ssize_t)invocation.wire.length) goto cleanup;
    }
    failed = NO;
    while (!failed && (!exited || !eof)) {
        uint64_t now = mach_continuous_time();
        if (atomic_load(&_cancelled) || now >= invocation.deadline) {
            failed = YES; break;
        }
        // Bound each wait to one second so sleep/wake observes continuous time,
        // even though the kernel's relative kevent timeout excludes sleep.
        long double nanos = (long double)(invocation.deadline - now) *
            timebase.numer / timebase.denom;
        uint64_t interval = (uint64_t)MIN(nanos, 1000000000.0L);
        struct timespec timeout = {(time_t)(interval / 1000000000),
                                   (long)(interval % 1000000000)};
        struct kevent ready[3];
        int count = kevent(events, NULL, 0, ready, 3, &timeout);
        if (count < 0) {
            if (errno == EINTR) continue;
            failed = YES; break;
        }
        for (int i = 0; i < count && !failed; i++) {
            if ((ready[i].flags & EV_ERROR) ||
                (ready[i].filter == EVFILT_READ &&
                 ready[i].ident == (uintptr_t)_cancelRead)) { failed = YES; break; }
            if (ready[i].filter == EVFILT_PROC) { exited = YES; continue; }
            for (;;) {
                unsigned char chunk[1024];
                ssize_t length = read(output[0], chunk, sizeof(chunk));
                if (length < 0 && errno == EINTR) continue;
                if (length < 0 && errno == EAGAIN) break;
                if (length < 0) { failed = YES; break; }
                if (length == 0) { eof = YES; break; }
                if (bytes.length + (NSUInteger)length > 8192) { failed = YES; break; }
                for (ssize_t j = 0; j < length; j++) {
                    if (lines == 2 || ++lineBytes > 4096) { failed = YES; break; }
                    if (chunk[j] == '\n') { lines++; lineBytes = 0; }
                }
                if (failed) break;
                [bytes appendBytes:chunk length:(NSUInteger)length];
            }
            if (eof) {
                struct kevent removal;
                EV_SET(&removal, (uintptr_t)output[0], EVFILT_READ, EV_DELETE, 0, 0, NULL);
                if (kevent(events, &removal, 1, NULL, 0, NULL) != 0) failed = YES;
            }
        }
    }
cleanup:
    // Close control input before termination. Only this worker ever signals or
    // reaps pid. Even an exited child keeps its PID until our sole waitpid.
    if (input[1] >= 0) { close(input[1]); input[1] = -1; }
    if (pid > 0) {
        if (!exited) kill(pid, SIGKILL);
        pid_t reaped;
        do { reaped = waitpid(pid, &status, 0); } while (reaped < 0 && errno == EINTR);
        if (reaped != pid || !WIFEXITED(status)) failed = YES;
    }
    for (int i = 0; i < 2; i++) {
        if (input[i] >= 0) close(input[i]);
        if (output[i] >= 0) close(output[i]);
    }
    if (events >= 0) close(events);
    if (executable >= 0) close(executable);
    if (failed || atomic_load(&_cancelled) || lines != 2 || lineBytes != 0)
        return nil;
    *exitStatus = WEXITSTATUS(status);
    return [bytes copy];
}
@end
