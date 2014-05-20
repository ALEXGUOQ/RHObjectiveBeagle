//
//  RHObjectiveBeagle.m
//
//  Created by Richard Heard on 19/05/2014.
//  Copyright (c) 2014 Richard Heard. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions
//  are met:
//  1. Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright
//  notice, this list of conditions and the following disclaimer in the
//  documentation and/or other materials provided with the distribution.
//  3. The name of the author may not be used to endorse or promote products
//  derived from this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
//  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
//  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
//  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
//  NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
//  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
//  THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//  References:
//  http://lists.cs.uiuc.edu/pipermail/lldb-commits/Week-of-Mon-20120116/004775.html
//  http://books.google.com/books?id=K8vUkpOXhN4C&pg=PA972&lpg=PA972&dq=MALLOC_PTR_IN_USE_RANGE_TYPE&source=bl&ots=OLhfT_Yv0C&sig=vgdZVfNjrAM9e3tMtADOTGzzVRo&hl=en&sa=X&ei=B795U8DXM6zjsATimoIw&ved=0CEgQ6AEwBg#v=onepage&q=MALLOC_PTR_IN_USE_RANGE_TYPE&f=false
//  https://www.mikeash.com/pyblog/friday-qa-2013-09-27-arm64-and-you.html
//  http://www.sealiesoftware.com/blog/archive/2013/09/24/objc_explain_Non-pointer_isa.html
//  https://www.opensource.apple.com/source/Libc/Libc-825.40.1/gen/magazine_malloc.c
//  http://www.cocoawithlove.com/2010/05/look-at-how-malloc-works-on-mac.html
//
//  (lldb) command script import lldb.macosx.heap
//  ptr_refs --help
//

#import "RHObjectiveBeagle.h"

#include <objc/objc-api.h>
#include <objc/runtime.h>
#include <malloc/malloc.h>
#include <mach/mach.h>


#pragma mark internal - arc support

#if __has_feature(objc_arc)

    #define arc_retain(x)       (x)
    #define arc_release(x)
    #define arc_autorelease(x)  (x)

#else

    #define arc_retain(x)       ([x retain])
    #define arc_release(x)      ([x release])
    #define arc_autorelease(x)  ([x autorelease])

    #ifndef __bridge
        #define __bridge
    #endif
    #ifndef __bridge_retained
        #define __bridge_retained
    #endif
    #ifndef __bridge_transfer
        #define __bridge_transfer
    #endif

#endif

#ifndef RH_OBJECTIVE_BEAGLE_M
#define RH_OBJECTIVE_BEAGLE_M 1

#pragma mark - internal - defs

#define OPTION_ENABLED(options, option) ((options & option) == option)
#define ROUND_TO_MULTIPLE(num, multiple) ((num) && (multiple) ? (num) + (multiple) - 1 - ((num) - 1) % (multiple) : 0)


static kern_return_t RHReadMemory(task_t task, vm_address_t remote_address, vm_size_t size, void **local_memory);
static void _RHZoneIntrospectionEnumeratorFindInstancesCallback(task_t task, void *baton, unsigned type, vm_range_t *ranges, unsigned count);
extern NSArray * _RHBeagleFindInstancesOfClassWithOptionsInternal(Class aClass, RHBeagleFindOptions options);
static BOOL _RHBeagleIsKnownUnsafeClass(Class aClass);
static Class _RHBeagleClassFromString(NSString *className);


#pragma mark - public - instance search

NSArray * beagle(NSString *className) {
    Class aClass = _RHBeagleClassFromString(className);
    if (!aClass) return nil;
    return beagle_getInstancesOfClass(aClass);
}

NSArray * beagle_exact(NSString *className) {
    Class aClass = _RHBeagleClassFromString(className);
    if (!aClass) return nil;
    return beagle_getInstancesOfExactClass(aClass);
}

id beagle_first(NSString *className) {
    Class aClass = _RHBeagleClassFromString(className);
    if (!aClass) return nil;
    return beagle_getFirstInstanceOfClass(aClass);
}


#pragma mark - public - verbose instance search

