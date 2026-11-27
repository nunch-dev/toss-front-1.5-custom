#include <Security/Authorization.h>
#include <Security/AuthorizationDB.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc > 2 || (argc == 2 && strcmp(argv[1], "--screen-trial") != 0)) {
        fputs("Usage: run-probe [--screen-trial]\n", stderr);
        return 1;
    }
    if (geteuid() == 0 || getuid() != geteuid()) {
        fputs("Run this diagnostic as the logged-in user, not root.\n", stderr);
        return 1;
    }
    printf("PROBE_PROCESS pid=%d uid=%d\n", (int)getpid(), (int)geteuid());
    const char *right_name = argc == 2
        ? "org.plf02wh.remoteunlock.screen-test"
        : "org.plf02wh.remoteunlock.probe";
    CFDictionaryRef definition = NULL;
    OSStatus status = AuthorizationRightGet(right_name, &definition);
    if (status != errAuthorizationSuccess) {
        const char *label = status == errAuthorizationDenied
            ? "PROBE_RIGHT_NOT_INSTALLED" : "PROBE_RIGHT_LOOKUP_FAILED";
        fprintf(stderr, "%s status=%d\n", label, (int)status);
        return 1;
    }
    const void *value = CFDictionaryGetValue(definition, CFSTR("mechanisms"));
    const void *rule_class = CFDictionaryGetValue(definition, CFSTR("class"));
    Boolean matches = rule_class != NULL &&
        CFEqual(rule_class, CFSTR("evaluate-mechanisms")) &&
        value != NULL && CFGetTypeID(value) == CFArrayGetTypeID() &&
        CFArrayGetCount(value) == 1 &&
        CFEqual(CFArrayGetValueAtIndex(value, 0), CFSTR("PlfAuthProbe:probe"));
    CFRelease(definition);
    if (!matches) {
        fputs("PROBE_RIGHT_UNEXPECTED_DEFINITION\n", stderr);
        return 1;
    }
    AuthorizationRef authorization = NULL;
    status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
                                 kAuthorizationFlagDefaults, &authorization);
    if (status != errAuthorizationSuccess) {
        fprintf(stderr, "PROBE_CONTEXT_FAILED status=%d\n", (int)status);
        return 1;
    }
    AuthorizationItem item = {right_name, 0, NULL, 0};
    AuthorizationRights rights = {1, &item};
    status = AuthorizationCopyRights(authorization, &rights, kAuthorizationEmptyEnvironment,
                                    kAuthorizationFlagExtendRights |
                                    kAuthorizationFlagInteractionAllowed, NULL);
    OSStatus release_status = AuthorizationFree(authorization, kAuthorizationFlagDestroyRights);
    printf("PROBE_RIGHT_RESULT status=%d release=%d\n", (int)status, (int)release_status);
    puts("Expected denial alone does not prove plug-in invocation; check the scoped system log.");
    return status == errAuthorizationDenied && release_status == errAuthorizationSuccess ? 0 : 1;
}
