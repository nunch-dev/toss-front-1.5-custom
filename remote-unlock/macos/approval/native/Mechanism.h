#import <Foundation/Foundation.h>
#import <Security/AuthorizationPlugin.h>
#import "Models.h"

NS_ASSUME_NONNULL_BEGIN
@interface PLFPluginState : NSObject
@property(nonatomic, readonly) AuthorizationCallbacks callbacks;
- (instancetype)initWithCallbacks:(const AuthorizationCallbacks *)callbacks;
// One active invocation across mechanisms. A new mechanism can run after
// the previous worker and its callbacks have finished.
- (BOOL)claimInvocation;
- (void)finishInvocation;
@end

@interface PLFMechanism : NSObject
- (instancetype)initWithPlugin:(PLFPluginState *)plugin
                       engine:(AuthorizationEngineRef)engine
                         mode:(PLFApprovalMode)mode;
- (OSStatus)invoke;
- (OSStatus)deactivate;
- (void)destroy;
@end
NS_ASSUME_NONNULL_END
