#import "PPTXCompatibilityReader.h"
#import "OOXMLPackageReader.h"

@implementation PPTXCompatibilityReader

+ (NSString *)xmlDecoded:(NSString *)s {
    NSString *v = [s copy] ?: @"";
    v = [v stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    v = [v stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    v = [v stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    v = [v stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    v = [v stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"];
    return v;
}

+ (NSDictionary *)readPresentationFromOOXMLPath:(NSString *)filePath {
    NSMutableArray<NSArray<NSString *> *> *slides = [NSMutableArray array];
    NSArray<NSString *> *entries = [OOXMLPackageReader entryNamesInZipAtPath:filePath];
    NSArray<NSString *> *slideEntries = [[entries filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *entry, NSDictionary *_) {
        return [entry hasPrefix:@"ppt/slides/slide"] && [entry hasSuffix:@".xml"];
    }]] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSNumericSearch];
    }];

    NSRegularExpression *textRe = [NSRegularExpression regularExpressionWithPattern:@"<a:t[^>]*>(.*?)</a:t>" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    for (NSString *entry in slideEntries) {
        NSData *data = [OOXMLPackageReader dataForEntry:entry inZipAtPath:filePath];
        NSString *xml = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
        NSArray<NSTextCheckingResult *> *matches = [textRe matchesInString:xml options:0 range:NSMakeRange(0, xml.length)];
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        for (NSTextCheckingResult *m in matches) {
            if (m.numberOfRanges < 2) continue;
            NSString *t = [xml substringWithRange:[m rangeAtIndex:1]];
            t = [self xmlDecoded:t];
            if (t.length) [texts addObject:t];
        }
        [slides addObject:texts];
    }
    NSArray<NSString *> *vbaEntries = [OOXMLPackageReader vbaRelatedEntryNamesInZipAtPath:filePath];
    return @{
        @"slides": slides,
        @"hasMacros": @([OOXMLPackageReader hasVBAMacroProjectInZipAtPath:filePath]),
        @"vbaEntries": vbaEntries ?: @[]
    };
}

+ (NSArray<NSArray<NSString *> *> *)readSlideTextsFromPPTXPath:(NSString *)filePath {
    NSDictionary *presentation = [self readPresentationFromOOXMLPath:filePath];
    return presentation[@"slides"] ?: @[];
}

@end
