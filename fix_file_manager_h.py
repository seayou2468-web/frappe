import os

file_path = 'FileManagerCore.h'
with open(file_path, 'r') as f:
    content = f.read()

helper_decl = "+ (NSString *)effectiveHomeDirectory;"
if helper_decl not in content:
    content = content.replace("+ (NSString *)relativeToHomePath:(NSString *)absolutePath;", helper_decl + "\n+ (NSString *)relativeToHomePath:(NSString *)absolutePath;")

with open(file_path, 'w') as f:
    f.write(content)
