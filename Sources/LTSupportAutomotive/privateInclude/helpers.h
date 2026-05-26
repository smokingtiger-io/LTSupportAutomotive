//
//  Copyright (c) Dr. Michael Lauer Information Technology. All rights reserved.
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSString* _Nullable LTStringLookupOrNil( NSString* key );
NSString* LTStringLookupWithPlaceholder( NSString* key, NSString* placeholder );
void MyNSLog(const char *file, int lineNumber, const char *functionName, NSString *format, ...);
NSString* LTDataToString( NSData* d );

// Posts an NSNotification onto the main queue regardless of the calling
// thread. NSNotificationCenter delivers synchronously on the posting
// thread, and large parts of this library run on BLE / dispatch /
// stream threads — so naive postNotificationName: would deliver to UI
// observers on a background thread. Always main-marshal these.
void LTPostNotificationOnMain( NSString* name, id _Nullable object );

NS_ASSUME_NONNULL_END

// global macros
#ifndef LOG
    #define LOG(args...) MyNSLog(__FILE__,__LINE__,__PRETTY_FUNCTION__,args);
#endif

#ifndef UTF8_NARROW_NOBREAK_SPACE
    #define UTF8_NARROW_NOBREAK_SPACE @"\u202F"
#endif

// Severity-tagged log macros. Distinguishing WARN/ERROR from LOG used
// to be impossible because both expanded to the same MyNSLog call.
// Now the format string is prefixed at compile time via NSString
// literal concatenation so output is greppable and oslog filtering
// can pick on the tag. All call sites in the library pass an NSString
// literal as the first argument; if a caller ever passes a runtime
// string, the concatenation would fail at compile time, which is the
// signal to migrate that site to LOG.
#ifndef WARN
#define WARN(...) MyNSLog( __FILE__, __LINE__, __PRETTY_FUNCTION__, @"[WARN] " __VA_ARGS__ )
#endif

#ifndef ERROR
#define ERROR(...) MyNSLog( __FILE__, __LINE__, __PRETTY_FUNCTION__, @"[ERROR] " __VA_ARGS__ )
#endif
