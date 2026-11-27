#import "Models.h"
#include <mach/mach_time.h>
#include <math.h>

static BOOL integer(id value) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    double number = [value doubleValue];
    return isfinite(number) && number >= 0 && number <= 9007199254740991.0 &&
           floor(number) == number;
}

static NSDictionary *record(NSString *line, NSSet<NSString *> *keys) {
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length == 0 || data.length > 4096) return nil;
    NSError *error = nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || ![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *fields = value;
    if (![[NSSet setWithArray:fields.allKeys] isEqualToSet:keys]) return nil;
    if (!integer(fields[@"version"]) || ![fields[@"version"] isEqual:@2] ||
        !integer(fields[@"expiresAt"])) return nil;
    for (NSString *key in @[@"kind", @"mode", @"account", @"generation", @"requestId", @"requestHash"]) {
        if (![fields[key] isKindOfClass:NSString.class]) return nil;
    }
    NSString *hash = fields[@"requestHash"];
    if (hash.length != 43) return nil;
    NSCharacterSet *alphabet = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"];
    if ([hash rangeOfCharacterFromSet:alphabet.invertedSet].location != NSNotFound) return nil;
    NSString *base64 = [[[hash stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
        stringByReplacingOccurrencesOfString:@"_" withString:@"/"] stringByAppendingString:@"="];
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    if (decoded.length != 32 || ![[decoded base64EncodedStringWithOptions:0] isEqual:base64]) return nil;
    return fields;
}

static BOOL contextMatches(id value, NSDictionary *expected) {
    if (expected == nil) return value == NSNull.null;
    if (![value isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *fields = value;
    if (![[NSSet setWithArray:fields.allKeys] isEqualToSet:
          [NSSet setWithArray:expected.allKeys]]) return NO;
    for (NSString *key in @[@"executionUID", @"callerSecuritySession", @"attributes",
                            @"consoleUID", @"cgUID"]) {
        if (!integer(fields[key]) || ![fields[key] isEqual:expected[key]]) return NO;
    }
    for (NSString *key in @[@"onConsole", @"loginDone"]) {
        if (CFGetTypeID((__bridge CFTypeRef)fields[key]) != CFBooleanGetTypeID() ||
            ![fields[key] isEqual:expected[key]]) return NO;
    }
    return YES;
}

PLFDecision PLFValidateOutput(NSData *output, PLFInvocation *invocation, int exitStatus) {
    if (exitStatus != 0 || output.length > 8192 || mach_continuous_time() >= invocation.deadline)
        return PLFDecisionInvalid;
    NSString *text = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    if (lines.count != 3 || ![lines[2] isEqual:@""]) return PLFDecisionInvalid;
    NSSet *boundKeys = [NSSet setWithArray:
        @[@"version", @"kind", @"mode", @"account", @"context",
          @"generation", @"requestId", @"requestHash", @"expiresAt"]];
    NSMutableSet *resultKeys = [boundKeys mutableCopy];
    [resultKeys addObject:@"decision"];
    NSDictionary *bound = record(lines[0], boundKeys);
    NSDictionary *result = record(lines[1], resultKeys);
    if (!bound || !result || ![bound[@"kind"] isEqual:@"bound"] ||
        ![result[@"kind"] isEqual:@"result"]) return PLFDecisionInvalid;
    for (NSDictionary *fields in @[bound, result]) {
        if (![fields[@"generation"] isEqual:invocation.generation] ||
            ![fields[@"requestId"] isEqual:invocation.requestID] ||
            ![fields[@"mode"] isEqual:invocation.mode] ||
            ![fields[@"account"] isEqual:invocation.account] ||
            !contextMatches(fields[@"context"], invocation.context)) return PLFDecisionInvalid;
    }
    int64_t boundExpiry = [bound[@"expiresAt"] longLongValue];
    int64_t resultExpiry = [result[@"expiresAt"] longLongValue];
    if (boundExpiry != invocation.expiresAt || resultExpiry > boundExpiry ||
        NSDate.date.timeIntervalSince1970 >= resultExpiry ||
        ![bound[@"requestHash"] isEqual:result[@"requestHash"]]) return PLFDecisionInvalid;
    if ([result[@"decision"] isEqual:@"approve"]) return PLFDecisionApprove;
    if ([result[@"decision"] isEqual:@"deny"]) return PLFDecisionDeny;
    return PLFDecisionInvalid;
}
