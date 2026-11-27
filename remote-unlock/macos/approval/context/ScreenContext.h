#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint32_t executionUID;
    uint32_t callerSecuritySession;
    uint32_t attributes;
    uint32_t consoleUID;
    uint32_t cgUID;
    bool onConsole;
    bool loginDone;
} PLFScreenContext;

bool PLFScreenContextValid(const PLFScreenContext *context);
bool PLFCaptureScreenContext(PLFScreenContext *context);
bool PLFScreenContextsEqual(const PLFScreenContext *left, const PLFScreenContext *right);
