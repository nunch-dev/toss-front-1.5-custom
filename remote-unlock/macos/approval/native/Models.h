#import <Foundation/Foundation.h>
#include "../context/ScreenContext.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PLFDecision) {
    PLFDecisionInvalid,
    PLFDecisionDeny,
    PLFDecisionApprove
};

typedef NS_ENUM(NSInteger, PLFApprovalMode) {
    PLFApprovalModeIsolated,
    PLFApprovalModeScreenTrial
};

@interface PLFInvocation : NSObject
@property(nonatomic, readonly, copy) NSData *wire;
@property(nonatomic, readonly, copy) NSString *generation;
@property(nonatomic, readonly, copy) NSString *requestID;
@property(nonatomic, readonly, copy) NSString *mode;
@property(nonatomic, readonly, copy) NSString *account;
@property(nonatomic, readonly, copy, nullable) NSDictionary *context;
@property(nonatomic, readonly) int64_t expiresAt;
@property(nonatomic, readonly) uint64_t deadline;
- (nullable instancetype)initAtUnixTime:(int64_t)issuedAt
                       continuousTime:(uint64_t)ticks
                                 mode:(PLFApprovalMode)mode;
- (BOOL)matchesCurrentContext;
- (instancetype)init NS_UNAVAILABLE;
@end

// Stateless pipe-boundary validation. The mechanism owns cancellation and
// one-time commit; a successful parse alone never calls an engine callback.
PLFDecision PLFValidateOutput(NSData *output, PLFInvocation *invocation, int exitStatus);

NS_ASSUME_NONNULL_END
