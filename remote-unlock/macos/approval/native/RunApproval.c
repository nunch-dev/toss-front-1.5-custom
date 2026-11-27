#include <Security/Authorization.h>
#include <Security/AuthorizationDB.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1], "approve") != 0 && strcmp(argv[1], "deny") != 0)) {
        fputs("Usage: run-approval approve|deny\n", stderr);
        return 1;
    }
    if (getuid() == 0 || getuid() != geteuid() || getgid() != getegid()) {
        fputs("Run as the logged-in user with matching real/effective IDs.\n", stderr);
        return 1;
    }
    const char *right = "org.plf02wh.remoteunlock.approval-test";
    CFDictionaryRef definition = NULL;
    OSStatus status = AuthorizationRightGet(right, &definition);
    if (status != errAuthorizationSuccess) {
        fprintf(stderr, "APPROVAL_RIGHT_LOOKUP_FAILED status=%d\n", (int)status);
        return 1;
    }
    const void *ruleClass = CFDictionaryGetValue(definition, CFSTR("class"));
    const void *mechanisms = CFDictionaryGetValue(definition, CFSTR("mechanisms"));
    const void *shared = CFDictionaryGetValue(definition, CFSTR("shared"));
    const void *tries = CFDictionaryGetValue(definition, CFSTR("tries"));
    int attempts = 0;
    Boolean matches = ruleClass && CFEqual(ruleClass, CFSTR("evaluate-mechanisms")) &&
        mechanisms && CFGetTypeID(mechanisms) == CFArrayGetTypeID() &&
        CFArrayGetCount(mechanisms) == 1 &&
        CFEqual(CFArrayGetValueAtIndex(mechanisms, 0), CFSTR("PlfRemoteApproval:approval")) &&
        shared == kCFBooleanFalse && tries && CFGetTypeID(tries) == CFNumberGetTypeID() &&
        CFNumberGetValue(tries, kCFNumberIntType, &attempts) && attempts == 1;
    CFRelease(definition);
    if (!matches) {
        fputs("APPROVAL_RIGHT_UNEXPECTED_DEFINITION\n", stderr);
        return 1;
    }
    AuthorizationRef context = NULL;
    status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
                                 kAuthorizationFlagDefaults, &context);
    if (status != errAuthorizationSuccess) {
        fprintf(stderr, "APPROVAL_CONTEXT_FAILED status=%d\n", (int)status);
        return 1;
    }
    printf("APPROVAL_PROCESS pid=%d uid=%d\n", (int)getpid(), (int)getuid());
    AuthorizationItem item = {right, 0, NULL, 0};
    AuthorizationRights rights = {1, &item};
    status = AuthorizationCopyRights(context, &rights, kAuthorizationEmptyEnvironment,
        kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed, NULL);
    OSStatus released = AuthorizationFree(context, kAuthorizationFlagDestroyRights);
    printf("APPROVAL_RIGHT_RESULT status=%d release=%d\n", (int)status, (int)released);
    puts("OS_SCREEN_UNLOCK=not_tested");
    OSStatus expected = strcmp(argv[1], "approve") == 0 ?
        errAuthorizationSuccess : errAuthorizationDenied;
    return status == expected && released == errAuthorizationSuccess ? 0 : 1;
}
