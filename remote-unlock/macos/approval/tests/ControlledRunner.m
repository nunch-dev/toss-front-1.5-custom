#import "ControlledRunner.h"
#import "../native/Runner.h"

static NSCondition *control;
static BOOL blocked;
static unsigned calls;

void PLFTestRunnerPrepare(BOOL waits) {
    control = [[NSCondition alloc] init];
    blocked = waits;
    calls = 0;
}
BOOL PLFTestRunnerStarted(void) {
    [control lock];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!calls && [control waitUntilDate:deadline]) {}
    BOOL started = calls != 0;
    [control unlock];
    return started;
}
unsigned PLFTestRunnerCalls(void) {
    [control lock];
    unsigned count = calls;
    [control unlock];
    return count;
}
void PLFTestRunnerRelease(void) {
    [control lock];
    blocked = NO;
    [control broadcast];
    [control unlock];
}

@implementation PLFRunner {
    BOOL _cancelled;
}
- (void)cancel {
    [control lock];
    _cancelled = YES;
    [control broadcast];
    [control unlock];
}
- (NSData *)run:(PLFInvocation *)invocation exitStatus:(int *)status {
    [control lock];
    calls++;
    [control broadcast];
    while (blocked && !_cancelled) [control wait];
    [control unlock];
    // A valid response can arrive concurrently with cancellation. Returning it
    // even after cancel tests the owner's commit guard, not this adapter.
    NSMutableDictionary *record = [@{
        @"version": @2, @"kind": @"bound", @"generation": invocation.generation,
        @"mode": invocation.mode, @"account": invocation.account,
        @"context": invocation.context ?: NSNull.null,
        @"requestId": invocation.requestID, @"expiresAt": @(invocation.expiresAt),
        @"requestHash": @"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    } mutableCopy];
    NSMutableData *data = [NSMutableData data];
    [data appendData:[NSJSONSerialization dataWithJSONObject:record options:0 error:NULL]];
    [data appendBytes:"\n" length:1];
    record[@"kind"] = @"result";
    record[@"decision"] = @"approve";
    [data appendData:[NSJSONSerialization dataWithJSONObject:record options:0 error:NULL]];
    [data appendBytes:"\n" length:1];
    *status = 0;
    return data;
}
@end
