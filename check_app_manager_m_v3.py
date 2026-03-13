import sys

with open("AppManager.m", "r") as f:
    content = f.read()

# Check for fixed names
bad_names = [
    "idevice_plist_free",
    "idevice_plist_get_node_type",
    "core_device_proxy_connect_tcp_stream"
]

for name in bad_names:
    if name in content:
        print(f"Found forbidden name {name} in AppManager.m")
        sys.exit(1)

print("AppManager.m looks good (v3).")
