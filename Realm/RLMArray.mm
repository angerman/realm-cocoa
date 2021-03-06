////////////////////////////////////////////////////////////////////////////
//
// Copyright 2014 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

#import "RLMArray_Private.hpp"

#import "RLMObject_Private.h"
#import "RLMObjectStore.h"
#import "RLMObjectSchema.h"
#import "RLMQueryUtil.hpp"
#import "RLMSwiftSupport.h"
#import "RLMUtil.hpp"

#import <realm/link_view.hpp>

@implementation RLMArray {
@public
    // array for standalone
    NSMutableArray *_backingArray;
}

template<typename IndexSetFactory>
static void changeArray(__unsafe_unretained RLMArray *const ar, NSKeyValueChange kind, dispatch_block_t f, IndexSetFactory&& is) {
    if (!ar->_backingArray) {
        ar->_backingArray = [NSMutableArray new];
    }

    if (RLMObjectBase *parent = ar->_parentObject) {
        NSIndexSet *indexes = is();
        [parent willChange:kind valuesAtIndexes:indexes forKey:ar->_key];
        f();
        [parent didChange:kind valuesAtIndexes:indexes forKey:ar->_key];
    }
    else {
        f();
    }
}

static void changeArray(__unsafe_unretained RLMArray *const ar, NSKeyValueChange kind, NSUInteger index, dispatch_block_t f) {
    changeArray(ar, kind, f, [=] { return [NSIndexSet indexSetWithIndex:index]; });
}

static void changeArray(__unsafe_unretained RLMArray *const ar, NSKeyValueChange kind, NSRange range, dispatch_block_t f) {
    changeArray(ar, kind, f, [=] { return [NSIndexSet indexSetWithIndexesInRange:range]; });
}

static void changeArray(__unsafe_unretained RLMArray *const ar, NSKeyValueChange kind, NSIndexSet *is, dispatch_block_t f) {
    changeArray(ar, kind, f, [=] { return is; });
}

- (instancetype)initWithObjectClassName:(NSString *)objectClassName {
    self = [super init];
    if (self) {
        _objectClassName = objectClassName;
    }
    return self;
}

- (RLMRealm *)realm {
    return nil;
}

//
// Generic implementations for all RLMArray variants
//

- (id)firstObject {
    if (self.count) {
        return [self objectAtIndex:0];
    }
    return nil;
}

- (id)lastObject {
    NSUInteger count = self.count;
    if (count) {
        return [self objectAtIndex:count-1];
    }
    return nil;
}

- (void)addObjects:(id<NSFastEnumeration>)objects {
    for (id obj in objects) {
        [self addObject:obj];
    }
}

- (void)addObject:(RLMObject *)object {
    [self insertObject:object atIndex:self.count];
}

- (void)removeLastObject {
    NSUInteger count = self.count;
    if (count) {
        [self removeObjectAtIndex:count-1];
    }
}

- (id)objectAtIndexedSubscript:(NSUInteger)index {
    return [self objectAtIndex:index];
}

- (void)setObject:(id)newValue atIndexedSubscript:(NSUInteger)index {
    [self replaceObjectAtIndex:index withObject:newValue];
}

//
// Standalone RLMArray implementation
//

static void RLMValidateMatchingObjectType(RLMArray *array, RLMObject *object) {
    if (!object || ![array->_objectClassName isEqualToString:object->_objectSchema.className]) {
        NSString *message = [NSString stringWithFormat:@"Object type '%@' does not match RLMArray type '%@'.", object->_objectSchema.className, array->_objectClassName];
        @throw RLMException(message);
    }
}

static void RLMValidateArrayBounds(__unsafe_unretained RLMArray *const ar,
                                   NSUInteger index, bool allowOnePastEnd=false) {
    NSUInteger max = ar->_backingArray.count + allowOnePastEnd;
    if (index >= max) {
        @throw RLMException([NSString stringWithFormat:@"Index %llu is out of bounds (must be less than %llu).",
                             (unsigned long long)index, (unsigned long long)max]);
    }
}

- (id)objectAtIndex:(NSUInteger)index {
    RLMValidateArrayBounds(self, index);
    if (!_backingArray) {
        _backingArray = [NSMutableArray new];
    }
    return [_backingArray objectAtIndex:index];
}

- (NSUInteger)count {
    return _backingArray.count;
}

