obj-c-partition-2d
==================

Two-dimensional space partitioning of Objective C objects allowing fast retrieval in rectangle or circle.
Requires Automatic Reference Counting (ARC), is helped by Key-Value Observing (KVO) and is MIT licensed.

```
// you specify how CGPoint is taken from objects when SpacePartitioning is created.
SpacePartitioning* space = [SpacePartitioning spacePartitioningWithKeyPath:@"center"
                                                            observeChanges:YES];
                                                            
// Objects added are retained by SpacePartitioning and will update their position
// if objects emit Key-Value Observing (KVO) change notifications.
[space addObject: view1];
[space addObject: view2];

// enumerate objects in circle (rectangle is also possible)
[space enumerateWithinRadius:10 fromPoint:CGPointMake(100,100)
                     toBlock:^(UIView* view) {
                        NSLog(@"%@ has center = %@", view, NSStringFromCGPoint(view.center));
                        return YES; // keep on enumerating
                     }];
  
// sometimes we need to remove objects from partitioning 
[space removeObject: view1];
```
