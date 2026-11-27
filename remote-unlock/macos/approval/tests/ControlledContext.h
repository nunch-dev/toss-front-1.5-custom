#pragma once
#include "../context/ScreenContext.h"

// Test-link replacement for the OS observation boundary; never shipped.
PLFScreenContext PLFTestScreenContext(void);
void PLFTestContextSet(const PLFScreenContext *context);