- (BOOL)isInvalidated {
    return NO;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(__unsafe_unretained id [])buffer count:(NSUInteger)len {
    return [_backingArray countByEnumeratingWithState:state objects:buffer count:len];
}

- (void)addObjectsFromArray:(NSArray *)array {
    for (id obj in array) {
        RLMValidateMatchingObjectType(self, obj);
    }
    changeArray(self, NSKeyValueChangeInsertion, NSMakeRange(_backingArray.count, array.count), ^{
        [_backingArray addObjectsFromArray:array];
    });
}

- (void)insertObject:(RLMObject *)anObject atIndex:(NSUInteger)index {
    RLMValidateMatchingObjectType(self, anObject);
    RLMValidateArrayBounds(self, index, true);
    changeArray(self, NSKeyValueChangeInsertion, index, ^{
        [_backingArray insertObject:anObject atIndex:index];
    });
}

- (void)insertObjects:(id<NSFastEnumeration>)objects atIndexes:(NSIndexSet *)indexes {
    changeArray(self, NSKeyValueChangeInsertion, indexes, ^{
        NSUInteger currentIndex = [indexes firstIndex];
        for (RLMObject *obj in objects) {
            RLMValidateMatchingObjectType(self, obj);
            [_backingArray insertObject:obj atIndex:currentIndex];
            currentIndex = [indexes indexGreaterThanIndex:currentIndex];
        }
    });
}

- (void)removeObjectAtIndex:(NSUInteger)index {
    RLMValidateArrayBounds(self, index);
    changeArray(self, NSKeyValueChangeRemoval, index, ^{
        [_backingArray removeObjectAtIndex:index];
    });
}

- (void)removeObjectsAtIndexes:(NSIndexSet *)indexes {
    changeArray(self, NSKeyValueChangeRemoval, indexes, ^{
        [_backingArray removeObjectsAtIndexes:indexes];
    });
}

- (void)replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
    RLMValidateMatchingObjectType(self, anObject);
    RLMValidateArrayBounds(self, index);
    changeArray(self, NSKeyValueChangeReplacement, index, ^{
        [_backingArray replaceObjectAtIndex:index withObject:anObject];
    });
}

- (void)moveObjectAtIndex:(NSUInteger)sourceIndex toIndex:(NSUInteger)destinationIndex {
    RLMValidateArrayBounds(self, sourceIndex);
    RLMValidateArrayBounds(self, destinationIndex);
    RLMObjectBase *original = _backingArray[sourceIndex];
    [_backingArray removeObjectAtIndex:sourceIndex];
    [_backingArray insertObject:original atIndex:destinationIndex];
}

- (void)exchangeObjectAtIndex:(NSUInteger)index1 withObjectAtIndex:(NSUInteger)index2 {
    RLMValidateArrayBounds(self, index1);
    RLMValidateArrayBounds(self, index2);
    [_backingArray exchangeObjectAtIndex:index1 withObjectAtIndex:index2];
}

- (NSUInteger)indexOfObject:(RLMObject *)object {
    RLMValidateMatchingObjectType(self, object);
    NSUInteger index = 0;
    for (RLMObject *cmp in _backingArray) {
        if (RLMObjectBaseAreEqual(object, cmp)) {
            return index;
        }
        index++;
    }
    return NSNotFound;
}

- (void)removeAllObjects {
    changeArray(self, NSKeyValueChangeRemoval, NSMakeRange(0, _backingArray.count), ^{
        [_backingArray removeAllObjects];
    });
}

- (RLMResults *)objectsWhere:(NSString *)predicateFormat, ...
{
    va_list args;
    RLM_VARARG(predicateFormat, args);
    return [self objectsWhere:predicateFormat args:args];
}

- (RLMResults *)objectsWhere:(NSString *)predicateFormat args:(va_list)args
{
    return [self objectsWithPredicate:[NSPredicate predicateWithFormat:predicateFormat arguments:args]];
}

