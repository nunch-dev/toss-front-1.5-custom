#import "../native/Mechanism.h"
#import "ControlledRunner.h"
#include "ControlledContext.h"
#include <stdio.h>
#include <stdlib.h>

static const AuthorizationPluginInterface *api;
static unsigned checks;
static void require(BOOL okay, const char *name) {
    if (!okay) { fprintf(stderr, "FAIL %s\n", name); exit(1); }
    checks++;
}
@interface Receipt : NSObject
@property NSCondition *condition;
@property AuthorizationMechanismRef mechanism;
@property unsigned results;
@property unsigned deactivations;
@property AuthorizationResult result;
@property BOOL destroyOnResult;
@property BOOL deactivateOnResult;
@property BOOL destroyed;
- (BOOL)waitForDeactivation:(BOOL)deactivation;
@end
@implementation Receipt
- (instancetype)init {
    self = [super init];
    if (self) _condition = [[NSCondition alloc] init];
    return self;
}
- (BOOL)waitForDeactivation:(BOOL)deactivation {
    [_condition lock];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!(deactivation ? _deactivations : _results)) {
        if (![_condition waitUntilDate:limit]) break;
    }
    BOOL ready = deactivation ? _deactivations != 0 : _results != 0;
    [_condition unlock];
    return ready;
}
@end

static OSStatus result(AuthorizationEngineRef engine, AuthorizationResult value) {
    Receipt *receipt = (__bridge Receipt *)engine;
    if (receipt.destroyOnResult) {
        api->MechanismDestroy(receipt.mechanism);
        receipt.destroyed = YES;
    }
    if (receipt.deactivateOnResult) api->MechanismDeactivate(receipt.mechanism);
    [receipt.condition lock];
    receipt.result = value;
    receipt.results++;
    [receipt.condition broadcast];
    [receipt.condition unlock];
    return errAuthorizationSuccess;
}
static OSStatus deactivated(AuthorizationEngineRef engine) {
    Receipt *receipt = (__bridge Receipt *)engine;
    [receipt.condition lock];
    receipt.deactivations++;
    [receipt.condition broadcast];
    [receipt.condition unlock];
    return errAuthorizationSuccess;
}
static Receipt *create(AuthorizationPluginRef plugin, const char *mode) {
    Receipt *receipt = [[Receipt alloc] init];
    AuthorizationMechanismRef mechanism = NULL;
    require(api->MechanismCreate(plugin, (__bridge void *)receipt, mode, &mechanism) == 0,
            "create mechanism");
    receipt.mechanism = mechanism;
    return receipt;
}
static AuthorizationPluginRef plugin(void) {
    AuthorizationCallbacks callbacks = {0};
    callbacks.version = kAuthorizationCallbacksVersion;
    callbacks.SetResult = result;
    callbacks.DidDeactivate = deactivated;
    AuthorizationPluginRef reference = NULL;
    require(AuthorizationPluginCreate(&callbacks, &reference, &api) == 0, "create plugin");
    return reference;
}

