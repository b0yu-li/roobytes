#import "RoobytesObjCException.h"

NSException * _Nullable RoobytesCatchException(NS_NOESCAPE void (^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return exception;
    }
}