NSArray * beagle_getInstancesOfClass(Class aClass) {
    return RHBeagleFindInstancesOfClassWithOptions(aClass, RHBeagleFindOptionsDefault);
}

NSArray * beagle_getInstancesOfExactClass(Class aClass) {
    return RHBeagleFindInstancesOfClassWithOptions(aClass, RHBeagleFindOptionExcludeSubclasses);
}

id beagle_getFirstInstanceOfClass(Class aClass) {
    //RHBeagleFindOptionFirstMatch only returns a single object, so its safe to use lastObject.
    return [RHBeagleFindInstancesOfClassWithOptions(aClass, RHBeagleFindOptionFirstMatch) lastObject];
}


#pragma mark - public - class search

extern NSArray * beagle_classes(NSString *partialName){
    return beagle_getClassesWithPrefix(partialName);
}

extern NSArray * beagle_subclasses(NSString *className) {
    Class aClass = _RHBeagleClassFromString(className);
    if (!aClass) return nil;
    return beagle_getSubclassesOfClass(aClass);
}


#pragma mark - public - verbose class search

NSArray * beagle_getSubclassesOfClass(Class aClass) {
    return RHBeagleGetSubclassesOfClass(aClass);
}

NSArray * beagle_getClassesWithPrefix(NSString *partialName){
    return RHBeagleGetClassesWithNameAndOptions(partialName, NSAnchoredSearch);

}


#pragma mark - public - RHObjectiveBeagleAdditions

@implementation NSObject (RHObjectiveBeagleAdditions)

+ (NSArray *)beagle_instances {
    return beagle_getInstancesOfClass([self class]);
}

+ (NSArray *)beagle_exactInstances {
    return beagle_getInstancesOfExactClass([self class]);
}

+ (id)beagle_firstInstance {
    return beagle_getFirstInstanceOfClass([self class]);
}

#pragma mark - misc
+ (id)beagle_subclasses {
    return RHBeagleGetSubclassesOfClass([self class]);
}

@end


#pragma mark - public - implementation

NSArray * RHBeagleFindInstancesOfClassWithOptions(Class aClass, RHBeagleFindOptions options) {
    
    //if someone has passed us a string, massage it into an actual class
    if ([(id)aClass isKindOfClass:[NSString class]]) {
        aClass = _RHBeagleClassFromString((NSString*)aClass);
    }
    
    //sanity check
    if (!aClass) {
        NSLog(@"RHBeagle: Error: class must not be NULL.");
        return nil;
    }
    
    return _RHBeagleFindInstancesOfClassWithOptionsInternal(aClass, options);
}


#pragma mark - public - misc

NSArray * RHBeagleGetSubclassesOfClass(Class query){
    int count = objc_getClassList(NULL, 0);
    if (count < 0) return nil;
    
    CFMutableArrayRef results = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if (!results) return nil;
    
    if (count > 0) {
        Class *classes = (Class *)malloc(sizeof(Class) * count);
        count = objc_getClassList(classes, count);
        
        for (int i = 0; i < count; i++) {
            
            if (_RHBeagleIsKnownUnsafeClass(classes[i])){
                continue;
            }

            for (Class current = class_getSuperclass(classes[i]); current != NULL; current = class_getSuperclass(current)){
                if (current == query) {
                    CFArrayAppendValue(results, (__bridge void *)classes[i]);
                    break;
                }
            }
        }
        
        free(classes);
    }
    
    //cleanup
    CFArrayRef result = CFArrayCreateCopy(kCFAllocatorDefault, results);
    CFRelease(results);
    
    return arc_autorelease((__bridge_transfer NSArray *)result);
}

NSArray * RHBeagleGetClassesWithNameAndOptions(NSString *partialName, NSStringCompareOptions options){
    int count = objc_getClassList(NULL, 0);
    if (count < 0) return nil;
    
    CFMutableArrayRef results = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if (!results) return nil;
    
    if (count > 0) {
        Class *classes = (Class *)malloc(sizeof(Class) * count);
        count = objc_getClassList(classes, count);
        
        for (int i = 0; i < count; i++) {
            Class current = classes[i];
            if ([NSStringFromClass(current) rangeOfString:partialName options:options].length > 0) {
                
                if (!_RHBeagleIsKnownUnsafeClass(current)){
                    CFArrayAppendValue(results, (__bridge void *)current);
                }
            }
        }
        
        free(classes);
    }
    
    //cleanup
    CFArrayRef result = CFArrayCreateCopy(kCFAllocatorDefault, results);
    CFRelease(results);
    
    return arc_autorelease((__bridge_transfer NSArray *)result);
}


