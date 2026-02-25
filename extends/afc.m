NS_ASSUME_NONNULL_BEGIN
//
//  afc.m
//  StikDebug
//
//  Created by Duy Tran on 2026/01/14.
//
#include <string.h>
#include <stdlib.h>

#import "JITEnableContext.h"
#import "JITEnableContextInternal.h"
#import <Foundation/Foundation.h>

@implementation JITEnableContext(AFC)

- (BOOL)afcIsPathDirectory:(NSString *)path {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        return NO;
    }
    struct AfcClientHandle *client = NULL;
    IdeviceFfiError* err = afc_client_connect(provider, &client);
    if (err) {
        idevice_error_free(err);
        return NO;
    }

    struct AfcFileInfo info;
    err = afc_get_file_info(client, path.fileSystemRepresentation, &info);
    BOOL is_dir = NO;
    if (!err) {
        is_dir = (info.st_ifmt && !strcmp(info.st_ifmt, "S_IFDIR"));
        afc_file_info_free(&info);
    } else {
        idevice_error_free(err);
    }

    afc_client_free(client);
    return is_dir;
}

- (NSArray<NSString *> *)afcListDir:(NSString *)path error:(NSError * _Nullable * _Nullable)error {
    if (!provider) {
        if (error) *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return nil;
    }
    struct AfcClientHandle *client = NULL;
    IdeviceFfiError* err = afc_client_connect(provider, &client);
    if (err) {
        if (error) *error = [self errorWithStr:@"Failed to connect to AFC!" code:err->code];
        idevice_error_free(err);
        return nil;
    }

    char **entries = NULL;
    size_t count = 0;
    NSMutableArray<NSString *>* results = [NSMutableArray array];
    err = afc_list_directory(client, path.fileSystemRepresentation, &entries, &count);
    if (!err) {
        for (size_t i = 0; i < count; i++) {
            if (entries[i]) {
                [results addObject:[NSString stringWithUTF8String:entries[i]]];
                free(entries[i]);
            }
        }
        free(entries);
    } else {
        if (error) *error = [self errorWithStr:@"Failed to list directory!" code:err->code];
        idevice_error_free(err);
        afc_client_free(client);
        return nil;
    }

    afc_client_free(client);
    return results;
}

- (BOOL)afcPushFile:(NSString *)sourcePath toPath:(NSString *)destPath error:(NSError * _Nullable * _Nullable)error {
    if (!provider) {
        if (error) *error = [self errorWithStr:@"Provider not initialized!" code:-1];
        return NO;
    }
    struct AfcClientHandle *client = NULL;
    IdeviceFfiError* err = afc_client_connect(provider, &client);
    if (err) {
        if (error) *error = [self errorWithStr:@"Failed to connect to AFC!" code:err->code];
        idevice_error_free(err);
        return NO;
    }

    struct AfcFileHandle *handle = NULL;
    err = afc_file_open(client, destPath.fileSystemRepresentation, AfcWrOnly, &handle);
    if (err) {
        if (error) *error = [self errorWithStr:@"Failed to open destination file on device!" code:err->code];
        idevice_error_free(err);
        afc_client_free(client);
        return NO;
    }

    NSData* fileData = [NSData dataWithContentsOfFile:sourcePath];
    if (fileData) {
        afc_file_write(handle, fileData.bytes, fileData.length);
    }
    afc_file_close(handle);

    afc_client_free(client);
    return YES;
}

@end
NS_ASSUME_NONNULL_END
