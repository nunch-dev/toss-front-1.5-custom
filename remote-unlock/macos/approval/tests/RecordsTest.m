#import "../native/Models.h"
#include "ControlledContext.h"
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
static void require(BOOL condition, const char *name) {
    if (!condition) {
        fprintf(stderr, "FAIL %s\n", name);
        exit(1);
    }
    checks++;
}

static NSArray<NSMutableDictionary *> *frames(PLFInvocation *invocation) {
    NSMutableDictionary *bound = [@{
        @"version": @2, @"kind": @"bound", @"generation": invocation.generation,
        @"mode": invocation.mode, @"account": invocation.account,
        @"context": invocation.context ?: NSNull.null,
        @"requestId": invocation.requestID,
        @"requestHash": @"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        @"expiresAt": @(invocation.expiresAt)
    } mutableCopy];
    NSMutableDictionary *result = [bound mutableCopy];
    result[@"kind"] = @"result";
    result[@"decision"] = @"approve";
    return @[bound, result];
}

static NSData *encode(NSArray *values) {
    NSMutableData *data = [NSMutableData data];
    for (id value in values) {
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
        if (!json || error) abort();
        [data appendData:json];
        [data appendBytes:"\n" length:1];
    }
    return data;
}

int main(void) {
    @autoreleasepool {
        int64_t now = (int64_t)NSDate.date.timeIntervalSince1970;
        PLFInvocation *invocation = [[PLFInvocation alloc]
            initAtUnixTime:now continuousTime:mach_continuous_time() mode:PLFApprovalModeIsolated];
        require(invocation != nil, "create invocation");
        NSDictionary *isolatedWire = [NSJSONSerialization JSONObjectWithData:invocation.wire
                                                                    options:0 error:NULL];
        require([isolatedWire[@"version"] isEqual:@2] &&
                [isolatedWire[@"mode"] isEqual:@"isolated-right-test"] &&
                [isolatedWire[@"account"] isEqual:@"isolated-right-test"] &&
                isolatedWire[@"context"] == NSNull.null, "encode isolated local contract v2");
        require(PLFValidateOutput(encode(frames(invocation)), invocation, 0) ==
                PLFDecisionApprove, "accept matching approval");
        NSArray *denied = frames(invocation);
        denied[1][@"decision"] = @"deny";
        require(PLFValidateOutput(encode(denied), invocation, 0) ==
                PLFDecisionDeny, "preserve signed denial");

        NSArray<NSDictionary *> *cases = @[
            @{@"name": @"wrong generation", @"target": @1, @"key": @"generation", @"value": NSUUID.UUID.UUIDString},
            @{@"name": @"wrong request", @"target": @1, @"key": @"requestId", @"value": NSUUID.UUID.UUIDString},
            @{@"name": @"wrong bound generation", @"target": @0, @"key": @"generation", @"value": @"wrong"},
            @{@"name": @"wrong bound request", @"target": @0, @"key": @"requestId", @"value": @"wrong"},
            @{@"name": @"mismatched hash", @"target": @1, @"key": @"requestHash", @"value": @"BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"},
            @{@"name": @"noncanonical hash", @"target": @0, @"key": @"requestHash", @"value": @"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB"},
            @{@"name": @"wrong hash type", @"target": @0, @"key": @"requestHash", @"value": @1},
            @{@"name": @"expired decision", @"target": @1, @"key": @"expiresAt", @"value": @0},
            @{@"name": @"extended decision", @"target": @1, @"key": @"expiresAt", @"value": @(invocation.expiresAt + 1)},
            @{@"name": @"changed bound expiry", @"target": @0, @"key": @"expiresAt", @"value": @(invocation.expiresAt - 1)},
            @{@"name": @"boolean expiry", @"target": @1, @"key": @"expiresAt", @"value": @YES},
            @{@"name": @"fractional expiry", @"target": @1, @"key": @"expiresAt", @"value": @(now + 10.5)},
            @{@"name": @"boolean version", @"target": @0, @"key": @"version", @"value": @YES},
            @{@"name": @"wrong version", @"target": @1, @"key": @"version", @"value": @1},
            @{@"name": @"wrong mode", @"target": @1, @"key": @"mode", @"value": @"screen-trial"},
            @{@"name": @"wrong account", @"target": @0, @"key": @"account", @"value": @"screen-trial-uid-501"},
            @{@"name": @"isolated context forbidden", @"target": @1, @"key": @"context", @"value": @{}},
            @{@"name": @"missing context field", @"target": @0, @"key": @"context", @"value": NSNull.null},
            @{@"name": @"unknown decision", @"target": @1, @"key": @"decision", @"value": @"allow"},
            @{@"name": @"wrong decision type", @"target": @1, @"key": @"decision", @"value": @YES},
            @{@"name": @"wrong result kind", @"target": @1, @"key": @"kind", @"value": @"bound"},
            @{@"name": @"unknown field", @"target": @0, @"key": @"extra", @"value": @1},
            @{@"name": @"missing decision", @"target": @1, @"key": @"decision", @"value": NSNull.null}
        ];
        for (NSDictionary *test in cases) {
            NSArray<NSMutableDictionary *> *pair = frames(invocation);
            NSMutableDictionary *target = pair[[test[@"target"] unsignedIntegerValue]];
            if (test[@"value"] == NSNull.null) [target removeObjectForKey:test[@"key"]];
            else target[test[@"key"]] = test[@"value"];
            require(PLFValidateOutput(encode(pair), invocation, 0) == PLFDecisionInvalid,
                    [test[@"name"] UTF8String]);
        }
        NSData *valid = encode(frames(invocation));
        require(PLFValidateOutput(valid, invocation, 1) == PLFDecisionInvalid, "nonzero exit");
        require(PLFValidateOutput([valid subdataWithRange:NSMakeRange(0, valid.length - 1)],
                                 invocation, 0) == PLFDecisionInvalid, "truncated output");
        require(PLFValidateOutput(encode(@[frames(invocation)[0]]), invocation, 0) ==
                PLFDecisionInvalid, "missing result");
        NSArray *pair = frames(invocation);
        require(PLFValidateOutput(encode(@[pair[1], pair[0]]), invocation, 0) ==
                PLFDecisionInvalid, "reordered frames");
        require(PLFValidateOutput(encode(@[pair[0], pair[1], pair[1]]), invocation, 0) ==
                PLFDecisionInvalid, "extra result");
        require(PLFValidateOutput([NSMutableData dataWithLength:8193], invocation, 0) ==
                PLFDecisionInvalid, "oversized output");
        PLFInvocation *other = [[PLFInvocation alloc]
            initAtUnixTime:now continuousTime:mach_continuous_time() mode:PLFApprovalModeIsolated];
        require(PLFValidateOutput(valid, other, 0) == PLFDecisionInvalid, "cross invocation replay");
        PLFInvocation *past = [[PLFInvocation alloc]
            initAtUnixTime:now - 31 continuousTime:mach_continuous_time() mode:PLFApprovalModeIsolated];
        require(PLFValidateOutput(encode(frames(past)), past, 0) ==
                PLFDecisionInvalid, "wall clock expiry");
        PLFInvocation *elapsed = [[PLFInvocation alloc]
            initAtUnixTime:now continuousTime:0 mode:PLFApprovalModeIsolated];
        require(PLFValidateOutput(encode(frames(elapsed)), elapsed, 0) ==
                PLFDecisionInvalid, "continuous clock expiry");
        PLFScreenContext context = PLFTestScreenContext();
        PLFTestContextSet(&context);
        PLFInvocation *screen = [[PLFInvocation alloc]
            initAtUnixTime:now continuousTime:mach_continuous_time() mode:PLFApprovalModeScreenTrial];
        require(screen != nil && [screen.account isEqual:@"screen-trial-uid-501"],
                "screen account uses captured console");
        NSDictionary *screenWire = [NSJSONSerialization JSONObjectWithData:screen.wire
                                                                  options:0 error:NULL];
        require([screenWire[@"version"] isEqual:@2] &&
                [screenWire[@"mode"] isEqual:@"screen-trial"] &&
                [screenWire[@"account"] isEqual:@"screen-trial-uid-501"] &&
                [screenWire[@"context"] isEqual:screen.context] &&
                CFGetTypeID((__bridge CFTypeRef)screenWire[@"context"][@"onConsole"]) == CFBooleanGetTypeID(),
                "encode typed screen context in local contract v2");
        require(PLFValidateOutput(encode(frames(screen)), screen, 0) == PLFDecisionApprove,
                "matching screen context accepted");
        for (NSNumber *target in @[@0, @1]) {
            for (NSString *key in screen.context) {
                NSArray<NSMutableDictionary *> *values = frames(screen);
                NSMutableDictionary *changed = [screen.context mutableCopy];
                changed[key] = [@[@"onConsole", @"loginDone"] containsObject:key] ?
                    @NO : @([changed[key] unsignedLongLongValue] + 1);
                values[target.unsignedIntegerValue][@"context"] = changed;
                require(PLFValidateOutput(encode(values), screen, 0) == PLFDecisionInvalid,
                        "changed context field rejected in either frame");
            }
        }
        for (NSDictionary *change in @[
            @{@"executionUID": @YES}, @{@"onConsole": @1}, @{@"loginDone": @1},
            @{@"attributes": @16.5}, @{@"extra": @1}
        ]) {
            NSArray<NSMutableDictionary *> *values = frames(screen);
            NSMutableDictionary *changed = [screen.context mutableCopy];
            [changed addEntriesFromDictionary:change];
            values[1][@"context"] = changed;
            require(PLFValidateOutput(encode(values), screen, 0) == PLFDecisionInvalid,
                    "malformed context rejected");
        }
        NSArray<NSMutableDictionary *> *missingContext = frames(screen);
        missingContext[1][@"context"] = NSNull.null;
        require(PLFValidateOutput(encode(missingContext), screen, 0) == PLFDecisionInvalid,
                "screen context required");
        context.callerSecuritySession = 1;
        PLFTestContextSet(&context);
        PLFInvocation *smallSession = [[PLFInvocation alloc]
            initAtUnixTime:now continuousTime:mach_continuous_time() mode:PLFApprovalModeScreenTrial];
        require(smallSession != nil, "opaque session identifier one is valid");
        NSArray<NSMutableDictionary *> *booleanSession = frames(smallSession);
        NSMutableDictionary *typedContext = [smallSession.context mutableCopy];
        typedContext[@"callerSecuritySession"] = @YES;
        booleanSession[1][@"context"] = typedContext;
        require(PLFValidateOutput(encode(booleanSession), smallSession, 0) == PLFDecisionInvalid,
                "boolean cannot stand for numeric session one");
        PLFTestContextSet(NULL);
        require([[PLFInvocation alloc] initAtUnixTime:now continuousTime:mach_continuous_time()
                                               mode:PLFApprovalModeScreenTrial] == nil,
                "unavailable screen context prevents invocation");
        printf("NATIVE_RECORDS_OK checks=%u\n", checks);
    }
    return 0;
}
