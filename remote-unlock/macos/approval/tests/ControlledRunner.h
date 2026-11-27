#import <Foundation/Foundation.h>

// Test-only replacement for the process adapter. Never linked into the bundle.
void PLFTestRunnerPrepare(BOOL blocked);
BOOL PLFTestRunnerStarted(void);
unsigned PLFTestRunnerCalls(void);
void PLFTestRunnerRelease(void);
