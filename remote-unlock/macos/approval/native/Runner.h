#import "Models.h"

NS_ASSUME_NONNULL_BEGIN
@interface PLFRunner : NSObject
// Run once, on the mechanism's worker. Returns only after closing pipes and
// reaping its child. Cancellation may be called concurrently, even before run.
// Output remains untrusted: the owner must validate it at the commit point,
// because the result frame can expire earlier than the invocation itself.
- (nullable NSData *)run:(PLFInvocation *)invocation exitStatus:(int *)exitStatus;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