#pragma mark - internal - implementation

//passed to _RHZoneIntrospectionEnumeratorFindInstancesCallback as baton
typedef struct _RHBeagleFindContext {
    Class query;
    CFArrayRef subclasses;
    CFMutableArrayRef results;
    NSUInteger options;
    BOOL canceled; //atm, only used in conjunction with option first
} RHBeagleFindContext;
typedef RHBeagleFindContext* RHBeagleFindContextRef;


static kern_return_t RHReadMemory(task_t task, vm_address_t remote_address, vm_size_t size, void **local_memory) {
    *local_memory = (void*) remote_address;
    return KERN_SUCCESS;
}

typedef struct _RHObjectStandin {
    Class isa;
} RHObjectStandin;


#pragma mark - internal - callback
static void _RHZoneIntrospectionEnumeratorFindInstancesCallback(task_t task, void *baton, unsigned type, vm_range_t *ranges, unsigned count) {
    RHBeagleFindContextRef context = (RHBeagleFindContextRef)baton;
    
    //bail if we have been canceled
    if (context->canceled){
        return;
    }
    
    for (unsigned i = 0; i < count; i++) {
        vm_range_t *range =  &ranges[i];
        
        void *data = (void *)range->address;
        size_t size = range->size;
        
        //make sure range is big enough to contain an "object" sized pointer
        if (size < sizeof(RHObjectStandin)){
            continue;
        }
        
        uintptr_t *pointers = (uintptr_t *)data;
        
#if defined(__arm64__)
        //MAGIC: for arm64 tagged isa pointers : (http://www.sealiesoftware.com/blog/archive/2013/09/24/objc_explain_Non-pointer_isa.html)
        //Note: We can't use object_getClass directly because we have no idea if the pointer is actually to an object or not at this point in time.
        extern uint64_t objc_debug_isa_class_mask WEAK_IMPORT_ATTRIBUTE;

        uint64_t taggedPointerMask;
        if (objc_debug_isa_class_mask != 0x0){
            //fall back to 0x00000001fffffff8 as of 19th May 2014; Not ABI stable..
            taggedPointerMask = 0x00000001fffffff8;
        } else {
            taggedPointerMask = objc_debug_isa_class_mask;
        }
        
        void * isa = (void *)(pointers[0] & taggedPointerMask);

#elif (defined(__i386__) || defined(__x86_64__) || defined(__arm__))
        //regular stuff, on these known arcs.
        void * isa = (void *)pointers[0];
#else
        //unknown arch. we need to be updated depending on whether or not the arch uses tagged isa pointers
#error Unknown architecture. We don't know if tagged isa pointers are used, therefore we can't continue.
#endif
        
        
        Class matchedClass = NULL;
        
        //check for a direct class pointer match
        if (isa == (__bridge void *)context->query){
            matchedClass = context->query;
        }
        
        //check for subclass pointer match
        if (!OPTION_ENABLED(context->options, RHBeagleFindOptionExcludeSubclasses) && context->subclasses) {
            CFIndex count = CFArrayGetCount(context->subclasses);
            for (CFIndex i = 0; i < count; i++) {
                Class possibleClass = CFArrayGetValueAtIndex(context->subclasses, i);
                if (isa == (__bridge void *)possibleClass) {
                    matchedClass = possibleClass;
                    break;
                }
            }
        }
        
        //bail on this zone if we didn't find a matching class pointer
        if (matchedClass == NULL){
            continue;
        }
        
        //remove "unsafe" classes from subclasses by default
        if (!OPTION_ENABLED(context->options, RHBeagleFindOptionIncludeKnownUnsafeObjects)) {
            if (_RHBeagleIsKnownUnsafeClass(matchedClass)){
                continue;
            }
        }

        
        //sanity check the zone size, making sure that it's the correct size for the classes instance size
        size_t needed = class_getInstanceSize(matchedClass);
        
        //malloc operates as per: http://www.cocoawithlove.com/2010/05/look-at-how-malloc-works-on-mac.html
        //therefore we need to round needed size to nearest quantum allocation size before comparing it to the ranges size
        
        //these next defs are from the last known malloc source: https://www.opensource.apple.com/source/Libc/Libc-825.40.1/gen/magazine_malloc.c (10.8.5) ( See : http://openradar.io/15365352 )
#define SHIFT_TINY_QUANTUM      4 // Required for AltiVec
#define	TINY_QUANTUM           (1 << SHIFT_TINY_QUANTUM)
        
#ifdef __LP64__
#define NUM_TINY_SLOTS          64	// number of slots for free-lists
#else
#define NUM_TINY_SLOTS          32	// number of slots for free-lists
#endif
        
        //this next one is extracted from inlined logic spread throughout scalable_malloc.c (think tiny)
#define SMALL_THRESHOLD            ((NUM_TINY_SLOTS - 1) * TINY_QUANTUM)
        
        //tiny; 16 bytes allocation
        if (needed <= SMALL_THRESHOLD){
            size_t rounded = ROUND_TO_MULTIPLE(needed, 16);
            if (rounded != size) continue;
        } else {
            //small; 512 bytes allocation (we ignore large allocations)
            size_t rounded = ROUND_TO_MULTIPLE(needed, 512);
            if (rounded != size) continue;
        }
        
        //if LastMatch; remove any previously added results (Not exactly optimal.. )
        if (OPTION_ENABLED(context->options, RHBeagleFindOptionLastMatch)){
            CFArrayRemoveAllValues(context->results);
        }
        
        //add to results
        CFArrayAppendValue(context->results, data);
        
        //if FirstMatch; cancel the remainder of our processing
        if (OPTION_ENABLED(context->options, RHBeagleFindOptionFirstMatch)){
            context->canceled = YES;
        }
    }
}


