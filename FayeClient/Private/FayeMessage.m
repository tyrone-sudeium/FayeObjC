/* The MIT License
 
 Copyright (c) 2011 Paul Crawford
 Copyright (c) 2013 Tyrone Trevorrow
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE. */

//
//  FayeMessage.m
//  FayeObjC
//

#import "FayeMessage.h"
#import <objc/runtime.h>

@implementation FayeMessage

+ (NSDateFormatter*) dateTimeFormatter
{
    static NSString *dateTimeFormatString = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    static NSDateFormatter *dateFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [NSDateFormatter new];
        [dateFormatter setFormatterBehavior: NSDateFormatterBehavior10_4];
        [dateFormatter setDateFormat: dateTimeFormatString];
    });
    return dateFormatter;
}

+ (NSDateFormatter*) dateTimeZoneFormatter
{
    static NSString *dateTimeFormatString = @"yyyy-MM-dd'T'HH:mm:ssz";
    static NSDateFormatter *dateFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [NSDateFormatter new];
        [dateFormatter setFormatterBehavior: NSDateFormatterBehavior10_4];
        [dateFormatter setDateFormat: dateTimeFormatString];
    });
    return dateFormatter;
}

- (id) initWithDict:(NSDictionary *)dict
{
    self = [super init];
    if (self != nil) {
        NSArray *properties = @[@"channel",
                                @"clientId",
                                @"successful",
                                @"authSuccessful",
                                @"version",
                                @"minimumVersion",
                                @"supportedConnectionTypes",
                                @"advice",
                                @"error",
                                @"subscription",
                                @"data",
                                @"ext",
                                @"fayeId"];
        for (NSString *propertyName in properties) {
            id object = dict[propertyName];
            if (object != [NSNull null]) {
                [self setValue: object forKey: propertyName];
            }
        }
        
        NSString *timestamp = dict[@"timestamp"];
        if (timestamp) {
            if ([timestamp hasSuffix: @"Z"]) {
                self.timestamp = [[FayeMessage dateTimeFormatter] dateFromString: timestamp];
            } else {
                self.timestamp = [[FayeMessage dateTimeZoneFormatter] dateFromString: timestamp];
            }
        }
    }
    return self;
}

- (NSString*)description {
    NSMutableString *desc = [NSMutableString stringWithString: @"\n"];
    unsigned int propCount = 0;
    objc_property_t *props = class_copyPropertyList([self class], &propCount);
    for (unsigned int i = 0; i < propCount; i++) {
        NSString *propName = [NSString stringWithUTF8String: property_getName(props[i])];
        if([self valueForKey: propName]) {
            [desc appendFormat: @"%@ : %@\n", propName, [self valueForKey:propName]];
        }
    }
    
    return desc.copy;
}

@end
