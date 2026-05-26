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

#ifndef WARN
#define WARN LOG
#endif

#ifndef ERROR
#define ERROR LOG
#endif
