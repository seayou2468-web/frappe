import re

with open('IdeviceManager.m', 'r') as f:
    content = f.read()

# 1. Extract Imports
imports = re.findall(r'^#import.*$', content, re.MULTILINE)
header = "\n".join(imports) + "\n\n"

# 2. Extract Class Extension
extension_match = re.search(r'@interface IdeviceManager \(\).*?@end', content, re.DOTALL)
if extension_match:
    extension_block = extension_match.group(0)
    # Remove method implementations from extension block if any
    # Extension should only have properties/ivars
    # We'll just take the properties/ivars manually to be safe
    props = re.findall(r'@property.*?;', extension_block)
    ivars_match = re.search(r'\{.*?\}', extension_block, re.DOTALL)
    ivars = ivars_match.group(0) if ivars_match else ""
    extension = "@interface IdeviceManager ()\n" + ivars + "\n" + "\n".join(props) + "\n@end\n\n"
else:
    extension = ""

# 3. Extract all methods
# Methods start with - ( or + ( and end with }
# This is tricky because of nested blocks. We use brace counting.
methods = []
# We'll search through the whole content for method starts
# But we need to avoid the interface declarations if they are just prototypes (though we don't have many here)
# Actually, let's just find everything that looks like a method implementation.
method_starts = list(re.finditer(r'^[+-]\s*\(.*?\).*?\{', content, re.MULTILINE))

def get_full_method(start_pos, text):
    brace_count = 0
    in_method = False
    for i in range(start_pos, len(text)):
        if text[i] == '{':
            brace_count += 1
            in_method = True
        elif text[i] == '}':
            brace_count -= 1

        if in_method and brace_count == 0:
            return text[start_pos:i+1]
    return None

seen_method_sigs = set()
unique_methods = []

for m in method_starts:
    full = get_full_method(m.start(), content)
    if full:
        # Extract signature to avoid duplicates
        sig_match = re.match(r'^[+-]\s*\(.*?\).*?(?=\{)', full, re.DOTALL)
        if sig_match:
            sig = sig_match.group(0).strip()
            if sig not in seen_method_sigs:
                seen_method_sigs.add(sig)
                unique_methods.append(full)

# 4. Extract Synthesizes
synthesizes = re.findall(r'@synthesize.*?;', content)
synth_block = "\n".join(synthesizes) + "\n\n"

# 5. Reconstruct
final_content = header + extension + "@implementation IdeviceManager\n\n" + synth_block + "\n\n".join(unique_methods) + "\n\n@end\n"

with open('IdeviceManager.m', 'w') as f:
    f.write(final_content)