- (id)valueForKey:(NSString *)key {
    if ([key isEqualToString:RLMInvalidatedKey]) {
        return @NO; // Standalone arrays are never invalidated
    }
    if (!_backingArray) {
        return @[];
    }
    return [_backingArray valueForKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key {
    [_backingArray setValue:value forKey:key];
}

- (NSUInteger)indexOfObjectWithPredicate:(NSPredicate *)predicate {
    if (!_backingArray) {
        return NSNotFound;
    }
    return [_backingArray indexOfObjectPassingTest:^BOOL(id obj, NSUInteger, BOOL *) {
        return [predicate evaluateWithObject:obj];
    }];
}

- (NSArray *)objectsAtIndexes:(NSIndexSet *)indexes {
    if (!_backingArray) {
        _backingArray = [NSMutableArray new];
    }
    return [_backingArray objectsAtIndexes:indexes];
}

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context {
    RLMValidateArrayObservationKey(keyPath, self);
    [super addObserver:observer forKeyPath:keyPath options:options context:context];
}

//
// Methods unsupported on standalone RLMArray instances
//

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"

- (RLMResults *)objectsWithPredicate:(NSPredicate *)predicate
{
    @throw RLMException(@"This method can only be called on RLMArray instances retrieved from an RLMRealm");
}

- (RLMResults *)sortedResultsUsingProperty:(NSString *)property ascending:(BOOL)ascending
{
    return [self sortedResultsUsingDescriptors:@[[RLMSortDescriptor sortDescriptorWithProperty:property ascending:ascending]]];
}

- (RLMResults *)sortedResultsUsingDescriptors:(NSArray *)properties
{
    @throw RLMException(@"This method can only be called on RLMArray instances retrieved from an RLMRealm");
}

#pragma GCC diagnostic pop

- (NSUInteger)indexOfObjectWhere:(NSString *)predicateFormat, ...
{
    va_list args;
    RLM_VARARG(predicateFormat, args);
    return [self indexOfObjectWhere:predicateFormat args:args];
}

- (NSUInteger)indexOfObjectWhere:(NSString *)predicateFormat args:(va_list)args
{
    return [self indexOfObjectWithPredicate:[NSPredicate predicateWithFormat:predicateFormat
                                                                   arguments:args]];
}

#pragma mark - Superclass Overrides

- (NSString *)description
{
    return [self descriptionWithMaxDepth:RLMDescriptionMaxDepth];
}

- (NSString *)descriptionWithMaxDepth:(NSUInteger)depth {
    if (depth == 0) {
        return @"<Maximum depth exceeded>";
    }

    const NSUInteger maxObjects = 100;
    NSMutableString *mString = [NSMutableString stringWithFormat:@"RLMArray <%p> (\n", self];
    unsigned long index = 0, skipped = 0;
    for (id obj in self) {
        NSString *sub;
        if ([obj respondsToSelector:@selector(descriptionWithMaxDepth:)]) {
            sub = [obj descriptionWithMaxDepth:depth - 1];
        }
        else {
            sub = [obj description];
        }

        // Indent child objects
        NSString *objDescription = [sub stringByReplacingOccurrencesOfString:@"\n" withString:@"\n\t"];
        [mString appendFormat:@"\t[%lu] %@,\n", index++, objDescription];
        if (index >= maxObjects) {
            skipped = self.count - maxObjects;
            break;
        }
    }
    
    // Remove last comma and newline characters
    if(self.count > 0)
        [mString deleteCharactersInRange:NSMakeRange(mString.length-2, 2)];
    if (skipped) {
        [mString appendFormat:@"\n\t... %lu objects skipped.", skipped];
    }
    [mString appendFormat:@"\n)"];
    return [NSString stringWithString:mString];
}

@end

@interface RLMSortDescriptor ()
@property (nonatomic, strong) NSString *property;
@property (nonatomic, assign) BOOL ascending;
@end

@implementation RLMSortDescriptor
+ (instancetype)sortDescriptorWithProperty:(NSString *)propertyName ascending:(BOOL)ascending {
    RLMSortDescriptor *desc = [[RLMSortDescriptor alloc] init];
    desc->_property = propertyName;
    desc->_ascending = ascending;
    return desc;
}

- (instancetype)reversedSortDescriptor {
    return [self.class sortDescriptorWithProperty:_property ascending:!_ascending];
}

@end

//
// RLMCArrayHolder implementation
//
@implementation RLMCArrayHolder
- (instancetype)initWithSize:(NSUInteger)arraySize {
    if ((self = [super init])) {
        size = arraySize;
        array = std::make_unique<id[]>(size);
    }
    return self;
}

- (void)resize:(NSUInteger)newSize {
    if (newSize != size) {
        size = newSize;
        array = std::make_unique<id[]>(size);
    }
}
@end
