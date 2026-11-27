#include <Security/AuthorizationPlugin.h>
#include <Security/AuthSession.h>
#include <CoreGraphics/CGSession.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <os/log.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    const AuthorizationCallbacks *callbacks;
    os_log_t log;
} ProbePlugin;

typedef struct {
    ProbePlugin *plugin;
    AuthorizationEngineRef engine;
} ProbeMechanism;

static OSStatus destroy_plugin(AuthorizationPluginRef reference) {
    ProbePlugin *plugin = reference;
    os_release(plugin->log);
    free(plugin);
    return errAuthorizationSuccess;
}

static OSStatus create_mechanism(AuthorizationPluginRef reference,
                                AuthorizationEngineRef engine,
                                AuthorizationMechanismId name,
                                AuthorizationMechanismRef *output) {
    *output = NULL;
    if (strcmp(name, "probe") != 0) {
        return errAuthorizationInternal;
    }
    ProbeMechanism *mechanism = calloc(1, sizeof(*mechanism));
    if (mechanism == NULL) {
        return errAuthorizationInternal;
    }
    mechanism->plugin = reference;
    mechanism->engine = engine;
    *output = mechanism;
    return errAuthorizationSuccess;
}

static OSStatus invoke_mechanism(AuthorizationMechanismRef reference) {
    ProbeMechanism *mechanism = reference;
    SecuritySessionId session = noSecuritySession;
    SessionAttributeBits attributes = 0;
    OSStatus session_status = SessionGetInfo(callerSecuritySession, &session, &attributes);
    AuthorizationSessionId evaluation = NULL;
    OSStatus evaluation_status = errAuthorizationInternal;
    if (mechanism->plugin->callbacks->GetSessionId != NULL) {
        evaluation_status = mechanism->plugin->callbacks->GetSessionId(
            mechanism->engine, &evaluation);
    }
    uid_t console_uid = (uid_t)-1;
    CFStringRef console_user = SCDynamicStoreCopyConsoleUser(NULL, &console_uid, NULL);
    if (console_user != NULL) CFRelease(console_user);
    int64_t cg_uid = -1;
    Boolean on_console = false, login_done = false;
    CFDictionaryRef context = CGSessionCopyCurrentDictionary();
    if (context != NULL) {
        CFTypeRef uid = CFDictionaryGetValue(context, kCGSessionUserIDKey);
        if (uid != NULL && CFGetTypeID(uid) == CFNumberGetTypeID())
            CFNumberGetValue(uid, kCFNumberSInt64Type, &cg_uid);
        CFTypeRef console = CFDictionaryGetValue(context, kCGSessionOnConsoleKey);
        CFTypeRef login = CFDictionaryGetValue(context, kCGSessionLoginDoneKey);
        on_console = console != NULL && CFEqual(console, kCFBooleanTrue);
        login_done = login != NULL && CFEqual(login, kCFBooleanTrue);
        CFRelease(context);
    }
    // These describe the caller/console, NOT an authenticated unlock target.
    // Never log the opaque evaluation pointer, usernames, hints or credentials.
    os_log(mechanism->plugin->log,
           "AUTH_PROBE_CONTEXT uid=%{public}u euid=%{public}u "
           "caller_session=%{public}u session_status=%{public}d attributes=%{public}u "
           "evaluation_status=%{public}d evaluation_present=%{public}d "
           "console_uid=%{public}u cg_uid=%{public}lld on_console=%{public}d login_done=%{public}d",
           (unsigned)getuid(), (unsigned)geteuid(), (unsigned)session,
           (int)session_status, (unsigned)attributes, (int)evaluation_status,
           evaluation != NULL, (unsigned)console_uid, (long long)cg_uid,
           (int)on_console, (int)login_done);
    os_log(mechanism->plugin->log, "AUTH_PROBE_INVOKED result=deny");
    return mechanism->plugin->callbacks->SetResult(mechanism->engine,
                                                   kAuthorizationResultDeny);
}

static OSStatus deactivate_mechanism(AuthorizationMechanismRef reference) {
    ProbeMechanism *mechanism = reference;
    return mechanism->plugin->callbacks->DidDeactivate(mechanism->engine);
}

static OSStatus destroy_mechanism(AuthorizationMechanismRef reference) {
    free(reference);
    return errAuthorizationSuccess;
}

static const AuthorizationPluginInterface interface = {
    .version = kAuthorizationPluginInterfaceVersion,
    .PluginDestroy = destroy_plugin,
    .MechanismCreate = create_mechanism,
    .MechanismInvoke = invoke_mechanism,
    .MechanismDeactivate = deactivate_mechanism,
    .MechanismDestroy = destroy_mechanism,
};

OSStatus AuthorizationPluginCreate(const AuthorizationCallbacks *callbacks,
                                  AuthorizationPluginRef *output,
                                  const AuthorizationPluginInterface **output_interface) {
    *output = NULL;
    *output_interface = NULL;
    ProbePlugin *plugin = calloc(1, sizeof(*plugin));
    if (plugin == NULL) {
        return errAuthorizationInternal;
    }
    plugin->callbacks = callbacks;
    plugin->log = os_log_create("org.plf02wh.remoteunlock.authprobe", "mechanism");
    *output = plugin;
    *output_interface = &interface;
    return errAuthorizationSuccess;
}
