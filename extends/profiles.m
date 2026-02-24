#include "profiles.h"
#import "JITEnableContext.h"
#import "JITEnableContextInternal.h"
#import <Foundation/Foundation.h>

@implementation JITEnableContext(Profile)

- (NSArray<NSData*>*)fetchAllProfiles:(NSError **)error {
    [self ensureHeartbeatWithError:error];
    if(*error) return nil;

    MisagentClientHandle* misagentHandle = 0;
    IdeviceFfiError * err = misagent_connect(provider, &misagentHandle);
    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        idevice_error_free(err);
        return nil;
    }
    
    uint8_t** profileArr = 0;
    size_t profileCount = 0;
    size_t* profileLengthArr = 0;
    err = misagent_copy_all(misagentHandle, &profileArr, &profileLengthArr, &profileCount);

    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        misagent_client_free(misagentHandle);
        idevice_error_free(err);
        return nil;
    }
    
    NSMutableArray* ans = [NSMutableArray array];
    for(int i = 0; i < profileCount; ++i) {
        [ans addObject:[NSData dataWithBytes:profileArr[i] length:profileLengthArr[i]]];
    }
    
    misagent_free_profiles(profileArr, profileLengthArr, profileCount);
    misagent_client_free(misagentHandle);
    
    return ans;
}

- (BOOL)removeProfileWithUUID:(NSString*)uuid error:(NSError **)error {
    [self ensureHeartbeatWithError:error];
    if(*error) return NO;

    MisagentClientHandle* misagentHandle = 0;
    IdeviceFfiError * err = misagent_connect(provider, &misagentHandle);
    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        idevice_error_free(err);
        return NO;
    }
    
    err = misagent_remove(misagentHandle, [uuid UTF8String]);
    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        misagent_client_free(misagentHandle);
        idevice_error_free(err);
        return NO;
    }
    
    misagent_client_free(misagentHandle);
    return YES;
}

- (BOOL)addProfile:(NSData*)profile error:(NSError **)error {
    [self ensureHeartbeatWithError:error];
    if(*error) return NO;

    MisagentClientHandle* misagentHandle = 0;
    IdeviceFfiError * err = misagent_connect(provider, &misagentHandle);
    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        idevice_error_free(err);
        return NO;
    }
    
    err = misagent_install(misagentHandle, [profile bytes], [profile length]);
    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        misagent_client_free(misagentHandle);
        idevice_error_free(err);
        return NO;
    }
    
    misagent_client_free(misagentHandle);
    return YES;
}

@end

@implementation CMSDecoderHelper
+ (NSData*)decodeCMSData:(NSData *)cmsData error:(NSError **)error {
    if (!cmsData || cmsData.length == 0) return nil;
    NSData *xmlStart = [@"<?xml" dataUsingEncoding:NSASCIIStringEncoding];
    NSData *plistEnd = [@"</plist>" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange startRange = [cmsData rangeOfData:xmlStart options:0 range:NSMakeRange(0, cmsData.length)];
    if (startRange.location != NSNotFound) {
        NSRange endRange = [cmsData rangeOfData:plistEnd options:0 range:NSMakeRange(startRange.location, cmsData.length - startRange.location)];
        if (endRange.location != NSNotFound) {
            return [cmsData subdataWithRange:NSMakeRange(startRange.location, NSMaxRange(endRange) - startRange.location)];
        }
    }
    return nil;
}
@end
