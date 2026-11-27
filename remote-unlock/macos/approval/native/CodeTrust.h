#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
extern const char PLFHelperPath[];
// Returns an owned CLOEXEC descriptor, or -1. Root is the deployment trust
// boundary: administrators must not replace the helper while it is in use.
int PLFOpenVerifiedHelper(void);
NS_ASSUME_NONNULL_END
