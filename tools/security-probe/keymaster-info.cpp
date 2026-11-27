#include <android/hardware/keymaster/4.0/IKeymasterDevice.h>
#include <cstdio>

using android::hardware::hidl_string;
using android::hardware::keymaster::V4_0::IKeymasterDevice;
using android::hardware::keymaster::V4_0::SecurityLevel;

int main() {
    auto device = IKeymasterDevice::tryGetService("default");
    if (device == nullptr) {
        std::fputs("Keymaster 4.0/default is unavailable\n", stderr);
        return 1;
    }

    auto result = device->getHardwareInfo(
        [](SecurityLevel level, const hidl_string& name, const hidl_string& author) {
            std::printf("security_level=%d\nname=%s\nauthor=%s\n",
                        static_cast<int>(level), name.c_str(), author.c_str());
        });
    if (!result.isOk()) {
        std::fprintf(stderr, "getHardwareInfo failed: %s\n", result.description().c_str());
        return 1;
    }
    return 0;
}
