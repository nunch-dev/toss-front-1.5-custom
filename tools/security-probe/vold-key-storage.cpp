#include <KeyStorage.h>
#include <android-base/logging.h>

#include <cstdio>
#include <cstdlib>
#include <string>
#include <sys/random.h>
#include <unistd.h>

int main(int, char** argv) {
    android::base::InitLogging(argv, android::base::StderrLogger);
    using namespace android::vold;

    KeyBuffer expected(64);
    if (getrandom(expected.data(), expected.size(), 0) !=
        static_cast<ssize_t>(expected.size())) {
        perror("getrandom");
        return 1;
    }
    char root[] = "/data/local/tmp/plf-vold-key-test-XXXXXX";
    if (mkdtemp(root) == nullptr) {
        perror("mkdtemp");
        return 1;
    }
    printf("scratch=%s\n", root);
    bool passed = true;
    for (const bool use_keystore : {true, false}) {
        const std::string name = use_keystore ? "keystore" : "secret";
        const std::string path = std::string(root) + "/" + name;
        const std::string temporary = path + ".tmp";
        const KeyAuthentication auth(use_keystore ? "" : "diagnostic-secret-not-a-user-credential");

        const bool stored = storeKeyAtomically(path, temporary, auth, expected);
        printf("%s.store=%s\n", name.c_str(), stored ? "PASS" : "FAIL");
        passed &= stored;
        if (stored) {
            if (!use_keystore) {
                KeyBuffer rejected;
                const bool accepted = retrieveKey(
                        path, KeyAuthentication("incorrect-diagnostic-secret"), &rejected);
                printf("secret.wrong_secret_rejected=%s\n", accepted ? "FAIL" : "PASS");
                passed &= !accepted;
            }
            KeyBuffer actual;
            const bool restored = retrieveKey(path, auth, &actual) && actual == expected;
            printf("%s.restore=%s\n", name.c_str(), restored ? "PASS" : "FAIL");
            passed &= restored;
        }
        for (const auto& owned : {path, temporary}) {
            if (access(owned.c_str(), F_OK) == 0) {
                const bool removed = destroyKey(owned);
                printf("%s.cleanup=%s\n", owned.c_str(), removed ? "PASS" : "FAIL");
                passed &= removed;
            }
        }
    }
    if (rmdir(root) != 0) {
        perror("rmdir");
        passed = false;
    }
    printf("VOLD_KEY_STORAGE_%s\n", passed ? "PASS" : "FAIL");
    return passed ? 0 : 1;
}
