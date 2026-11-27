#include <Security/AuthorizationPlugin.h>
#include <dlfcn.h>
#include <stdio.h>

typedef OSStatus (*CreatePlugin)(const AuthorizationCallbacks *,
                                AuthorizationPluginRef *,
                                const AuthorizationPluginInterface **);

typedef struct {
    unsigned results;
    unsigned deactivations;
    AuthorizationResult result;
} Receipt;

static OSStatus receive_result(AuthorizationEngineRef engine, AuthorizationResult result) {
    Receipt *receipt = (Receipt *)engine;
    receipt->results++;
    receipt->result = result;
    return errAuthorizationSuccess;
}

static OSStatus receive_deactivation(AuthorizationEngineRef engine) {
    Receipt *receipt = (Receipt *)engine;
    receipt->deactivations++;
    return errAuthorizationSuccess;
}

#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "PROBE_SELF_TEST_FAILED line=%d\n", __LINE__); \
        return 1; \
    } \
} while (0)

int main(int argc, char **argv) {
    CHECK(argc == 2);
    void *module = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (module == NULL) {
        fprintf(stderr, "PROBE_LOAD_FAILED %s\n", dlerror());
        return 1;
    }
    CreatePlugin create = (CreatePlugin)dlsym(module, "AuthorizationPluginCreate");
    CHECK(create != NULL);
    AuthorizationCallbacks callbacks = {0};
    callbacks.version = kAuthorizationCallbacksVersion;
    callbacks.SetResult = receive_result;
    callbacks.DidDeactivate = receive_deactivation;
    AuthorizationPluginRef plugin = NULL;
    const AuthorizationPluginInterface *interface = NULL;
    CHECK(create(&callbacks, &plugin, &interface) == errAuthorizationSuccess);
    CHECK(plugin != NULL && interface != NULL);
    CHECK(interface->version == kAuthorizationPluginInterfaceVersion);
    Receipt receipt = {0};
    AuthorizationMechanismRef mechanism = NULL;
    CHECK(interface->MechanismCreate(plugin, (AuthorizationEngineRef)&receipt,
                                    "unknown", &mechanism) != errAuthorizationSuccess);
    CHECK(mechanism == NULL);
    CHECK(interface->MechanismCreate(plugin, (AuthorizationEngineRef)&receipt,
                                    "probe", &mechanism) == errAuthorizationSuccess);
    CHECK(interface->MechanismInvoke(mechanism) == errAuthorizationSuccess);
    CHECK(receipt.results == 1 && receipt.result == kAuthorizationResultDeny);
    CHECK(interface->MechanismDeactivate(mechanism) == errAuthorizationSuccess);
    CHECK(receipt.deactivations == 1);
    CHECK(interface->MechanismDestroy(mechanism) == errAuthorizationSuccess);
    CHECK(interface->PluginDestroy(plugin) == errAuthorizationSuccess);
    CHECK(dlclose(module) == 0);
    puts("PROBE_SELF_TEST_OK local_callback_test_only");
    return 0;
}
