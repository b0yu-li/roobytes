#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns any thrown `NSException` (nil on success).
/// Used to keep AppKit draw paths from aborting the process on `NSRangeException`.
NSException * _Nullable RoobytesCatchException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
