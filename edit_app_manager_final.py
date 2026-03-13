import sys

with open("AppManager.m", "r") as f:
    content = f.read()

# Fix undeclared functions and incorrect names
# 1. idevice_plist_free -> plist_free
# 2. idevice_plist_get_node_type -> plist_get_node_type
# 3. idevice_plist_array_get_size -> plist_array_get_size
# 4. idevice_plist_array_get_item -> plist_array_get_item
# 5. idevice_plist_dict_get_item -> plist_dict_get_item
# 6. idevice_plist_get_string_val -> plist_get_string_val
# 7. idevice_plist_get_bool_val -> plist_get_bool_val
# 8. core_device_proxy_connect_tcp_stream -> adapter_connect (with adapter)

content = content.replace("idevice_plist_free", "plist_free")
content = content.replace("idevice_plist_get_node_type", "plist_get_node_type")
content = content.replace("idevice_plist_array_get_size", "plist_array_get_size")
content = content.replace("idevice_plist_array_get_item", "plist_array_get_item")
content = content.replace("idevice_plist_dict_get_item", "plist_dict_get_item")
content = content.replace("idevice_plist_get_string_val", "plist_get_string_val")
content = content.replace("idevice_plist_get_bool_val", "plist_get_bool_val")

# Fix core_device_proxy_connect_tcp_stream(proxy, rsdPort, &rsdStream)
# It should be:
# struct AdapterHandle *adapter = NULL;
# err = core_device_proxy_create_tcp_adapter(proxy, &adapter);
# err = adapter_connect(adapter, rsdPort, &rsdStream);

# Let's use a more robust replacement for the TCP stream connection part
tcp_connect_old = """            struct ReadWriteOpaque *rsdStream = NULL;
            struct IdeviceFfiError *streamErr = core_device_proxy_connect_tcp_stream(proxy, rsdPort, &rsdStream);
            if (streamErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to connect to RSD stream: %s", streamErr->message];
                idevice_error_free(streamErr); core_device_proxy_free(proxy);
                safeCompletion(nil, msg); return;
            }"""

tcp_connect_new = """            struct AdapterHandle *adapter = NULL;
            struct IdeviceFfiError *adapterErr = core_device_proxy_create_tcp_adapter(proxy, &adapter);
            if (adapterErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to create adapter: %s", adapterErr->message];
                idevice_error_free(adapterErr); core_device_proxy_free(proxy);
                safeCompletion(nil, msg); return;
            }
            struct ReadWriteOpaque *rsdStream = NULL;
            struct IdeviceFfiError *streamErr = adapter_connect(adapter, rsdPort, &rsdStream);
            if (streamErr) {
                NSString *msg = [NSString stringWithFormat:@"Failed to connect to RSD stream: %s", streamErr->message];
                idevice_error_free(streamErr); core_device_proxy_free(proxy);
                safeCompletion(nil, msg); return;
            }"""

content = content.replace(tcp_connect_old, tcp_connect_new)

# Repeat for install and remove methods
tcp_connect_generic_old = """            struct ReadWriteOpaque *rsdStream = NULL;
            core_device_proxy_connect_tcp_stream(proxy, rsdPort, &rsdStream);"""

tcp_connect_generic_new = """            struct AdapterHandle *adapter = NULL;
            core_device_proxy_create_tcp_adapter(proxy, &adapter);
            struct ReadWriteOpaque *rsdStream = NULL;
            adapter_connect(adapter, rsdPort, &rsdStream);"""

content = content.replace(tcp_connect_generic_old, tcp_connect_generic_new)

with open("AppManager.m", "w") as f:
    f.writelines(content)