NSArray * _RHBeagleFindInstancesOfClassWithOptionsInternal(Class class, RHBeagleFindOptions options) {
    
    //grab the zones in the current process
    vm_address_t *zones = NULL;
    unsigned int count = 0;
    kern_return_t error = malloc_get_all_zones(0, &RHReadMemory, &zones, &count);
    if (error != KERN_SUCCESS){
        NSLog(@"[RHBeagle] Error: malloc_get_all_zones failed.");
        return nil;
    }
    
    
    //create our context object
    RHBeagleFindContext *context = calloc(sizeof(RHBeagleFindContext), 1);
    if (!context){
        NSLog(@"[RHBeagle] Error: failed to calloc memory for an RHBeagleFindContext struct.");
        return nil;
    }
    
    context->query = class;
    context->options = options;
    context->results = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

    //subclasses
    CFArrayRef subclasses = (__bridge CFArrayRef)RHBeagleGetSubclassesOfClass(class);
    if (subclasses) context->subclasses = CFRetain(subclasses);
    
    for (unsigned i = 0; i < count; i++) {
        const malloc_zone_t *zone = (const malloc_zone_t *)zones[i];
        if (zone == NULL || zone->introspect == NULL){
            continue;
        }
        
        //for each zone, enumerate using our enumerator callback
        zone->introspect->enumerator(mach_task_self(), context, MALLOC_PTR_IN_USE_RANGE_TYPE, zones[i], &RHReadMemory, &_RHZoneIntrospectionEnumeratorFindInstancesCallback);
    }
    
    
    //cleanup RHBeagleFindContext
    NSArray *result = (__bridge NSArray *)CFArrayCreateCopy(kCFAllocatorDefault, context->results);
    
    if (context->subclasses) CFRelease(context->subclasses);
    if (context->results) CFRelease(context->results);
    free(context);
    
    //success
    return arc_autorelease(result);
}


