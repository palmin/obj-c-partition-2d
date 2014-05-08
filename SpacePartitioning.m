//
//  SpacePartitioning.m
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

#import <assert.h>
#import "SpacePartitioning.h"

#if !__has_feature(objc_arc)
# error SoapSerialization requires ARC (Automatic Reference Counting)
#endif

@class SpacePartitioningNode;
@interface SpacePartitioning ()  {
    struct SpacePartitioningNode* root;
    
    // key is NSNumber with pointer to object, which makes it fast
    // to lookup object by reference
    NSMutableDictionary* pointFromPointer; // value is NSValue with CGPoint
    NSMutableDictionary* objectFromPointer; // value is object added
    
    NSString* keyPath;
    BOOL observeChanges;
}

@end

#define ObjectsPerLeaf 8

struct SpacePartitioningNode {
    CGPoint upperLeft, lowerRight;
    
    // node is branch if one and other are non-NULL, and either both are NULL or none are
    struct SpacePartitioningNode* one;
    struct SpacePartitioningNode* other;
    
    size_t count; // for leafs this is number of objects, for branches this is total count of children
    void* objects[ObjectsPerLeaf];
    CGPoint points[ObjectsPerLeaf];
};

static struct SpacePartitioningNode* createNode(CGPoint upperLeft, CGPoint lowerRight) {
    struct SpacePartitioningNode* node = calloc(1, sizeof(struct SpacePartitioningNode));
    node->upperLeft = upperLeft;
    node->lowerRight = lowerRight;
    return node;
}

// we assume node is not NULL
static void destroyNode(struct SpacePartitioningNode* node) {
    assert(node != NULL);
    if(node->one) {
        destroyNode(node->one);
        destroyNode(node->other);
    }
    free(node);
}

static inline bool nodeIsLeaf(struct SpacePartitioningNode* node) {
    return node->one == NULL;
}

static inline bool pointBetween(CGPoint upperLeft, CGPoint point, CGPoint lowerRight) {
    return upperLeft.x <= point.x && upperLeft.y <= point.y &&
           point.x <= lowerRight.x && point.y <= lowerRight.y;
}

static inline bool rectOverlaps(CGPoint upperLeft, CGRect rect, CGPoint lowerRight) {
    if(rect.origin.x > lowerRight.x) return false;
    if(rect.origin.y > lowerRight.y) return false;
    if(CGRectGetMaxX(rect) < upperLeft.x) return false;
    if(CGRectGetMaxY(rect) < upperLeft.y) return false;
    return true;
}

#ifdef DEBUG
static inline void assertSanity(struct SpacePartitioningNode* node) {
    assert(node != NULL);
    assert((node->count <= ObjectsPerLeaf) == nodeIsLeaf(node)); // leaves and only leaves have <= ObjectsPerLeaf children
    assert(nodeIsLeaf(node) || node->count == node->one->count + node->other->count); // branches must have sum of children nodes
    
    if(nodeIsLeaf(node)) {
        for(size_t k = 0; k < node->count; ++k) {
            assert(pointBetween(node->upperLeft, node->points[k], node->lowerRight)); // points must be inside bounds
            assert(node->objects[k] != NULL); // we do not allow NULL objects
        }
    } else {
        assertSanity(node->one);
        assertSanity(node->other);
    }
}
#else
static inline void assertSanity(struct SpacePartitioningNode* node) {}
#endif

static void addToNode(struct SpacePartitioningNode* node, CGPoint point, void* object);

// we convert leaf node to branch node, distributing objects as evenly as possible,
// assuming node is not NULL and is not already branch and that left has at least
// one object.
static void convertNodeToBranch(struct SpacePartitioningNode* node) {
    assert(node != NULL && node->one == NULL && node->count >= 1);

    int k, count = (int)node->count;
    CGFloat minX, maxX, minY, maxY;
    minX = maxX = node->points[0].x;
    minY = maxY = node->points[0].y;
    assert(node->objects[0] != NULL);
    for(k = 1; k < count; ++k) {
        assert(node->objects[k] != NULL);
        CGPoint pt = node->points[k];
        minX = fmin(minX, pt.x);
        maxX = fmax(maxX, pt.x);
        minY = fmin(minY, pt.y);
        maxY = fmax(maxY, pt.y);
    }

    // we partition to half the larger of the two axis
    CGFloat wid = maxX - minX, hei = maxY - minY;
    if(wid >= hei) {
        // split horizontally
        CGFloat midX = 0.5 * minX + 0.5 * maxX;
        node->one = createNode(node->upperLeft, CGPointMake(midX, node->lowerRight.y));
        node->other = createNode(CGPointMake(midX, node->upperLeft.y), node->lowerRight);
    } else {
        // split vertically
        CGFloat midY = 0.5 * minY + 0.5 * maxY;
        node->one = createNode(node->upperLeft, CGPointMake(node->lowerRight.x, midY));
        node->other = createNode(CGPointMake(node->upperLeft.x, midY), node->lowerRight);
    }
    
    // add elements to child nodes
    node->count = 0;
    for(k = 0; k < count; ++k) {
        addToNode(node, node->points[k], node->objects[k]);
    }
}

