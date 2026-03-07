import re

with open('IdeviceManager.m', 'r') as f:
    lines = f.readlines()

# Collect everything that is currently between @interface and @end (the first pair)
# and everything between @implementation and @end (the second pair)

interface_lines = []
implementation_lines = []
other_lines = [] # Imports etc

state = "OTHER"
for line in lines:
    if line.startswith('@interface IdeviceManager ()'):
        state = "INTERFACE"
        interface_lines.append(line)
        continue
    if state == "INTERFACE":
        interface_lines.append(line)
        if line.startswith('@end'):
            state = "OTHER"
        continue

    if line.startswith('@implementation IdeviceManager'):
        state = "IMPLEMENTATION"
        implementation_lines.append(line)
        continue
    if state == "IMPLEMENTATION":
        implementation_lines.append(line)
        if line.startswith('@end'):
            state = "OTHER"
        continue

    if state == "OTHER":
        other_lines.append(line)

# Now, find methods that are trapped in other_lines or interface_lines and move them to implementation_lines
def extract_methods(src_lines):
    methods = []
    current_method = []
    in_method = False
    brace_count = 0
    remaining = []

    for line in src_lines:
        if line.strip().startswith('- (') or line.strip().startswith('+ ('):
            in_method = True
            current_method.append(line)
            brace_count += line.count('{') - line.count('}')
            if '{' in line and brace_count == 0: # single line method?
                 methods.append("".join(current_method))
                 current_method = []
                 in_method = False
            continue

        if in_method:
            current_method.append(line)
            brace_count += line.count('{') - line.count('}')
            if brace_count == 0 and '}' in line:
                methods.append("".join(current_method))
                current_method = []
                in_method = False
        else:
            remaining.append(line)
    return methods, remaining

methods_from_other, clean_other = extract_methods(other_lines)
methods_from_interface, clean_interface = extract_methods(interface_lines)

# Implementation usually ends with @end. We want to insert BEFORE the last @end.
if implementation_lines and implementation_lines[-1].strip() == '@end':
    final_impl = implementation_lines[:-1] + methods_from_other + methods_from_interface + [implementation_lines[-1]]
else:
    final_impl = implementation_lines + methods_from_other + methods_from_interface

with open('IdeviceManager.m', 'w') as f:
    f.writelines(clean_other)
    f.writelines(clean_interface)
    f.writelines(final_impl)
