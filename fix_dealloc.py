import re

with open('IdeviceManager.m', 'r') as f:
    content = f.read()

if '- (void)dealloc {' not in content:
    content = content.replace('@end', '- (void)dealloc { [self disconnect]; }\n@end')

with open('IdeviceManager.m', 'w') as f:
    f.write(content)
