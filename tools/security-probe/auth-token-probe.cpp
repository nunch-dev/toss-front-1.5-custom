#include <android/hardware/gatekeeper/1.0/IGatekeeper.h>
#include <android/hardware/keymaster/4.0/IKeymasterDevice.h>
#include <keymasterV4_0/authorization_set.h>
#include <keymasterV4_0/keymaster_utils.h>

#include <array>
#include <cstdio>
#include <cstring>
#include <sys/random.h>
#include <unistd.h>

namespace gk = android::hardware::gatekeeper::V1_0;
namespace km = android::hardware::keymaster::V4_0;
using android::hardware::hidl_vec;

int main() {
    auto gatekeeper = gk::IGatekeeper::tryGetService("default");
    auto keymaster = km::IKeymasterDevice::tryGetService("default");
    if (gatekeeper == nullptr || keymaster == nullptr) {
        fprintf(stderr, "Required HAL unavailable\n");
        return 1;
    }
    std::array<uint8_t, 64> material;
    uint32_t test_uid;
    if (getrandom(material.data(), material.size(), 0) !=
                static_cast<ssize_t>(material.size()) ||
        getrandom(&test_uid, sizeof(test_uid), 0) != static_cast<ssize_t>(sizeof(test_uid))) {
        perror("getrandom");
        return 1;
    }
    // Isolate the probe from Android user IDs and locksettings' fake user IDs.
    test_uid |= 0x80000000U;
    hidl_vec<uint8_t> secret(material.data(), material.data() + 32);
    gk::GatekeeperResponse enrolled;
    auto enroll_call = gatekeeper->enroll(test_uid, {}, {}, secret,
            [&](const auto& response) { enrolled = response; });
    printf("gatekeeper_enroll=%d\n", static_cast<int32_t>(enrolled.code));
    if (!enroll_call.isOk() || enrolled.code != gk::GatekeeperStatusCode::STATUS_OK) {
        return 1;
    }

    gk::GatekeeperResponse verified;
    auto verify_call = gatekeeper->verify(test_uid, 0, enrolled.data, secret,
            [&](const auto& response) { verified = response; });
    printf("gatekeeper_verify=%d\n", static_cast<int32_t>(verified.code));
    bool passed = verify_call.isOk() &&
            (verified.code == gk::GatekeeperStatusCode::STATUS_OK ||
             verified.code == gk::GatekeeperStatusCode::STATUS_REENROLL);
    const bool token_shape = verified.data.size() == 69 && verified.data[0] == 0;
    printf("token_shape_valid=%d\n", token_shape);
    passed &= token_shape;

    if (passed) {
        const auto token = km::support::hidlVec2AuthToken(verified.data);
        const bool token_fields = token.userId != 0 && token.challenge == 0 &&
                token.authenticatorType == km::HardwareAuthenticatorType::PASSWORD &&
                token.mac.size() == 32;
        printf("token_fields_valid=%d\n", token_fields);
        passed &= token_fields;

        auto parameters = km::AuthorizationSetBuilder()
                .AesEncryptionKey(256)
                .GcmModeMinMacLen(128)
                .Authorization(km::TAG_USER_SECURE_ID, token.userId)
                .Authorization(km::TAG_USER_AUTH_TYPE, km::HardwareAuthenticatorType::PASSWORD)
                .Authorization(km::TAG_AUTH_TIMEOUT, 15);
        hidl_vec<uint8_t> raw_key(material.data() + 32, material.data() + 64);
        hidl_vec<uint8_t> key_blob;
        km::KeyCharacteristics characteristics;
        auto import_error = km::ErrorCode::UNKNOWN_ERROR;
        auto import_call = keymaster->importKey(parameters.hidl_data(), km::KeyFormat::RAW, raw_key,
                [&](auto error, const auto& blob, const auto& auth) {
                    import_error = error;
                    key_blob = blob;
                    characteristics = auth;
                });
        printf("key_import=%d\n", static_cast<int32_t>(import_error));
        passed &= import_call.isOk() && import_error == km::ErrorCode::OK;

        if (import_call.isOk() && import_error == km::ErrorCode::OK) {
            km::AuthorizationSet auth(characteristics.softwareEnforced);
            auth.push_back(km::AuthorizationSet(characteristics.hardwareEnforced));
            const bool sid_matches = auth.Contains(km::TAG_USER_SECURE_ID, token.userId);
            const bool type_matches = auth.Contains(
                    km::TAG_USER_AUTH_TYPE, km::HardwareAuthenticatorType::PASSWORD);
            printf("key_sid_matches=%d\nkey_auth_type_matches=%d\n", sid_matches, type_matches);
            passed &= sid_matches && type_matches;

            std::array<uint8_t, 12> nonce{};
            auto operation = km::AuthorizationSetBuilder()
                    .Authorization(km::TAG_BLOCK_MODE, km::BlockMode::GCM)
                    .Authorization(km::TAG_PADDING, km::PaddingMode::NONE)
                    .Authorization(km::TAG_MAC_LENGTH, 128)
                    .Authorization(km::TAG_NONCE,
                            km::support::blob2hidlVec(nonce.data(), nonce.size()));
            for (const bool authenticated : {false, true}) {
                km::HardwareAuthToken supplied = authenticated ? token : km::HardwareAuthToken{};
                auto begin_error = km::ErrorCode::UNKNOWN_ERROR;
                uint64_t handle = 0;
                auto begin_call = keymaster->begin(km::KeyPurpose::DECRYPT, key_blob,
                        operation.hidl_data(), supplied,
                        [&](auto error, const auto&, auto operation_handle) {
                            begin_error = error;
                            handle = operation_handle;
                        });
                printf("%s_token_begin=%d\n", authenticated ? "valid" : "missing",
                        static_cast<int32_t>(begin_error));
                const auto expected = authenticated ? km::ErrorCode::OK
                        : km::ErrorCode::KEY_USER_NOT_AUTHENTICATED;
                passed &= begin_call.isOk() && begin_error == expected;
                if (begin_call.isOk() && begin_error == km::ErrorCode::OK) {
                    auto abort_result = keymaster->abort(handle);
                    passed &= abort_result.isOk() &&
                            static_cast<km::ErrorCode>(abort_result) == km::ErrorCode::OK;
                }
            }
            auto deleted = keymaster->deleteKey(key_blob);
            const bool key_removed = deleted.isOk() &&
                    static_cast<km::ErrorCode>(deleted) == km::ErrorCode::OK;
            printf("test_key_cleanup=%d\n", key_removed);
            passed &= key_removed;
        }
        memset_explicit(raw_key.data(), 0, raw_key.size());
    }

    auto delete_status = gk::GatekeeperStatusCode::ERROR_GENERAL_FAILURE;
    auto delete_call = gatekeeper->deleteUser(test_uid,
            [&](const auto& response) { delete_status = response.code; });
    printf("test_gatekeeper_delete=%d\n", static_cast<int32_t>(delete_status));
    // The software HAL keeps handles in the caller and volatile cache entries.
    // Its optional deleteUser method may report ERROR_NOT_IMPLEMENTED.
    passed &= delete_call.isOk() &&
            (delete_status == gk::GatekeeperStatusCode::STATUS_OK ||
             delete_status == gk::GatekeeperStatusCode::ERROR_NOT_IMPLEMENTED);
    memset_explicit(secret.data(), 0, secret.size());
    memset_explicit(material.data(), 0, material.size());
    printf("AUTH_TOKEN_PROBE_%s\n", passed ? "PASS" : "FAIL");
    return passed ? 0 : 1;
}
