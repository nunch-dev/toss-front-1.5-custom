#import <Foundation/Foundation.h>
#include <sys/types.h>

// All descriptors returned by these functions are >= 3 and CLOEXEC.
BOOL PLFMakePipe(int descriptors[2]);
// Spawn only the fixed, already-verified helper. No ownership passes on failure.
// The caller alone owns signaling and waitpid; nobody else may reap this child.
pid_t PLFSpawnHelper(int input, int output);
