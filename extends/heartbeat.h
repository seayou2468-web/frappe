NS_ASSUME_NONNULL_BEGIN
//
//  heartbeat.h
//  StikJIT
//
//  Created by Stephen on 3/27/25.
//

// heartbeat.h
#ifndef HEARTBEAT_H
#define HEARTBEAT_H
#include "idevice.h"
#import <Foundation/Foundation.h>

typedef void (^HeartbeatCompletionHandlerC)(int result, const char * _Nullable message);
typedef void (^LogFuncC)(const char* _Nullable message, ...);

extern int globalHeartbeatToken;
extern NSDate* lastHeartbeatDate;

void startHeartbeat(IdevicePairingFile* pairing_file, IdeviceProviderHandle** provider, int heartbeatToken, HeartbeatCompletionHandlerC completion);
#endif /* HEARTBEAT_H */

NS_ASSUME_NONNULL_END