static BOOL _RHBeagleIsKnownUnsafeClass(Class aClass) {
    NSString *className = NSStringFromClass(aClass);
    
    if ([@"NSPlaceholderString" isEqualToString:className]) return YES;
    if ([@"__NSPlaceholderArray" isEqualToString:className]) return YES;
    if ([@"NSPlaceholderValue" isEqualToString:className]) return YES;
    if ([@"__ARCLite__" isEqualToString:className]) return YES;
    if ([@"__NSMessageBuilder" isEqualToString:className]) return YES;
    if ([@"__NSGenericDeallocHandler" isEqualToString:className]) return YES;
    if ([@"Object" isEqualToString:className]) return YES;
    if ([@"_NSZombie_" isEqualToString:className]) return YES;
    
    
    return NO;
}

#define CLASS_SEARCH_THRESHOLD 3
#define CLASS_FUZZY_SEARCH_THRESHOLD 12

static Class _RHBeagleClassFromString(NSString *className) {
    if (className && ![className isKindOfClass:[NSString class]]) {
        return object_getClass((Class)className);
    }
    
    Class aClass = NSClassFromString(className);
    if (!aClass) {
        NSInteger classNameLength = [className length];
        if (classNameLength <= CLASS_SEARCH_THRESHOLD){
            NSLog(@"[RHBeagle] Error: Unknown class '%@'.", className);
            return nil;
        }

        //psudo fuzzy mistyped class matching for longer class names
        NSString *fuzzyClassName = className;
        if (classNameLength > CLASS_FUZZY_SEARCH_THRESHOLD){
            fuzzyClassName = [fuzzyClassName substringWithRange:NSMakeRange(CLASS_SEARCH_THRESHOLD, classNameLength - (2 * CLASS_SEARCH_THRESHOLD))];
        }
        NSArray *possibleMatches = RHBeagleGetClassesWithNameAndOptions(fuzzyClassName, NSCaseInsensitiveSearch);
        
        NSString *question = [possibleMatches count] > 0 ? @"Perhaps you want one of these:" : @"";
        NSLog(@"[RHBeagle] Error: Unknown class '%@'. %@\n\t%@\n", className, question, [possibleMatches componentsJoinedByString:@"\n\t"]);
        
        return NULL;
    }
    
    return aClass;
}


#pragma mark - public - passthrough debug methods

#define SAFE_PASSTHROUGH( selectorName ) do { \
    SEL selector = NSSelectorFromString(selectorName); \
    if (![[self class] instancesRespondToSelector:selector]) return [NSString stringWithFormat:@"[RHBeagle] Error: Class '%@' does not implement instance method '%@'.", NSStringFromClass([self class]), selectorName]; \
_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Warc-performSelector-leaks\"") \
    return [self performSelector:selector]; \
_Pragma("clang diagnostic pop") \
} while (0)

@implementation NSObject (RHBeaglePassthroughAdditions)

- (id)beagle_ivarDescription {
    SAFE_PASSTHROUGH(@"_ivarDescription");
}

- (id)beagle_methodDescription {
    SAFE_PASSTHROUGH(@"_methodDescription");
}

- (id)beagle_shortMethodDescription {
    SAFE_PASSTHROUGH(@"_shortMethodDescription");
}

@end

#endif //end RH_OBJECTIVE_BEAGLE_M

/*
 
 .
 ..
 ...
 ....
 WOOF!
 ......
 .......
 ........
 .........
 ..........
 ...........
 ............
 .............
 ..............
 ...............
 ................
 .................
 ..................
 ...................
 ....................
 .....................
 ......................
 .......................
 ........................
 .........................
 ..........................
 ...........................
 ............................
 .............................
 ..............................
 ...............................
 .................................
 ..................................
 ...................................
 ....................................
 .....................................
 ......................................
 .......................................
 ........................................
 ........................................
 ..                        __          ..
 ..        ,             ," e`--o      ..
 ..       ((            (    __,'      ..
 ..        \\~---------' \_;/          ..
 ..        (               /           ..
 ..        /) .________.  )            ..
 ..       (( (        (( (             ..
 ..        ``-'        ``-'            ..
 ..                                    ..
 .. "Don't mind me, I'm just chilling" ..
 ..     - Objective Beagle, 2014       ..
 ..                                    ..
 ........................................

 
 */

