import re

with open('IdeviceManager.m', 'r') as f:
    content = f.read()

# Fix potential NULL pointer in inet_pton
content = content.replace(
    'if (inet_pton(AF_INET, [ip UTF8String], &sa.sin_addr) <= 0) { [self _handleError:@"IPアドレスの形式が正しくありません"]; return; }',
    'if (!ip || ip.length == 0 || inet_pton(AF_INET, [ip UTF8String], &sa.sin_addr) <= 0) { [self _handleError:@"IPアドレスの形式が正しくありません"]; return; }'
)

# Ensure idevice_error_free is only called on non-NULL
# Actually most free functions are safe, but let's be extra safe with FFI
def safe_ffi_free(match):
    ptr = match.group(1)
    return f'if ({ptr}) idevice_error_free({ptr});'

content = re.sub(r'idevice_error_free\((.*?)\);', safe_ffi_free, content)

with open('IdeviceManager.m', 'w') as f:
    f.write(content)
