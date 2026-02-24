#include "mount.h"
#import "JITEnableContext.h"
#import "JITEnableContextInternal.h"
#import <Foundation/Foundation.h>

@implementation JITEnableContext(DDI)

- (NSUInteger)getMountedDeviceCount:(NSError**)error {
    [self ensureHeartbeatWithError:error];
    if(*error) return 0;

    ImageMounterHandle* client = 0;
    IdeviceFfiError* err = image_mounter_connect(provider, &client);
    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        idevice_error_free(err);
        return 0;
    }
    plist_t* devices;
    size_t deviceLength = 0;
    err = image_mounter_copy_devices(client, &devices, &deviceLength);
    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        idevice_error_free(err);
        image_mounter_free(client);
        return 0;
    }
    for(size_t i = 0; i < deviceLength; ++i) {
        plist_free(devices[i]);
    }
    idevice_data_free((uint8_t *)devices, deviceLength*sizeof(plist_t));
    image_mounter_free(client);
    return deviceLength;
}

- (NSInteger)mountPersonalDDIWithImagePath:(NSString*)imagePath trustcachePath:(NSString*)trustcachePath manifestPath:(NSString*)manifestPath error:(NSError**)error {
    [self ensureHeartbeatWithError:error];
    if(*error) return -1;

    NSData* image = [NSData dataWithContentsOfFile:imagePath];
    NSData* trustcache = [NSData dataWithContentsOfFile:trustcachePath];
    NSData* buildManifest = [NSData dataWithContentsOfFile:manifestPath];
    if(!image || !trustcache || !buildManifest) {
        if (error) *error = [self errorWithStr:@"Failed to read one or more files" code:1];
        return 1;
    }
    
    IdevicePairingFile* pairingFile = [self getPairingFileWithError:error];
    if (*error) return 2;

    LockdowndClientHandle* lockdownClient = 0;
    IdeviceFfiError* err = lockdownd_connect(provider, &lockdownClient);
    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        idevice_pairing_file_free(pairingFile);
        idevice_error_free(err);
        return 6;
    }
    
    err = lockdownd_start_session(lockdownClient, pairingFile);
    idevice_pairing_file_free(pairingFile);
    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        idevice_error_free(err);
        lockdownd_client_free(lockdownClient);
        return 7;
    }
    
    plist_t uniqueChipIDPlist = 0;
    err = lockdownd_get_value(lockdownClient, "UniqueChipID", 0, &uniqueChipIDPlist);
    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        idevice_error_free(err);
        lockdownd_client_free(lockdownClient);
        return 8;
    }
    
    uint64_t uniqueChipID = 0;
    plist_get_uint_val(uniqueChipIDPlist, &uniqueChipID);
    plist_free(uniqueChipIDPlist);
    lockdownd_client_free(lockdownClient);

    ImageMounterHandle* mounterClient = 0;
    err = image_mounter_connect(provider, &mounterClient);
    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        idevice_error_free(err);
        return 9;
    }
    
    err = image_mounter_mount_personalized(
        mounterClient,
        provider,
        [image bytes],
        [image length],
        [trustcache bytes],
        [trustcache length],
        [buildManifest bytes],
        [buildManifest length],
        nil,
        uniqueChipID
    );
    
    if (err) {
        if (error) *error = [self errorWithStr:@(err->message) code:err->code];
        idevice_error_free(err);
        image_mounter_free(mounterClient);
        return 10;
    }
    
    image_mounter_free(mounterClient);
    return 0;
}
@end
