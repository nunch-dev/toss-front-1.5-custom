#import "Models.h"
#import <Security/SecRandom.h>
#include <mach/mach_time.h>
#include <os/log.h>

@implementation PLFInvocation {
    PLFScreenContext _screenContext;
}
- (instancetype)initAtUnixTime:(int64_t)issuedAt
               continuousTime:(uint64_t)ticks
                         mode:(PLFApprovalMode)mode {
    self = [super init];
    if (!self) return nil;
    if (issuedAt < 0 || issuedAt > INT64_C(9007199254740961)) return nil;
    switch (mode) {
        case PLFApprovalModeIsolated:
            _mode = @"isolated-right-test";
            _account = @"isolated-right-test";
            break;
        case PLFApprovalModeScreenTrial:
            if (!PLFCaptureScreenContext(&_screenContext)) {
                os_log(OS_LOG_DEFAULT, "PLF_APPROVAL_CONTEXT_REJECTED");
                return nil;
            }
            _mode = @"screen-trial";
            _account = [NSString stringWithFormat:@"screen-trial-uid-%u", _screenContext.consoleUID];
            _context = @{
                @"executionUID": @(_screenContext.executionUID),
                @"callerSecuritySession": @(_screenContext.callerSecuritySession),
                @"attributes": @(_screenContext.attributes),
                @"consoleUID": @(_screenContext.consoleUID),
                @"cgUID": @(_screenContext.cgUID),
                @"onConsole": @(_screenContext.onConsole),
                @"loginDone": @(_screenContext.loginDone)
            };
            break;
        default:
            return nil;
    }
    uint8_t bytes[32];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) return nil;
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.numer == 0) return nil;
    uint64_t duration = UINT64_C(30000000000) * timebase.denom / timebase.numer;
    if (ticks > UINT64_MAX - duration) return nil;
    _deadline = ticks + duration;
    _expiresAt = issuedAt + 30;
    _generation = NSUUID.UUID.UUIDString.lowercaseString;
    _requestID = NSUUID.UUID.UUIDString.lowercaseString;
    NSString *nonce = [[NSData dataWithBytes:bytes length:sizeof(bytes)] base64EncodedStringWithOptions:0];
    nonce = [[[nonce stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
                      stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
                      stringByReplacingOccurrencesOfString:@"=" withString:@""];
    NSDictionary *fields = @{
        @"version": @2, @"mode": _mode, @"account": _account,
        @"context": _context ?: NSNull.null,
        @"generation": _generation, @"requestId": _requestID,
        @"nonce": nonce, @"issuedAt": @(issuedAt), @"expiresAt": @(_expiresAt)
    };
    NSError *error = nil;
    NSData *encoded = [NSJSONSerialization dataWithJSONObject:fields options:0 error:&error];
    if (!encoded || error) return nil;
    NSMutableData *line = [encoded mutableCopy];
    [line appendBytes:"\n" length:1];
    _wire = [line copy];
    return self;
}

- (BOOL)matchesCurrentContext {
    if (_context == nil) return YES;
    PLFScreenContext current;
    return PLFCaptureScreenContext(&current) &&
        PLFScreenContextsEqual(&_screenContext, &current);
}
@end
