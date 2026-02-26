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
#import "CommonTypes.h"
#import <Foundation/Foundation.h>




extern int globalHeartbeatToken;
extern NSDate* lastHeartbeatDate;

void startHeartbeat(IdevicePairingFile* pairing_file, IdeviceProviderHandle** provider, int heartbeatToken, HeartbeatCompletionHandlerC completion);
#endif /* HEARTBEAT_H */