int main(void) {
    @autoreleasepool {
        PLFTestRunnerPrepare(NO);
        AuthorizationPluginRef reference = plugin();
        for (unsigned index = 0; index < 2; index++) {
            Receipt *receipt = create(reference, "approval");
            require(api->MechanismInvoke(receipt.mechanism) == 0, "invoke");
            require([receipt waitForDeactivation:NO], "receive result");
            api->MechanismDestroy(receipt.mechanism);
            require(receipt.results == 1 && receipt.result == kAuthorizationResultAllow,
                    "one matching approval");
        }
        require(PLFTestRunnerCalls() == 2, "allow sequential mechanisms after cleanup");
        api->PluginDestroy(reference);

        PLFTestRunnerPrepare(YES);
        reference = plugin();
        Receipt *first = create(reference, "approval");
        api->MechanismInvoke(first.mechanism);
        require(PLFTestRunnerStarted(), "active worker reached");
        Receipt *overlap = create(reference, "approval");
        api->MechanismInvoke(overlap.mechanism);
        require([overlap waitForDeactivation:NO], "overlap result");
        api->MechanismDestroy(overlap.mechanism);
        require(overlap.result == kAuthorizationResultDeny && PLFTestRunnerCalls() == 1,
                "reject overlapping mechanism without spawning");
        api->MechanismDeactivate(first.mechanism);
        require([first waitForDeactivation:YES], "cancellation acknowledged");
        api->MechanismDestroy(first.mechanism);
        require(first.results == 0 && first.deactivations == 1, "late approval cannot beat cancellation");
        api->PluginDestroy(reference);

        PLFTestRunnerPrepare(YES);
        reference = plugin();
        Receipt *twice = create(reference, "approval");
        api->MechanismInvoke(twice.mechanism);
        require(PLFTestRunnerStarted(), "reinvoke worker reached");
        require(api->MechanismInvoke(twice.mechanism) == errAuthorizationDenied, "reject reinvoke");
        require([twice waitForDeactivation:NO], "reinvoke produces denial");
        api->MechanismDestroy(twice.mechanism);
        require(twice.results == 1 && twice.result == kAuthorizationResultDeny, "reinvoke never allows");
        api->PluginDestroy(reference);

        PLFTestRunnerPrepare(YES);
        reference = plugin();
        Receipt *destroyed = create(reference, "approval");
        api->MechanismInvoke(destroyed.mechanism);
        require(PLFTestRunnerStarted(), "destroy worker reached");
        api->MechanismDestroy(destroyed.mechanism);
        require(destroyed.results == 0 && destroyed.deactivations == 0, "destroy drains without callbacks");
        api->PluginDestroy(reference);

        PLFTestRunnerPrepare(NO);
        reference = plugin();
        Receipt *early = create(reference, "approval");
        api->MechanismDeactivate(early.mechanism);
        api->MechanismDeactivate(early.mechanism);
        require(api->MechanismInvoke(early.mechanism) == errAuthorizationDenied, "deactivated cannot invoke");
        api->MechanismDestroy(early.mechanism);
        require(early.deactivations == 1 && early.results == 0, "deactivate exactly once");
        api->PluginDestroy(reference);

        PLFTestRunnerPrepare(NO);
        reference = plugin();
        Receipt *reentrant = create(reference, "approval");
        reentrant.deactivateOnResult = YES;
        api->MechanismInvoke(reentrant.mechanism);
        require([reentrant waitForDeactivation:YES], "reentrant deactivate completes");
        api->MechanismDestroy(reentrant.mechanism);
        require(reentrant.results == 1 && reentrant.deactivations == 1, "reentrant callbacks once");
        api->PluginDestroy(reference);

        PLFTestRunnerPrepare(NO);
        reference = plugin();
        Receipt *reentrantDestroy = create(reference, "approval");
        reentrantDestroy.destroyOnResult = YES;
        api->MechanismInvoke(reentrantDestroy.mechanism);
        require([reentrantDestroy waitForDeactivation:NO], "reentrant destroy completes");
        require(reentrantDestroy.destroyed && reentrantDestroy.results == 1, "reentrant owner retained");
        api->PluginDestroy(reference);

        reference = plugin();
        for (NSString *scenario in @[@"stable", @"missing-before", @"missing-after",
                                      @"session", @"execution", @"console", @"attributes"]) {
            PLFScreenContext context = PLFTestScreenContext();
            PLFTestContextSet([scenario isEqual:@"missing-before"] ? NULL : &context);
            PLFTestRunnerPrepare(YES);
            Receipt *screen = create(reference, "screen-trial");
            require(api->MechanismInvoke(screen.mechanism) == 0, "invoke screen mode");
            if (![scenario isEqual:@"missing-before"]) {
                require(PLFTestRunnerStarted(), "screen worker reached");
                if ([scenario isEqual:@"session"]) context.callerSecuritySession++;
                if ([scenario isEqual:@"execution"]) context.executionUID++;
                if ([scenario isEqual:@"console"]) context.consoleUID = context.cgUID = 502;
                if ([scenario isEqual:@"attributes"]) context.attributes |= 0x20;
                PLFTestContextSet([scenario isEqual:@"missing-after"] ? NULL : &context);
                PLFTestRunnerRelease();
            }
            require([screen waitForDeactivation:NO], "screen mode produces terminal result");
            api->MechanismDestroy(screen.mechanism);
            AuthorizationResult expected = [scenario isEqual:@"stable"] ?
                kAuthorizationResultAllow : kAuthorizationResultDeny;
            require(screen.results == 1 && screen.result == expected,
                    [NSString stringWithFormat:@"screen context %@ result", scenario].UTF8String);
            require(PLFTestRunnerCalls() == ([scenario isEqual:@"missing-before"] ? 0u : 1u),
                    "missing initial context cannot start helper");
        }
        api->PluginDestroy(reference);
        printf("NATIVE_OWNER_OK checks=%u local_callback_test_only\n", checks);
    }
    return 0;
}
