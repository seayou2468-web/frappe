#ifndef COMMON_TYPES_H
#define COMMON_TYPES_H

#import <Foundation/Foundation.h>
#include "idevice.h"

typedef void (^LogFuncC)(const char* message, ...);
typedef void (^HeartbeatCompletionHandlerC)(int result, const char *message);
typedef void (^DebugAppCallback)(int pid,
                                 struct DebugProxyHandle* debug_proxy,
                                 struct RemoteServerHandle* remote_server,
                                 dispatch_semaphore_t semaphore);

#endif
