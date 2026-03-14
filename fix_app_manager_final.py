import sys

file_path = 'AppManager.m'
with open(file_path, 'r') as f:
    content = f.read()

new_extraction = """
        plist_t bidNode = plist_dict_get_item(item, "CFBundleIdentifier");
        if (bidNode) {
            char *val = NULL; plist_get_string_val(bidNode, &val);
            if (val) { info.bundleId = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
        }
        if (!info.bundleId) continue;

        plist_t nameNode = plist_dict_get_item(item, "CFBundleDisplayName");
        if (!nameNode) nameNode = plist_dict_get_item(item, "CFBundleName");
        if (nameNode) {
            char *val = NULL; plist_get_string_val(nameNode, &val);
            if (val) { info.name = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
        }
        if (!info.name) info.name = info.bundleId;

        plist_t verNode = plist_dict_get_item(item, "CFBundleShortVersionString");
        if (!verNode) verNode = plist_dict_get_item(item, "CFBundleVersion");
        if (verNode) {
            char *val = NULL; plist_get_string_val(verNode, &val);
            if (val) { info.version = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
        }

        plist_t pathNode = plist_dict_get_item(item, "Path");
        if (pathNode) {
            char *val = NULL; plist_get_string_val(pathNode, &val);
            if (val) { info.path = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
        }

        plist_t signerNode = plist_dict_get_item(item, "SignerIdentity");
        if (signerNode) {
            char *val = NULL; plist_get_string_val(signerNode, &val);
            if (val) { info.signer = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
        }

        plist_t typeNode = plist_dict_get_item(item, "ApplicationType");
        if (typeNode) {
            char *val = NULL; plist_get_string_val(typeNode, &val);
            if (val) { info.type = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
        }

        plist_t containerNode = plist_dict_get_item(item, "Container");
        if (containerNode) {
            char *val = NULL; plist_get_string_val(containerNode, &val);
            if (val) { info.container = [NSString stringWithUTF8String:val]; plist_mem_free(val); }
        }

        plist_t usageNode = plist_dict_get_item(item, "StaticDiskUsage");
        if (usageNode) {
            uint64_t bytes = 0; plist_get_uint_val(usageNode, &bytes);
            if (bytes > 0) {
                if (bytes > 1024*1024*1024) info.diskUsage = [NSString stringWithFormat:@"%.2f GB", (double)bytes/(1024*1024*1024)];
                else if (bytes > 1024*1024) info.diskUsage = [NSString stringWithFormat:@"%.2f MB", (double)bytes/(1024*1024)];
                else info.diskUsage = [NSString stringWithFormat:@"%llu KB", bytes/1024];
            }
        }
"""

old_extraction_pattern = r'plist_t bidNode = plist_dict_get_item\(item, "CFBundleIdentifier"\);.*?info\.name = info\.bundleId;'

import re
content = re.sub(old_extraction_pattern, new_extraction.strip(), content, flags=re.DOTALL)

with open(file_path, 'w') as f:
    f.write(content)
