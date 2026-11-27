// TEST ONLY: link-time OS observation/file adapter. Never install this binary.
#include "../HelperBridge.h"
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern void plf_helper_run(void);
static const char *directory;
static unsigned calls;
static unsigned change_at;

static int fixture(const char *name) {
    char path[PATH_MAX];
    int count = snprintf(path, sizeof(path), "%s/%s", directory, name);
    return count > 0 && count < (int)sizeof(path) ? open(path, O_RDONLY | O_CLOEXEC) : -1;
}

int plf_open_root_file(const char *path, size_t maximum_bytes) {
    (void)maximum_bytes;
    if (strstr(path, "/policy.json") != NULL) return fixture("policy.json");
    if (strstr(path, "/relay-ca.der") != NULL) return fixture("relay-ca.der");
    return -1;
}

int plf_open_private_file(const char *path, uid_t owner, size_t maximum_bytes) {
    (void)maximum_bytes;
    if (owner != getuid()) return -1;
    char receipt[PATH_MAX];
    int count = snprintf(receipt, sizeof(receipt), "%s/key-read", directory);
    if (count <= 0 || count >= (int)sizeof(receipt)) _exit(1);
    int fd = open(receipt, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0 || close(fd) != 0) _exit(1);
    if (strcmp(path, "/Library/Application Support/PLF02WHRemoteApproval/requester.private.json") == 0 ||
        strcmp(path, "/Library/Application Support/PLF02WHRemoteApproval/screen-requester.private.json") == 0)
        return fixture("requester.private.json");
    return -1;
}

bool PLFCaptureScreenContext(PLFScreenContext *context) {
    calls++;
    if (change_at == UINT_MAX) return false;
    *context = (PLFScreenContext){
        .executionUID = getuid(), .callerSecuritySession = 100023,
        .attributes = 8240, .consoleUID = 501, .cgUID = 501,
        .onConsole = true, .loginDone = true
    };
    if (change_at > 0 && calls >= change_at) context->callerSecuritySession++;
    return true;
}

void plf_helper_fail(void) {
    fputs("APPROVAL_HELPER_FAILED\n", stderr);
    _exit(1);
}

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    directory = argv[1];
    change_at = (unsigned)strtoul(argv[2], NULL, 10);
    plf_helper_run();
    return 1;
}
