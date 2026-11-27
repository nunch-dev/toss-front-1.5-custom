#include "ControlledContext.h"
#include <pthread.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static bool available;
static PLFScreenContext observation;

PLFScreenContext PLFTestScreenContext(void) {
    return (PLFScreenContext){
        .executionUID = 92, .callerSecuritySession = 100023, .attributes = 0x2010,
        .consoleUID = 501, .cgUID = 501, .onConsole = true, .loginDone = true
    };
}

void PLFTestContextSet(const PLFScreenContext *context) {
    pthread_mutex_lock(&lock);
    available = context != NULL;
    observation = context != NULL ? *context : (PLFScreenContext){0};
    pthread_mutex_unlock(&lock);
}

bool PLFCaptureScreenContext(PLFScreenContext *context) {
    if (context == NULL) return false;
    pthread_mutex_lock(&lock);
    bool captured = available;
    *context = observation;
    pthread_mutex_unlock(&lock);
    if (captured && PLFScreenContextValid(context)) return true;
    *context = (PLFScreenContext){0};
    return false;
}
