import sys

with open("AppManager.m", "r") as f:
    content = f.read()

# 1. Fix method names for HeartbeatManager
content = content.replace("] pause]", "] pauseHeartbeat]")
content = content.replace("] resume]", "] resumeHeartbeat]")

# 2. Fix redefinition of 'proxy'
# The issue is likely that 'proxy' was already defined in the surrounding scope in some methods,
# or I inserted the robust block multiple times where it was already declared.

# Let's check where 'proxy' is declared and remove redundant declarations.
# I will change 'struct CoreDeviceProxyHandle *proxy = NULL;' to just 'proxy = NULL;' if it's already declared.

# In my robust_connect_code, I had:
# struct CoreDeviceProxyHandle *proxy = NULL;

# If I use 'struct CoreDeviceProxyHandle *proxy = NULL;' inside a block that already has 'proxy' declared, it will fail.
# However, fetchProfiles, install, and remove were newly implemented by me and I know where I put them.

# Actually, I'll just change the robust block to use a locally unique name if needed, or just remove the declaration part if it's already there.

lines = content.split('\n')
new_lines = []
declared_proxies = set()

# A more surgical approach:
# I'll look for the start of methods and reset the declared_proxies set.
for line in lines:
    if line.strip().startswith("- (void)") or line.strip().startswith("- (NSArray"):
        declared_proxies = set()

    if "struct CoreDeviceProxyHandle *proxy =" in line:
        if "proxy" in declared_proxies:
            line = line.replace("struct CoreDeviceProxyHandle *proxy =", "proxy =")
        else:
            declared_proxies.add("proxy")

    new_lines.append(line)

content = '\n'.join(new_lines)

with open("AppManager.m", "w") as f:
    f.write(content)
