//
//  JITEnableContextInternal.h
//  StikDebug
//
//  Created by s s on 2025/12/12.
//
#include "idevice.h"
#import "JITEnableContext.h"
@import Foundation;


@interface JITEnableContext(Internal)

- (LogFuncC)createCLogger:(LogFunc)logger;
- (NSError*)errorWithStr:(NSString*)str code:(int)code;

@end

static inline NSError* makeError(int code, NSString* msg) {
    return [NSError errorWithDomain:@"StikJIT" code:code userInfo:@{NSLocalizedDescriptionKey: msg}];
}
