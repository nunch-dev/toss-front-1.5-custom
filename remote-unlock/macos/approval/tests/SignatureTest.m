#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "HelperIdentity.h"
#include <stdio.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) return 1;
        NSURL *url = [NSURL fileURLWithPath:@(argv[1])];
        SecStaticCodeRef code = NULL;
        SecRequirementRef requirement = NULL;
        CFDictionaryRef information = NULL;
        NSString *expression = [NSString stringWithFormat:@"cdhash H\"%s\"", PLF_HELPER_CDHASH];
        BOOL valid = NO;
        if (SecRequirementCreateWithString((__bridge CFStringRef)expression, 0, &requirement) != 0)
            goto done;
        if (SecStaticCodeCreateWithPath((__bridge CFURLRef)url, 0, &code) != 0) goto done;
        if (SecStaticCodeCheckValidity(code, kSecCSStrictValidate, requirement) != 0) goto done;
        if (SecCodeCopySigningInformation(code, kSecCSSigningInformation, &information) != 0) goto done;
        {
            NSDictionary *fields = (__bridge NSDictionary *)information;
            NSNumber *flags = fields[(__bridge NSString *)kSecCodeInfoFlags];
            valid = [flags isKindOfClass:NSNumber.class] &&
                (flags.unsignedIntValue & kSecCodeSignatureRuntime) != 0 &&
                (flags.unsignedIntValue & kSecCodeSignatureLinkerSigned) == 0 &&
                fields[(__bridge NSString *)kSecCodeInfoEntitlements] == nil &&
                fields[(__bridge NSString *)kSecCodeInfoEntitlementsDict] == nil;
        }
done:
        if (information) CFRelease(information);
        if (code) CFRelease(code);
        if (requirement) CFRelease(requirement);
        puts(valid ? "SIGNED_HELPER_OK pinned_cdhash runtime no_entitlements" : "SIGNED_HELPER_FAILED");
        return valid ? 0 : 1;
    }
}
