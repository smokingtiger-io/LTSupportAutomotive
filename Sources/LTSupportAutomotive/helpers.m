//
//  Copyright (c) Dr. Michael Lauer Information Technology. All rights reserved.
//
#import "helpers.h"

#define LTSUPPORTAUTOMOTIVE_STRINGS_PATH @"Frameworks/LTSupportAutomotive.framework/LTSupportAutomotive"

static NSBundle* LTSupportAutomotiveResourceBundle( void )
{
    static NSBundle* bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // SwiftPM emits an accessor named SWIFTPM_MODULE_BUNDLE when the
        // target ships resources. When the library is consumed via SPM
        // the localized strings live in that bundle, not in the bundle
        // that owns LTVIN's class (which under static linking is the
        // host app bundle and so has no Localizable.strings of ours).
        Class anchor = NSClassFromString(@"LTVIN");
        NSBundle* classBundle = anchor ? [NSBundle bundleForClass:anchor] : [NSBundle mainBundle];
#ifdef SWIFTPM_MODULE_BUNDLE
        bundle = SWIFTPM_MODULE_BUNDLE;
#else
        NSURL* nested = [classBundle URLForResource:@"LTSupportAutomotive_LTSupportAutomotive" withExtension:@"bundle"];
        bundle = nested ? [NSBundle bundleWithURL:nested] : classBundle;
#endif
        if ( !bundle )
        {
            bundle = classBundle;
        }
    });
    return bundle;
}

NSString* LTStringLookupOrNil( NSString* key )
{
    NSString* value = [LTSupportAutomotiveResourceBundle() localizedStringForKey:key value:nil table:nil];
    return [value isEqualToString:key] ? nil : value;
}

NSString* LTStringLookupWithPlaceholder( NSString* key, NSString* placeholder )
{
    return [LTSupportAutomotiveResourceBundle() localizedStringForKey:key value:placeholder table:nil];
}

void MyNSLog(const char *file, int lineNumber, const char *functionName, NSString *format, ...)
{
    va_list ap;
    va_start (ap, format);
    if ( ![format hasSuffix:@"\n"] )
    {
        format = [format stringByAppendingString:@"\n"];
    }
    NSString* body = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end (ap);

    NSString* fileName = [[NSString stringWithUTF8String:file] lastPathComponent];
    fprintf( stderr, "%s (%s:%d) %s", functionName, [fileName UTF8String], lineNumber, body.UTF8String );
}

NSString* LTDataToString( NSData* d )
{
    NSString* s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    return [[s stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
}

void LTPostNotificationOnMain( NSString* name, id object )
{
    if ( [NSThread isMainThread] )
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:name object:object];
        return;
    }
    dispatch_async( dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:name object:object];
    });
}
