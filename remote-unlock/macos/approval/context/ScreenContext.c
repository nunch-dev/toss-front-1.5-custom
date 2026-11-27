#include "ScreenContext.h"
#include <CoreGraphics/CGSession.h>
#include <Security/AuthSession.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <unistd.h>

bool PLFScreenContextValid(const PLFScreenContext *context) {
    return context != NULL &&
        context->executionUID > 0 && context->executionUID < UINT32_MAX &&
        context->callerSecuritySession > 0 &&
        context->callerSecuritySession < UINT32_MAX - 1 &&
        (context->attributes & sessionHasGraphicAccess) != 0 &&
        (context->attributes & (sessionIsRoot | sessionIsRemote)) == 0 &&
        context->consoleUID > 0 && context->consoleUID < UINT32_MAX &&
        context->cgUID == context->consoleUID &&
        context->onConsole && context->loginDone;
}

bool PLFCaptureScreenContext(PLFScreenContext *context) {
    if (context == NULL) return false;
    *context = (PLFScreenContext){0};
    PLFScreenContext observed = {0};
    if (getuid() != geteuid()) return false;
    observed.executionUID = (uint32_t)getuid();
    SecuritySessionId session = noSecuritySession;
    SessionAttributeBits attributes = 0;
    if (SessionGetInfo(callerSecuritySession, &session, &attributes) != errSessionSuccess)
        return false;
    observed.callerSecuritySession = session;
    observed.attributes = attributes;
    uid_t consoleUID = (uid_t)-1;
    CFStringRef user = SCDynamicStoreCopyConsoleUser(NULL, &consoleUID, NULL);
    if (user == NULL) return false;
    CFRelease(user);
    observed.consoleUID = (uint32_t)consoleUID;
    CFDictionaryRef dictionary = CGSessionCopyCurrentDictionary();
    if (dictionary == NULL) return false;
    CFTypeRef uid = CFDictionaryGetValue(dictionary, kCGSessionUserIDKey);
    CFTypeRef onConsole = CFDictionaryGetValue(dictionary, kCGSessionOnConsoleKey);
    CFTypeRef loginDone = CFDictionaryGetValue(dictionary, kCGSessionLoginDoneKey);
    int64_t cgUID = 0;
    bool valid = uid != NULL && CFGetTypeID(uid) == CFNumberGetTypeID() &&
        CFNumberGetValue(uid, kCFNumberSInt64Type, &cgUID) &&
        cgUID > 0 && cgUID < UINT32_MAX &&
        onConsole != NULL && CFGetTypeID(onConsole) == CFBooleanGetTypeID() &&
        loginDone != NULL && CFGetTypeID(loginDone) == CFBooleanGetTypeID();
    if (valid) {
        observed.cgUID = (uint32_t)cgUID;
        observed.onConsole = CFBooleanGetValue(onConsole);
        observed.loginDone = CFBooleanGetValue(loginDone);
    }
    CFRelease(dictionary);
    if (!valid || !PLFScreenContextValid(&observed)) return false;
    *context = observed;
    return true;
}

bool PLFScreenContextsEqual(const PLFScreenContext *left, const PLFScreenContext *right) {
    return PLFScreenContextValid(left) && PLFScreenContextValid(right) &&
        left->executionUID == right->executionUID &&
        left->callerSecuritySession == right->callerSecuritySession &&
        left->attributes == right->attributes &&
        left->consoleUID == right->consoleUID &&
        left->cgUID == right->cgUID &&
        left->onConsole == right->onConsole &&
        left->loginDone == right->loginDone;
}
