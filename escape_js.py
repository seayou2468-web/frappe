import sys

def escape_string(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n"\n"')

with open('universal.js', 'r') as f:
    u = f.read()

with open('attachDetach.js', 'r') as f:
    a = f.read()

print('#import <Foundation/Foundation.h>')
print('static NSString *const kUniversalJitScript = @"' + escape_string(u) + '";')
print('static NSString *const kAttachDetachScript = @"' + escape_string(a) + '";')
