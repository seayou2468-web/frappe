#import "IdeviceManager.h"
#import <netinet/in.h>
#import <arpa/inet.h>
#import <stdlib.h>

@implementation IdeviceManager

+ (instancetype)sharedManager {
    static IdeviceManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[IdeviceManager alloc] init];
    });
    return shared;
}

- (void)connectWithIP:(NSString *)ip port:(int)port pairingPath:(NSString *)path completion:(void (^)(BOOL success, NSString *message))completion {
    [self disconnect];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct IdevicePairingFile *pairing = NULL;
        struct IdeviceFfiError *err = idevice_pairing_file_read([path UTF8String], &pairing);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"Pairing Error: %s", err->message];
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, msg); });
            return;
        }

        struct sockaddr_in sa;
        memset(&sa, 0, sizeof(sa));
        sa.sin_family = AF_INET;
        sa.sin_port = htons(port);
        inet_pton(AF_INET, [ip UTF8String], &sa.sin_addr);

        struct IdeviceProviderHandle *newProvider = NULL;
        err = idevice_tcp_provider_new((const idevice_sockaddr *)&sa, pairing, "IdeviceManager", &newProvider);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"Provider Error: %s", err->message];
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, msg); });
            return;
        }

        self.provider = newProvider;

        struct LockdowndClientHandle *lockdown = NULL;
        err = lockdownd_connect(newProvider, &lockdown);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"Lockdown Error: %s", err->message];
            idevice_error_free(err);
            [self disconnect];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, msg); });
            return;
        }

        plist_t deviceNamePlist = NULL;
        err = lockdownd_get_value(lockdown, NULL, "DeviceName", &deviceNamePlist);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"Get Value Error: %s", err->message];
            idevice_error_free(err);
            lockdownd_client_free(lockdown);
            [self disconnect];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, msg); });
            return;
        }

        NSString *deviceName = [self objectFromPlist:deviceNamePlist];
        plist_free(deviceNamePlist);
        lockdownd_client_free(lockdown);

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES, [NSString stringWithFormat:@"Connected to %@", deviceName]);
        });
    });
}

- (void)disconnect {
    if (self.provider) {
        idevice_provider_free(self.provider);
        self.provider = NULL;
    }
}

- (void)fetchDeviceInfoWithCompletion:(void (^)(NSDictionary *, NSString *))completion {
    if (!self.provider) { if(completion) completion(nil, @"Not connected"); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct LockdowndClientHandle *lockdown = NULL;
        struct IdeviceFfiError *err = lockdownd_connect(self.provider, &lockdown);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"Lockdown Error: %s", err->message];
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ if(completion) completion(nil, msg); });
            return;
        }

        plist_t values = NULL;
        err = lockdownd_get_value(lockdown, NULL, NULL, &values);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"Get Values Error: %s", err->message];
            idevice_error_free(err);
            lockdownd_client_free(lockdown);
            dispatch_async(dispatch_get_main_queue(), ^{ if(completion) completion(nil, msg); });
            return;
        }

        NSDictionary *dict = [self objectFromPlist:values];
        plist_free(values);
        lockdownd_client_free(lockdown);
        dispatch_async(dispatch_get_main_queue(), ^{ if(completion) completion(dict, nil); });
    });
}

- (void)listAppsWithCompletion:(void (^)(NSArray *, NSString *))completion {
    if (!self.provider) { if(completion) completion(nil, @"Not connected"); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct InstallationProxyClientHandle *instproxy = NULL;
        struct IdeviceFfiError *err = installation_proxy_connect(self.provider, &instproxy);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"InstProxy Connect Error: %s", err->message];
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ if(completion) completion(nil, msg); });
            return;
        }

        plist_t client_opts = plist_new_dict();
        plist_dict_set_item(client_opts, "ApplicationType", plist_new_string("Any"));

        plist_t *results = NULL;
        size_t results_len = 0;
        err = installation_proxy_browse(instproxy, client_opts, &results, &results_len);
        plist_free(client_opts);

        if (err) {
            NSString *msg = [NSString stringWithFormat:@"Browse Error: %s", err->message];
            idevice_error_free(err);
            installation_proxy_client_free(instproxy);
            dispatch_async(dispatch_get_main_queue(), ^{ if(completion) completion(nil, msg); });
            return;
        }

        NSMutableArray *apps = [NSMutableArray arrayWithCapacity:results_len];
        for (size_t i = 0; i < results_len; i++) {
            id obj = [self objectFromPlist:results[i]];
            if (obj) [apps addObject:obj];
        }
        idevice_plist_array_free(results, (uintptr_t)results_len);

        installation_proxy_client_free(instproxy);
        dispatch_async(dispatch_get_main_queue(), ^{ if(completion) completion(apps, nil); });
    });
}

