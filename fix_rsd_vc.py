import re

with open('IdeviceRsdViewController.m', 'r') as f:
    content = f.read()

old_cell = r"""    NSDictionary *svc = self.services[indexPath.row];
    cell.textLabel.text = svc[@"name"] ?: @"Unknown Service";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"Port: %@ | XPC: %@", svc[@"port"], svc[@"uses_remote_xpc"]];
    return cell;"""

new_cell = r"""    NSDictionary *svc = self.services[indexPath.row];
    cell.textLabel.text = svc[@"name"] ?: @"Unknown Service";
    NSString *ent = svc[@"entitlement"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"Port: %@%@", svc[@"port"], ent ? [NSString stringWithFormat:@" | %@", ent] : @""];
    return cell;"""

content = content.replace(old_cell, new_cell)

with open('IdeviceRsdViewController.m', 'w') as f:
    f.write(content)
