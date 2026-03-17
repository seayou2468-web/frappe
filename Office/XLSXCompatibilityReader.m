#import "XLSXCompatibilityReader.h"
#import "OOXMLPackageReader.h"

@implementation XLSXCompatibilityReader

+ (NSString *)xmlDecoded:(NSString *)s {
    NSString *v = [s copy] ?: @"";
    v = [v stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    v = [v stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    v = [v stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    v = [v stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    v = [v stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"];
    return v;
}

+ (NSInteger)columnIndexFromName:(NSString *)name {
    NSInteger col = 0;
    for (NSInteger i = 0; i < (NSInteger)name.length; i++) {
        unichar ch = [name characterAtIndex:i];
        if (ch < 'A' || ch > 'Z') break;
        col = col * 26 + (ch - 'A' + 1);
    }
    return MAX(0, col - 1);
}

+ (BOOL)parseCellRef:(NSString *)ref row:(NSInteger *)rowOut col:(NSInteger *)colOut {
    if (ref.length == 0) return NO;
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSInteger split = -1;
    for (NSInteger i = 0; i < (NSInteger)ref.length; i++) {
        if ([digits characterIsMember:[ref characterAtIndex:i]]) { split = i; break; }
    }
    if (split <= 0) return NO;
    NSString *colName = [[ref substringToIndex:split] uppercaseString];
    NSString *rowName = [ref substringFromIndex:split];
    NSInteger row = rowName.integerValue - 1;
    NSInteger col = [self columnIndexFromName:colName];
    if (row < 0 || col < 0) return NO;
    if (rowOut) *rowOut = row;
    if (colOut) *colOut = col;
    return YES;
}

+ (NSDictionary *)readWorkbookFromOOXMLPath:(NSString *)filePath {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    NSArray<NSString *> *entries = [OOXMLPackageReader entryNamesInZipAtPath:filePath];
    if (entries.count == 0) return @{@"sheets": result, @"hasMacros": @NO, @"vbaEntries": @[]};

    NSData *sharedData = [OOXMLPackageReader dataForEntry:@"xl/sharedStrings.xml" inZipAtPath:filePath];
    NSString *sharedXML = sharedData ? [[NSString alloc] initWithData:sharedData encoding:NSUTF8StringEncoding] : nil;
    NSMutableArray<NSString *> *sharedStrings = [NSMutableArray array];
    if (sharedXML.length > 0) {
        NSRegularExpression *tRe = [NSRegularExpression regularExpressionWithPattern:@"<t[^>]*>(.*?)</t>" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
        NSArray<NSTextCheckingResult *> *matches = [tRe matchesInString:sharedXML options:0 range:NSMakeRange(0, sharedXML.length)];
        for (NSTextCheckingResult *m in matches) {
            if (m.numberOfRanges < 2) continue;
            NSString *text = [sharedXML substringWithRange:[m rangeAtIndex:1]];
            [sharedStrings addObject:[self xmlDecoded:text]];
        }
    }

    NSArray<NSString *> *sheetEntries = [[entries filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *entry, NSDictionary *_) {
        return [entry hasPrefix:@"xl/worksheets/sheet"] && [entry hasSuffix:@".xml"];
    }]] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSNumericSearch];
    }];

    NSRegularExpression *cellRe = [NSRegularExpression regularExpressionWithPattern:@"<c\\b([^>]*)>(.*?)</c>" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSRegularExpression *refRe = [NSRegularExpression regularExpressionWithPattern:@"\\br=\"([A-Z]+[0-9]+)\"" options:0 error:nil];
    NSRegularExpression *typeRe = [NSRegularExpression regularExpressionWithPattern:@"\\bt=\"([^\"]+)\"" options:0 error:nil];
    NSRegularExpression *vRe = [NSRegularExpression regularExpressionWithPattern:@"<v[^>]*>(.*?)</v>" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSRegularExpression *isRe = [NSRegularExpression regularExpressionWithPattern:@"<t[^>]*>(.*?)</t>" options:NSRegularExpressionDotMatchesLineSeparators error:nil];

    NSInteger idx = 0;
    for (NSString *entry in sheetEntries) {
        NSData *sheetData = [OOXMLPackageReader dataForEntry:entry inZipAtPath:filePath];
        NSString *sheetXML = sheetData ? [[NSString alloc] initWithData:sheetData encoding:NSUTF8StringEncoding] : @"";
        NSMutableArray<NSDictionary *> *cells = [NSMutableArray array];
        NSInteger maxRow = 0, maxCol = 0;

        NSArray<NSTextCheckingResult *> *matches = [cellRe matchesInString:sheetXML options:0 range:NSMakeRange(0, sheetXML.length)];
        for (NSTextCheckingResult *match in matches) {
            if (match.numberOfRanges < 3) continue;
            NSString *attrs = [sheetXML substringWithRange:[match rangeAtIndex:1]];
            NSString *inner = [sheetXML substringWithRange:[match rangeAtIndex:2]];

            NSTextCheckingResult *refMatch = [refRe firstMatchInString:attrs options:0 range:NSMakeRange(0, attrs.length)];
            if (!refMatch || refMatch.numberOfRanges < 2) continue;
            NSString *ref = [attrs substringWithRange:[refMatch rangeAtIndex:1]];

            NSInteger row = 0, col = 0;
            if (![self parseCellRef:ref row:&row col:&col]) continue;

            NSString *type = nil;
            NSTextCheckingResult *typeMatch = [typeRe firstMatchInString:attrs options:0 range:NSMakeRange(0, attrs.length)];
            if (typeMatch.numberOfRanges >= 2) type = [attrs substringWithRange:[typeMatch rangeAtIndex:1]];

            NSString *value = @"";
            NSTextCheckingResult *vMatch = [vRe firstMatchInString:inner options:0 range:NSMakeRange(0, inner.length)];
            if (vMatch.numberOfRanges >= 2) {
                value = [inner substringWithRange:[vMatch rangeAtIndex:1]];
            } else {
                NSTextCheckingResult *isMatch = [isRe firstMatchInString:inner options:0 range:NSMakeRange(0, inner.length)];
                if (isMatch.numberOfRanges >= 2) value = [inner substringWithRange:[isMatch rangeAtIndex:1]];
            }

            if ([type isEqualToString:@"s"]) {
                NSInteger sharedIdx = value.integerValue;
                if (sharedIdx >= 0 && sharedIdx < (NSInteger)sharedStrings.count) value = sharedStrings[sharedIdx];
            } else {
                value = [self xmlDecoded:value];
            }

            [cells addObject:@{ @"row": @(row), @"col": @(col), @"value": value ?: @"" }];
            maxRow = MAX(maxRow, row);
            maxCol = MAX(maxCol, col);
        }

        [result addObject:@{
            @"name": [NSString stringWithFormat:@"Sheet%ld", (long)(idx + 1)],
            @"cells": cells,
            @"maxRow": @(maxRow),
            @"maxCol": @(maxCol)
        }];
        idx++;
    }

    NSArray<NSString *> *vbaEntries = [OOXMLPackageReader vbaRelatedEntryNamesInZipAtPath:filePath];
    return @{
        @"sheets": result,
        @"hasMacros": @([OOXMLPackageReader hasVBAMacroProjectInZipAtPath:filePath]),
        @"vbaEntries": vbaEntries ?: @[]
    };
}

+ (NSArray<NSDictionary *> *)readSheetsFromXLSXPath:(NSString *)filePath {
    NSDictionary *wb = [self readWorkbookFromOOXMLPath:filePath];
    return wb[@"sheets"] ?: @[];
}

@end