- (void)listDirectory:(NSString *)path completion:(void (^)(NSArray *, NSString *))completion {
    if (!self.provider) { if(completion) completion(nil, @"Not connected"); return; }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        struct AfcClientHandle *afc = NULL;
        struct IdeviceFfiError *err = afc_client_connect(self.provider, &afc);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"AFC Connect Error: %s", err->message];
            idevice_error_free(err);
            dispatch_async(dispatch_get_main_queue(), ^{ if(completion) completion(nil, msg); });
            return;
        }

        char **list = NULL;
        size_t count = 0;
        err = afc_list_directory(afc, [path UTF8String], &list, &count);
        if (err) {
            NSString *msg = [NSString stringWithFormat:@"List Dir Error: %s", err->message];
            idevice_error_free(err);
            afc_client_free(afc);
            dispatch_async(dispatch_get_main_queue(), ^{ if(completion) completion(nil, msg); });
            return;
        }

        NSMutableArray *items = [NSMutableArray arrayWithCapacity:count];
        if (list) {
            for (size_t i = 0; i < count; i++) {
                if (list[i]) {
                    [items addObject:[NSString stringWithUTF8String:list[i]]];
                }
            }
            idevice_outer_slice_free(list, (uintptr_t)count);
        }

        afc_client_free(afc);
        dispatch_async(dispatch_get_main_queue(), ^{ if(completion) completion(items, nil); });
    });
}

- (id)objectFromPlist:(plist_t)plist {
    return [self objectFromPlist:plist depth:0];
}

- (id)objectFromPlist:(plist_t)plist depth:(int)depth {
    if (!plist || depth > 20) return nil;

    plist_type nodeType = plist_get_node_type(plist);
    switch (nodeType) {
        case PLIST_BOOLEAN: {
            uint8_t val = 0;
            plist_get_bool_val(plist, &val);
            return @(val != 0);
        }
        case PLIST_INT: {
            int64_t val = 0;
            plist_get_int_val(plist, &val);
            return @(val);
        }
        case PLIST_REAL: {
            double val = 0;
            plist_get_real_val(plist, &val);
            return @(val);
        }
        case PLIST_STRING: {
            char *val = NULL;
            plist_get_string_val(plist, &val);
            NSString *s = val ? [NSString stringWithUTF8String:val] : @"";
            if (val) plist_mem_free(val);
            return s;
        }
        case PLIST_DATA: {
            char *val = NULL;
            uint64_t len = 0;
            plist_get_data_val(plist, &val, &len);
            if (len > 5 * 1024 * 1024) { // 5MB limit
                if (val) plist_mem_free(val);
                return nil;
            }
            NSData *d = val ? [NSData dataWithBytes:val length:len] : [NSData data];
            if (val) plist_mem_free(val);
            return d;
        }
        case PLIST_ARRAY: {
            uint32_t size = plist_array_get_size(plist);
            NSMutableArray *arr = [NSMutableArray arrayWithCapacity:size];
            for (uint32_t i = 0; i < size; i++) {
                plist_t item = plist_array_get_item(plist, i);
                id obj = [self objectFromPlist:item depth:depth + 1];
                if (obj) [arr addObject:obj];
            }
            return arr;
        }
        case PLIST_DICT: {
            uint32_t size = plist_dict_get_size(plist);
            NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:size];
            plist_dict_iter iter = NULL;
            plist_dict_new_iter(plist, &iter);
            char *key = NULL;
            plist_t val = NULL;
            while (true) {
                plist_dict_next_item(plist, iter, &key, &val);
                if (!key) break;
                id obj = [self objectFromPlist:val depth:depth + 1];
                if (obj) [dict setObject:obj forKey:[NSString stringWithUTF8String:key]];
                plist_mem_free(key);
            }
            plist_dict_free_iter(iter);
            return dict;
        }
        case PLIST_DATE: {
            int64_t sec = 0;
            plist_get_unix_date_val(plist, &sec);
            return [NSDate dateWithTimeIntervalSince1970:sec];
        }
        default:
            return nil;
    }
}

@end
