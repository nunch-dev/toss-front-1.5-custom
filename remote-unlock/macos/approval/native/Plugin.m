#import "Mechanism.h"
#include <string.h>

static OSStatus DestroyPlugin(AuthorizationPluginRef reference) {
    @autoreleasepool {
        (void)CFBridgingRelease(reference);
        return errAuthorizationSuccess;
    }
}

static OSStatus CreateMechanism(AuthorizationPluginRef reference,
                                AuthorizationEngineRef engine,
                                AuthorizationMechanismId name,
                                AuthorizationMechanismRef *output) {
    @autoreleasepool {
        if (!output) return errAuthorizationInternal;
        *output = NULL;
        if (!reference || !engine || !name) return errAuthorizationInternal;
        PLFApprovalMode mode;
        if (strcmp(name, "approval") == 0) mode = PLFApprovalModeIsolated;
        else if (strcmp(name, "screen-trial") == 0) mode = PLFApprovalModeScreenTrial;
        else return errAuthorizationInternal;
        PLFPluginState *plugin = (__bridge PLFPluginState *)reference;
        PLFMechanism *mechanism = [[PLFMechanism alloc] initWithPlugin:plugin engine:engine mode:mode];
        if (!mechanism) return errAuthorizationInternal;
        *output = (__bridge_retained void *)mechanism;
        return errAuthorizationSuccess;
    }
}

static OSStatus InvokeMechanism(AuthorizationMechanismRef reference) {
    @autoreleasepool {
        if (!reference) return errAuthorizationInternal;
        __attribute__((objc_precise_lifetime))
        PLFMechanism *mechanism = (__bridge PLFMechanism *)reference;
        return [mechanism invoke];
    }
}

static OSStatus DeactivateMechanism(AuthorizationMechanismRef reference) {
    @autoreleasepool {
        if (!reference) return errAuthorizationInternal;
        __attribute__((objc_precise_lifetime))
        PLFMechanism *mechanism = (__bridge PLFMechanism *)reference;
        return [mechanism deactivate];
    }
}

static OSStatus DestroyMechanism(AuthorizationMechanismRef reference) {
    @autoreleasepool {
        if (!reference) return errAuthorizationInternal;
        __attribute__((objc_precise_lifetime))
        PLFMechanism *mechanism = CFBridgingRelease(reference);
        [mechanism destroy];
        return errAuthorizationSuccess;
    }
}

static const AuthorizationPluginInterface Interface = {
    .version = kAuthorizationPluginInterfaceVersion,
    .PluginDestroy = DestroyPlugin,
    .MechanismCreate = CreateMechanism,
    .MechanismInvoke = InvokeMechanism,
    .MechanismDeactivate = DeactivateMechanism,
    .MechanismDestroy = DestroyMechanism
};

__attribute__((visibility("default")))
OSStatus AuthorizationPluginCreate(const AuthorizationCallbacks *callbacks,
                                  AuthorizationPluginRef *output,
                                  const AuthorizationPluginInterface **interface) {
    @autoreleasepool {
        if (!output || !interface) return errAuthorizationInternal;
        *output = NULL;
        *interface = NULL;
        if (!callbacks || !callbacks->SetResult || !callbacks->DidDeactivate)
            return errAuthorizationInternal;
        PLFPluginState *plugin = [[PLFPluginState alloc] initWithCallbacks:callbacks];
        if (!plugin) return errAuthorizationInternal;
        *output = (__bridge_retained void *)plugin;
        *interface = &Interface;
        return errAuthorizationSuccess;
    }
}
