//
//  afc.m
//  StikDebug
//
//  Created by Duy Tran on 2026/01/14.
//

#import "JITEnableContext.h"
#import "JITEnableContextInternal.h"
#import "FileManagerCore.h"
#import <Foundation/Foundation.h>

@implementation JITEnableContext(AFC)

- (BOOL)afcIsPathDirectory:(NSString *)path {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        return NO;
    }
    AfcClientHandle *client = NULL;
    IdeviceFfiError* err = afc_client_connect(provider, &client);
    if (err) {
        idevice_error_free(err);
        return NO;
    }

    AfcFileInfo info;
    err = afc_get_file_info(client, path.fileSystemRepresentation, &info);
    if (err) {
        idevice_error_free(err);
        afc_client_free(client);
        return NO;
    }

    BOOL is_dir = (info.st_ifmt && !strcmp(info.st_ifmt, "S_IFDIR"));
    afc_file_info_free(&info);

    afc_client_free(client);
    return is_dir;
}

- (NSArray<NSString *> *)afcListDir:(NSString *)path error:(NSError **)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        if (error) *error = makeError(-1, @"Provider not initialized!");
        return nil;
    }
    AfcClientHandle *client = NULL;
    IdeviceFfiError* err = afc_client_connect(provider, &client);
    if (err) {
        if (error) *error = makeError(err->code, @(err->message));
        idevice_error_free(err);
        return nil;
    }

    char **entries = NULL;
    size_t count = 0;
    NSMutableArray<NSString *>* results = [NSMutableArray array];
    err = afc_list_directory(client, path.fileSystemRepresentation, &entries, &count);
    if (err) {
        if (error) *error = makeError(err->code, @(err->message));
        idevice_error_free(err);
        afc_client_free(client);
        return nil;
    }

    for (size_t i = 0; i < count; i++) {
        if (entries[i]) {
            [results addObject:@(entries[i])];
            free(entries[i]);
        }
    }
    if (entries) free(entries);

    afc_client_free(client);
    return results;
}

- (BOOL)afcPushFile:(NSString *)sourcePath toPath:(NSString *)destPath error:(NSError **)error {
    if (!provider) {
        NSLog(@"Provider not initialized!");
        if (error) *error = makeError(-1, @"Provider not initialized!");
        return NO;
    }
    AfcClientHandle *client = NULL;
    IdeviceFfiError* err = afc_client_connect(provider, &client);
    if (err) {
        if (error) *error = makeError(err->code, @(err->message));
        idevice_error_free(err);
        return NO;
    }

    AfcFileHandle *handle = NULL;
    err = afc_file_open(client, destPath.fileSystemRepresentation, AfcWrOnly, &handle);
    if (err) {
        if (error) *error = makeError(err->code, @(err->message));
        idevice_error_free(err);
        afc_client_free(client);
        return NO;
    }

    NSData* fileData = [NSData dataWithContentsOfFile:sourcePath];
    if (fileData) {
        err = afc_file_write(handle, fileData.bytes, fileData.length);
        if (err) {
            if (error) *error = makeError(err->code, @(err->message));
            idevice_error_free(err);
        }
    } else {
        if (error) *error = makeError(-2, @"Failed to read source file!");
    }

    afc_file_close(handle);
    afc_client_free(client);

    return (error == NULL || *error == nil);
}

@end

@implementation JITEnableContext(AFC_Extra)

- (NSArray<FileItem *> *)afcContentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
    NSArray<NSString *> *names = [self afcListDir:path error:error];
    if (!names) return nil;

    NSMutableArray<FileItem *> *items = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) continue;

        FileItem *item = [[FileItem alloc] init];
        item.name = name;
        item.fullPath = [path stringByAppendingPathComponent:name];
        item.isDirectory = [self afcIsPathDirectory:item.fullPath];
        [items addObject:item];
    }
    return items;
}

@end
