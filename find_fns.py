import re

with open("idevice.h", "r") as f:
    content = f.read()

fns = [
    "plist_free",
    "plist_get_node_type",
    "plist_array_get_size",
    "plist_array_get_item",
    "plist_dict_get_item",
    "plist_get_string_val",
    "plist_get_bool_val",
    "core_device_proxy_connect_tcp_stream"
]

for fn in fns:
    if fn in content:
        # Find the line with the function declaration
        matches = re.findall(rf".*{fn}.*\(", content)
        for m in matches:
            print(f"Found: {m.strip()}")
    else:
        print(f"NOT FOUND: {fn}")
