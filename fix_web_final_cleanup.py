import sys

with open('WebBrowserViewController.m', 'r') as f:
    lines = f.readlines()

header = []
impl = []
found_impl = False
for line in lines:
    if '@implementation' in line:
        found_impl = True
    if found_impl:
        impl.append(line)
    else:
        header.append(line)

# Clean header from implementations
clean_header = []
for line in header:
    if '@interface' in line or '@property' in line or '@end' in line or line.startswith('#import') or line.strip() == '':
        clean_header.append(line)
    # Skip implementations in header
    elif line.strip().startswith('-') or line.strip().startswith('{'):
        continue

# Clean impl from duplications
clean_impl = []
seen_methods = set()
in_method = False
current_method_name = ""
method_lines = []

for line in impl:
    if line.strip().startswith('- (void)') or line.strip().startswith('- (BOOL)'):
        # Extract method name for deduplication
        name = line.split('(')[0] if '(' in line else line
        # This is too complex for a quick script.
        # I'll just rewrite the file manually with the known good state.
        pass

with open('WebBrowserViewController.m', 'w') as f:
    f.writelines(clean_header)
    f.writelines(impl)
