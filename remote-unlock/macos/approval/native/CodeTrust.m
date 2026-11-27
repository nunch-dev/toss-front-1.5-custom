#import "CodeTrust.h"
#import "HelperIdentity.h"
#import "../helper/TrustedFiles.h"
#import <Security/Security.h>
#include <sys/stat.h>
#include <unistd.h>

const char PLFHelperPath[] =
    "/Library/Security/SecurityAgentPlugins/PlfRemoteApproval.bundle"
    "/Contents/MacOS/approval-helper";

int PLFOpenVerifiedHelper(void) {
    NSString *hash = @PLF_HELPER_CDHASH;
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:
                          @"0123456789abcdefABCDEF"];
    if (hash.length != 40 ||
        [hash rangeOfCharacterFromSet:hex.invertedSet].location != NSNotFound)
        return -1;
    int fd = plf_open_root_file(PLFHelperPath, 64 * 1024 * 1024);
    if (fd < 0) return -1;
    struct stat before, after, named;
    BOOL valid = NO;
    SecStaticCodeRef code = NULL;
    SecRequirementRef requirement = NULL;
    CFDictionaryRef information = NULL;
    NSURL *url = [NSURL fileURLWithPath:@(PLFHelperPath)];
    NSString *expression = [NSString stringWithFormat:@"cdhash H\"%@\"", hash];
    if (fstat(fd, &before) != 0 || !(before.st_mode & S_IXUSR)) goto done;
    if (SecRequirementCreateWithString((__bridge CFStringRef)expression,
                                      kSecCSDefaultFlags, &requirement) != errSecSuccess)
        goto done;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags,
                                   &code) != errSecSuccess) goto done;
    // The pin is the native architecture's cdhash. No user-supplied requirement.
    if (SecStaticCodeCheckValidity(code, kSecCSStrictValidate,
                                   requirement) != errSecSuccess) goto done;
    if (SecCodeCopySigningInformation(code, kSecCSSigningInformation,
                                     &information) != errSecSuccess) goto done;
    {
        NSDictionary *info = (__bridge NSDictionary *)information;
        NSNumber *flags = info[(__bridge NSString *)kSecCodeInfoFlags];
        if (![flags isKindOfClass:NSNumber.class] ||
            !(flags.unsignedIntValue & kSecCodeSignatureRuntime) ||
            (flags.unsignedIntValue & kSecCodeSignatureLinkerSigned) ||
            info[(__bridge NSString *)kSecCodeInfoEntitlements] != nil ||
            info[(__bridge NSString *)kSecCodeInfoEntitlementsDict] != nil)
            goto done;
    }
    if (fstat(fd, &after) != 0 || lstat(PLFHelperPath, &named) != 0) goto done;
    valid = before.st_dev == after.st_dev && before.st_ino == after.st_ino &&
        before.st_size == after.st_size &&
        before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec &&
        before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec &&
        before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec &&
        before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec &&
        after.st_dev == named.st_dev && after.st_ino == named.st_ino;
done:
    if (information) CFRelease(information);
    if (code) CFRelease(code);
    if (requirement) CFRelease(requirement);
    if (!valid) { close(fd); return -1; }
    return fd;
}
