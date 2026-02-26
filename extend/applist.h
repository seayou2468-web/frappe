//
//  applist.h
//  StikJIT
//
//  Created by Stephen on 3/27/25.
//

#ifndef APPLIST_H
#define APPLIST_H
#include "idevice.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NSDictionary<NSString*, NSString*>* list_installed_apps(IdeviceProviderHandle* provider, NSString** error);
NSDictionary<NSString*, NSString*>* list_all_apps(IdeviceProviderHandle* provider, NSString** error);
NSDictionary<NSString*, NSString*>* list_hidden_system_apps(IdeviceProviderHandle* provider, NSString** error);
UIImage* getAppIcon(IdeviceProviderHandle* provider, NSString* bundleID, NSString** error);

#endif /* APPLIST_H */
