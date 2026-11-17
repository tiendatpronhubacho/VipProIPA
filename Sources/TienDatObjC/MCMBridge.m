#import "MCMBridge.h"

// Standard iOS sandbox build: cross-application container enumeration and
// sandbox-extension activation are intentionally unavailable. Do not replace
// these stubs with private MobileContainerManager entry points.
NSArray<NSString *> *MCMEnumerateIdentifiersForClass(uint64_t cls, NSUInteger limit, NSString **error) {
    (void)cls; (void)limit;
    if (error) *error = @"Cross-app container access is not available in the standard iOS sandbox";
    return @[];
}
NSString *MCMContainerPathForIdentifier(uint64_t cls, NSString *identifier, BOOL group, NSString **error) {
    (void)cls; (void)identifier; (void)group;
    if (error) *error = @"Cross-app container access is not available in the standard iOS sandbox";
    return nil;
}
NSString *MCMActivateContainerPath(uint64_t cls, NSString *identifier, BOOL group, NSString **error) {
    (void)cls; (void)identifier; (void)group;
    if (error) *error = @"Sandbox extension activation is unavailable in this build";
    return nil;
}
BOOL MCMBridgeAvailable(void) { return NO; }
int64_t MCMActivateContainer(uint64_t cls, NSString *identifier, BOOL group, NSString **error) {
    (void)cls; (void)identifier; (void)group;
    if (error) *error = @"Sandbox extension activation is unavailable in this build";
    return -1;
}