// we assume node is not NULL, point is inside node->bounds and object is not NULL
static void addToNode(struct SpacePartitioningNode* node, CGPoint point, void* object) {
    assert(node != NULL && pointBetween(node->upperLeft, point, node->lowerRight) && object != NULL);

    if(nodeIsLeaf(node)) {
        // we have leaf with additional space and we just add object here
        if(node->count < ObjectsPerLeaf) {
            node->objects[node->count] = object;
            node->points[node->count] = point;
            node->count += 1;
            return;
        }
        
        convertNodeToBranch(node);
    }
    
    // this is branch and we choose the one where bounds contain point, which can be both
    // and then we take the with the fewest count to keep tree balanced
    struct SpacePartitioningNode* smaller;
    struct SpacePartitioningNode* larger;
    if(node->one->count <= node->other->count) {
        smaller = node->one;
        larger = node->other;
    } else {
        smaller = node->other;
        larger = node->one;
    }
    
    if(pointBetween(smaller->upperLeft, point, smaller->lowerRight)) {
        addToNode(smaller, point, object);
    } else {
        assert(pointBetween(larger->upperLeft, point, larger->lowerRight));
        addToNode(larger, point, object);
    }
    node->count += 1;
}

// we assume node is not NULL, point is inside node->bounds and object is not NULL,
// and return whether object was deleted
static bool removeFromNode(struct SpacePartitioningNode* node, CGPoint point, void* object) {
    assert(node != NULL && pointBetween(node->upperLeft, point, node->lowerRight) && object != NULL);

    if(nodeIsLeaf(node)) {
        // we have leaf then  object must be one of these
        int count = (int)node->count;
        for(int k = 0; k < count; ++k) {
            if(node->objects[k] == object) {
                // we found object and must shift down all later objects
                for(int j = k; j + 1 < count; ++j) {
                    node->objects[j] = node->objects[j+1];
                    node->points[j] = node->points[j+1];
                }
                
                node->count -= 1;
                return true;
            }
        }
        
        return false;
    }
    
    // this is branch and we delete from each child
    bool deleted = false;
    if(pointBetween(node->one->upperLeft, point, node->one->lowerRight)) {
        deleted = removeFromNode(node->one, point, object);
    }
    if(!deleted && pointBetween(node->other->upperLeft, point, node->other->lowerRight)) {
        deleted = removeFromNode(node->other, point, object);
    }
    
    // if deleted we adjust count and perhaps convert back to leaf
    if(deleted) {
        node->count -= 1;
        
        // collapse branches to leaf
        if(node->count <= ObjectsPerLeaf) {
            // we assume that children are leafs
            assert(nodeIsLeaf(node->one) && nodeIsLeaf(node->other));
            
            int k, count1 = (int)node->one->count, count2 = (int)node->other->count;
            for(k = 0; k < count1; ++k) {
                node->points[k] = node->one->points[k];
                node->objects[k] = node->one->objects[k];
            }
            for(k = 0; k < count2; ++k) {
                node->points[count1+k] = node->other->points[k];
                node->objects[count1+k] = node->other->objects[k];
            }
            
            destroyNode(node->one); node->one = NULL;
            destroyNode(node->other); node->other = NULL;
        }
    }
    
    return deleted;
}

