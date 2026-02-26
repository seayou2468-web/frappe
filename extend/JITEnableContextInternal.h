//
//  JITEnableContextInternal.h
//  StikDebug
//
//  Created by s s on 2025/12/12.
//
#include "idevice.h"
#import "extend/JITEnableContext.h"
#import <Foundation/Foundation.h>


int plist_to_xml(plist_t plist, char **xml_out, uint32_t *length);
@interface JITEnableContext(Internal)

- (LogFuncC)createCLogger:(LogFunc)logger;
- (NSError*)errorWithStr:(NSString*)str code:(int)code;

@end

static inline NSError* makeError(int code, NSString* msg) {
    return [NSError errorWithDomain:@"StikJIT" code:code userInfo:@{NSLocalizedDescriptionKey: msg}];
}
