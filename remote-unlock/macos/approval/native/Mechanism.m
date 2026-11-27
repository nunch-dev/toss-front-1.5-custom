#import "Mechanism.h"
#import "Runner.h"
#include <mach/mach_time.h>
#include <pthread.h>
#include <time.h>
#include <os/log.h>

@implementation PLFPluginState {
    NSLock *_lock;
    BOOL _claimed;
}
- (instancetype)initWithCallbacks:(const AuthorizationCallbacks *)callbacks {
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        _callbacks.SetResult = callbacks->SetResult;
        _callbacks.DidDeactivate = callbacks->DidDeactivate;
    }
    return self;
}
- (BOOL)claimInvocation {
    [_lock lock];
    BOOL claimed = !_claimed;
    _claimed = YES;
    [_lock unlock];
    return claimed;
}
- (void)finishInvocation {
    [_lock lock];
    _claimed = NO;
    [_lock unlock];
}
@end

@implementation PLFMechanism {
    PLFPluginState *_plugin;
    PLFApprovalMode _mode;
    AuthorizationEngineRef _engine;
    NSCondition *_state;
    PLFInvocation *_invocation;
    PLFRunner *_runner;
    NSData *_output;
    int _exitStatus;
    BOOL _invoked, _cancelled, _destroyed, _committed;
    BOOL _workRunning, _workFinished, _ownsSlot;
    BOOL _deactivationRequested, _deactivated, _callbackRunning;
    pthread_t _callbackThread;
}

- (instancetype)initWithPlugin:(PLFPluginState *)plugin
                       engine:(AuthorizationEngineRef)engine
                         mode:(PLFApprovalMode)mode {
    self = [super init];
    if (self) {
        _plugin = plugin;
        _mode = mode;
        _engine = engine;
        _state = [[NSCondition alloc] init];
    }
    return self;
}

// A callback lease is reserved under _state, then called WITHOUT _state.
// Commit is the linearization point: a prior cancellation prohibits Allow.
// Destroy on another thread waits for the lease. Same-thread reentrant Destroy
// invalidates future leases and returns; the callback's strong owner survives
// until its stack unwinds. Only local bookkeeping follows that callback.
- (void)deliver {
    for (;;) {
        [_state lock];
        if (_destroyed || _callbackRunning || (_workRunning && !_workFinished)) {
            [_state unlock]; return;
        }
        BOOL deactivation = _deactivationRequested && !_deactivated;
        AuthorizationResult result = kAuthorizationResultDeny;
        if (deactivation) {
            _deactivated = YES;
        } else if (_invoked && _workFinished && !_committed &&
                   !_deactivationRequested) {
            // Validate while holding the same lock that commits/cancels. In
            // particular, recheck the response's potentially shorter expiry
            // after the synchronous system-context reads.
            if (!_cancelled && _output && _invocation &&
                [_invocation matchesCurrentContext] &&
                PLFValidateOutput(_output, _invocation, _exitStatus) == PLFDecisionApprove &&
                mach_continuous_time() < _invocation.deadline &&
                (int64_t)time(NULL) < _invocation.expiresAt)
                result = kAuthorizationResultAllow;
            _committed = YES;
        } else {
            [_state unlock]; return;
        }
        _callbackRunning = YES;
        _callbackThread = pthread_self();
        AuthorizationCallbacks callbacks = _plugin.callbacks;
        AuthorizationEngineRef engine = _engine;
        [_state unlock];
        if (deactivation) callbacks.DidDeactivate(engine);
        else {
            os_log(OS_LOG_DEFAULT, "PLF_APPROVAL_RESULT allow=%{public}d helper_exit=%{public}d",
                   result == kAuthorizationResultAllow, _exitStatus);
            callbacks.SetResult(engine, result);
        }
        [_state lock];
        _callbackRunning = NO;
        [_state broadcast];
        [_state unlock];
        // Deactivate may have reentered SetResult. Deliver DidDeactivate only
        // after SetResult returns, without nesting engine callbacks.
    }
}

- (OSStatus)invoke {
    [_state lock];
    if (_destroyed || _deactivationRequested) {
        [_state unlock]; return errAuthorizationDenied;
    }
    if (_invoked) {
        _cancelled = YES;
        [_runner cancel];
        [_state unlock];
        return errAuthorizationDenied;
    }
    _invoked = YES;
    os_log(OS_LOG_DEFAULT, "PLF_APPROVAL_INVOKED");
    _workRunning = YES;
    uint64_t ticks = mach_continuous_time();
    int64_t issuedAt = (int64_t)time(NULL);
    if ([_plugin claimInvocation]) {
        _ownsSlot = YES;
        _invocation = [[PLFInvocation alloc] initAtUnixTime:issuedAt continuousTime:ticks mode:_mode];
        if (_invocation) _runner = [[PLFRunner alloc] init];
    }
    // The block strongly owns self even when Destroy is called reentrantly
    // from SetResult. Engine entry points also retain their current owner.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            int exitStatus = -1;
            NSData *output = self->_runner && self->_invocation ?
                [self->_runner run:self->_invocation exitStatus:&exitStatus] : nil;
            [self->_state lock];
            self->_output = output;
            self->_exitStatus = exitStatus;
            self->_workFinished = YES;
            [self->_state unlock];
            [self deliver];
            [self->_state lock];
            if (self->_ownsSlot) {
                [self->_plugin finishInvocation];
                self->_ownsSlot = NO;
            }
            self->_workRunning = NO;
            [self->_state broadcast];
            [self->_state unlock];
        }
    });
    [_state unlock];
    return errAuthorizationSuccess;
}

- (OSStatus)deactivate {
    [_state lock];
    if (_destroyed) { [_state unlock]; return errAuthorizationSuccess; }
    _cancelled = YES;
    _deactivationRequested = YES;
    [_runner cancel];
    BOOL canDeliver = !_workRunning || _workFinished;
    [_state unlock];
    if (canDeliver) [self deliver];
    return errAuthorizationSuccess;
}

- (void)destroy {
    [_state lock];
    _destroyed = YES;
    _cancelled = YES;
    [_runner cancel];
    BOOL reentrant = _callbackRunning && pthread_equal(_callbackThread, pthread_self());
    // Callbacks only start after run has returned and closed/reaped everything.
    // Reentrant destruction therefore has no child or I/O to wait for.
    while (!reentrant && (_workRunning || _callbackRunning)) [_state wait];
    _engine = NULL;
    [_state unlock];
}
@end
