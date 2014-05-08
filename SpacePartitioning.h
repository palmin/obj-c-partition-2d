//
//  SpacePartitioning.h
//
//    Two-dimensional space partitioning of objects allowing fast retrieval
//    of objects in some rectangle or circle.
//
//    Container is not thread safe. Access should be restricted to only one
//    thread at a time. Automatic Reference Counting (ARC) required.
//
// Copyright (c) 2014 Anders Borum
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <Foundation/Foundation.h>

@interface SpacePartitioning : NSObject

// Objects added will be partitioned according to property with given
// keyPath which must return CGPoint. For UIView objects @"center" or @"frame.origin"
// could be useful. If partitioning observes changes and the objects support
// KVO notifications object placement in SpacePartitioning is automatically
// updated. Otherwise addObject: must be called to update placement.
+(SpacePartitioning*)spacePartitioningWithKeyPath:(NSString*)keyPath
                                   observeChanges:(BOOL)observeChanges;

// addObject can also be called for existing object to update its position
-(void)addObject:(id)object;

// returns whether object existed or not.
-(BOOL)removeObject:(id)object;

// present all objects in container in given rectangle, with no specific ordering.
// block should return YES to keep enumerating and NO to stop.
-(void)enumerateInsideRectangle:(CGRect)rectangle
                        toBlock:(BOOL (^)(id object))block;

// present all objects in container in given circle, with no specific ordering.
// block should return YES to keep enumerating and NO to stop.
-(void)enumerateWithinRadius:(CGFloat)radius fromPoint:(CGPoint)center
                     toBlock:(BOOL (^)(id object))block;

@end