// iterate through objects in node inside rectangle, assuming node and callback is not NULL.
// Iteration ends when callback block returns false, where this function
// returns false if any callback returned false.
static bool visitNodeObjectsInRect(struct SpacePartitioningNode* node, CGRect rectangle,
                                   bool (^callback)(CGPoint point, void* object)) {
    assert(node != NULL);
    
    if(nodeIsLeaf(node)) {
        int count = (int)node->count;
        for(int k = 0; k < count; ++k) {
            if(!CGRectContainsPoint(rectangle, node->points[k])) continue;
            
            bool goOn = callback(node->points[k], node->objects[k]);
            if(!goOn) return false;
        }
        
    } else {
        if(rectOverlaps(node->one->upperLeft, rectangle, node->one->lowerRight)) {
            bool goOn = visitNodeObjectsInRect(node->one, rectangle, callback);
            if(!goOn) return false;
        }

        if(rectOverlaps(node->other->upperLeft, rectangle, node->other->lowerRight)) {
            bool goOn = visitNodeObjectsInRect(node->other, rectangle, callback);
            if(!goOn) return false;
        }
        
    }
    return true;
}

@implementation SpacePartitioning

-(id)init {
    const CGFloat max = CGFLOAT_MAX;
    self = [super init];
    if(self) {
        root = createNode(CGPointMake(-max, -max), CGPointMake(max, max));
        pointFromPointer = [NSMutableDictionary new];
        objectFromPointer = [NSMutableDictionary new];
    }
    return self;
}

+(SpacePartitioning*)spacePartitioningWithKeyPath:(NSString*)keyPath
                                   observeChanges:(BOOL)observeChanges {
    SpacePartitioning* partitioning = [SpacePartitioning new];
    if(partitioning) {
        partitioning->keyPath = keyPath;
        partitioning->observeChanges = observeChanges;
    }
    return partitioning;
}

-(void)dealloc {
    // we remove objects to make sure there are no KVO observers
    for (id object in [objectFromPointer allValues]) {
        [self removeObject:object];
    }
    
    destroyNode(root);
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    [self addObject:object];
}

-(void)addObject:(id)object {
    CGPoint point;
    NSValue* value = [object valueForKeyPath:keyPath];
    [value getValue:&point];

    // make sure object is not represented multiple times
    NSValue* key = [NSValue valueWithPointer:(void*)object];
    NSValue* oldPoint = [pointFromPointer objectForKey:key];
    if(oldPoint) {
        // if we know about object and point has not even changed we do nothing
        if(CGPointEqualToPoint(point, oldPoint.CGPointValue)) return;
        
        // remove object but continue adding it again to update partitioning
        removeFromNode(root, oldPoint.CGPointValue, (__bridge void*)object);
        assertSanity(root);
    } else if(observeChanges) {
        [object addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:NULL];
    }
    
    // add to dictionaries
    [pointFromPointer setObject:[NSValue valueWithCGPoint:point] forKey:key];
    [objectFromPointer setObject:object forKey:key];
    
    // add to space partitioning
    addToNode(root, point, (__bridge void*)object);
    assertSanity(root);
}

-(BOOL)removeObject:(id)object {
    NSValue* key = [NSValue valueWithPointer:(void*)object];
    NSValue* point = [pointFromPointer objectForKey:key];
    if(point) {
        if(observeChanges) {
            [object removeObserver:self forKeyPath:keyPath];
        }
        removeFromNode(root, point.CGPointValue, (__bridge void *)(object));
        assertSanity(root);
    }
    [pointFromPointer removeObjectForKey:key];
    [objectFromPointer removeObjectForKey:key];
    
    return point != nil;
}

-(void)enumerateInsideRectangle:(CGRect)rectangle
                        toBlock:(BOOL (^)(id object))block {
    visitNodeObjectsInRect(root, rectangle, ^bool(CGPoint point, void* object) {
        return block((__bridge id)object);
    });
}

-(void)enumerateWithinRadius:(CGFloat)radius fromPoint:(CGPoint)center
                     toBlock:(BOOL (^)(id object))block {
    CGRect rectangle = CGRectMake(center.x - radius, center.y - radius, 2.0 * radius, 2.0 * radius);
    CGFloat sqrRadius = radius * radius;
    
    visitNodeObjectsInRect(root, rectangle, ^bool(CGPoint point, void* object) {
        // continue iteration without calling block if too far from center of circle
        CGFloat dx = center.x - point.x, dy = center.y - point.y;
        CGFloat sqrdist = dx*dx + dy*dy;
        if(sqrdist >= sqrRadius) return YES;
        
        return block((__bridge id)object);
    });
}

@end

