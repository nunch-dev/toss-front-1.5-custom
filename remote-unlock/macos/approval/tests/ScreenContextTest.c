#include "../context/ScreenContext.h"
#include <Security/AuthSession.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
static void require(bool value, const char *name) {
    if (!value) { fprintf(stderr, "FAIL %s\n", name); exit(1); }
    checks++;
}

int main(void) {
    PLFScreenContext valid = {
        .executionUID = 92, .callerSecuritySession = 100023,
        .attributes = sessionHasGraphicAccess,
        .consoleUID = 501, .cgUID = 501, .onConsole = true, .loginDone = true
    };
    require(PLFScreenContextValid(&valid), "local graphical console accepted");
    PLFScreenContext unknown = valid;
    unknown.attributes |= 0x2000;
    require(PLFScreenContextValid(&unknown), "unknown attribute bits do not reject a valid console");
    require(!PLFScreenContextValid(NULL), "absent observation rejected");
    require(!PLFCaptureScreenContext(NULL), "null capture destination rejected");
    require(PLFScreenContextsEqual(&valid, &valid), "same valid context matches");
    for (unsigned index = 0; index < 13; index++) {
        PLFScreenContext invalid = valid;
        const char *name = NULL;
        switch (index) {
            case 0: invalid.executionUID = 0; name = "root execution rejected"; break;
            case 1: invalid.executionUID = UINT32_MAX; name = "sentinel UID rejected"; break;
            case 2: invalid.callerSecuritySession = 0; name = "missing session rejected"; break;
            case 3: invalid.callerSecuritySession = UINT32_MAX; name = "caller sentinel rejected"; break;
            case 4: invalid.callerSecuritySession = UINT32_MAX - 1; name = "reserved session rejected"; break;
            case 5: invalid.attributes = 0; name = "nongraphical session rejected"; break;
            case 6: invalid.attributes |= sessionIsRoot; name = "root session rejected"; break;
            case 7: invalid.attributes |= sessionIsRemote; name = "remote session rejected"; break;
            case 8: invalid.consoleUID = invalid.cgUID = 0; name = "root console rejected"; break;
            case 9: invalid.consoleUID = invalid.cgUID = UINT32_MAX; name = "missing console rejected"; break;
            case 10: invalid.cgUID = 502; name = "disagreeing console sources rejected"; break;
            case 11: invalid.onConsole = false; name = "switched out console rejected"; break;
            case 12: invalid.loginDone = false; name = "unfinished login rejected"; break;
        }
        require(!PLFScreenContextValid(&invalid), name);
        require(!PLFScreenContextsEqual(&valid, &invalid), "invalid observation never matches");
    }
    PLFScreenContext alternatives[] = {valid, valid, valid, valid};
    alternatives[0].executionUID = 93;
    alternatives[1].callerSecuritySession++;
    alternatives[2].attributes |= sessionHasTTY;
    alternatives[3].consoleUID = alternatives[3].cgUID = 502;
    for (unsigned index = 0; index < 4; index++) {
        require(PLFScreenContextValid(&alternatives[index]), "alternate observation is independently valid");
        require(!PLFScreenContextsEqual(&valid, &alternatives[index]), "changed valid identity rejected");
    }
    printf("NATIVE_CONTEXT_OK checks=%u\n", checks);
    return 0;
}
