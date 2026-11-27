LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_PRODUCT),lineage_arm64_bgN)
include $(CLEAR_VARS)
LOCAL_MODULE := PLF02WHKeliBoard
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := KeliBoard.apk
LOCAL_PRODUCT_MODULE := true
LOCAL_MULTILIB := 64
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_SDK_VERSION := current
LOCAL_DEX_PREOPT := false

# Keep the upstream APK signature intact; install its compressed JNI separately.
LOCAL_REPLACE_PREBUILT_APK_INSTALLED := $(LOCAL_PATH)/KeliBoard.apk
LOCAL_PREBUILT_JNI_LIBS := \
    lib/arm64-v8a/libandroidx.graphics.path.so \
    lib/arm64-v8a/libjni_latinime.so
include $(BUILD_PREBUILT)
endif
