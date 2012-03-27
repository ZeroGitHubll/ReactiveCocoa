//
//  RACSubscribable+Operations.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/15/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "RACSubscribable+Operations.h"
#import "RACSubscriber.h"
#import "RACSubject.h"
#import "NSObject+GHExtensions.h"
#import "RACBehaviorSubject.h"
#import "RACDisposable.h"
#import "EXTNil.h"
#import "RACUnit.h"

#define RACCreateWeakSelf __block __unsafe_unretained id weakSelf = self;
#define RACRedefineSelf id self = weakSelf;


@implementation RACSubscribable (Operations)

- (instancetype)select:(id (^)(id x))selectBlock {
	NSParameterAssert(selectBlock != NULL);
	
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> observer) {
		RACRedefineSelf
		return [self subscribeNext:^(id x) {
			[observer sendNext:selectBlock(x)];
		} error:^(NSError *error) {
			[observer sendError:error];
		} completed:^{
			[observer sendCompleted];
		}];
	}];
}

- (instancetype)where:(BOOL (^)(id x))whereBlock {
	NSParameterAssert(whereBlock != NULL);
	
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> observer) {
		RACRedefineSelf
		return [self subscribeNext:^(id x) {
			if(whereBlock(x)) {
				[observer sendNext:x];
			}
		} error:^(NSError *error) {
			[observer sendError:error];
		} completed:^{
			[observer sendCompleted];
		}];
	}];
}

- (instancetype)do:(void (^)(id x))block {
	NSParameterAssert(block != NULL);

	[self subscribeNext:block];
	return self;
}

- (instancetype)throttle:(NSTimeInterval)interval {	
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> observer) {
		RACRedefineSelf
		__block id lastDelayedId = nil;
		return [self subscribeNext:^(id x) {
			lastDelayedId = [self performBlock:^{
				[observer sendNext:x];
			} afterDelay:interval];
		} error:^(NSError *error) {
			[self cancelPreviousPerformBlockRequestsWithId:lastDelayedId];
			[observer sendError:error];
		} completed:^{
			[observer sendCompleted];
		}];
	}];
}

- (instancetype)repeat {
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> observer) {
		RACRedefineSelf
		__block RACSubscriber *innerObserver = [RACSubscriber subscriberWithNext:^(id x) {
			[observer sendNext:x];
		} error:^(NSError *error) {
			[observer sendError:error];
		} completed:^{
			[self subscribe:innerObserver];
		}];
		
		return [self subscribe:innerObserver];
	}];
}

- (instancetype)defer {
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> observer) {
		RACRedefineSelf
		__block RACSubscriber *innerObserver = [RACSubscriber subscriberWithNext:^(id x) {
			[observer sendNext:x];
		} error:^(NSError *error) {
			[self subscribe:innerObserver];
		} completed:^{
			[observer sendCompleted];
		}];
		
		return [self subscribe:innerObserver];
	}];
}

- (instancetype)finally:(void (^)(void))block {
	NSParameterAssert(block != NULL);
	
	[self subscribeNext:^(id _) {
		
	} error:^(NSError *error) {
		block();
	} completed:^{
		block();
	}];
	
	return self;
}

- (instancetype)windowWithStart:(id<RACSubscribable>)openObservable close:(id<RACSubscribable> (^)(id<RACSubscribable> start))closeBlock {
	NSParameterAssert(openObservable != nil);
	NSParameterAssert(closeBlock != NULL);
	
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> observer) {
		RACRedefineSelf
				
		__block RACSubject *currentWindow = nil;
		__block id<RACSubscribable> currentCloseWindow = nil;
		__block RACDisposable *closeObserverDisposable = NULL;
		
		void (^closeCurrentWindow)(void) = ^{
			[currentWindow sendCompleted];
			currentWindow = nil;
			currentCloseWindow = nil;
			[closeObserverDisposable dispose], closeObserverDisposable = nil;
		};
		
		RACDisposable *openObserverDisposable = [openObservable subscribe:[RACSubscriber subscriberWithNext:^(id x) {
			if(currentWindow == nil) {
				currentWindow = [RACSubject subject];
				[observer sendNext:currentWindow];
				
				currentCloseWindow = closeBlock(currentWindow);
				closeObserverDisposable = [currentCloseWindow subscribe:[RACSubscriber subscriberWithNext:^(id x) {
					closeCurrentWindow();
				} error:^(NSError *error) {
					closeCurrentWindow();
				} completed:^{
					closeCurrentWindow();
				}]];
			}
		} error:^(NSError *error) {
			
		} completed:^{
			
		}]];
				
		RACDisposable *selfObserverDisposable = [self subscribeNext:^(id x) {
			[currentWindow sendNext:x];
		} error:^(NSError *error) {
			[observer sendError:error];
		} completed:^{
			[observer sendCompleted];
		}];
				
		return [RACDisposable disposableWithBlock:^{
			[closeObserverDisposable dispose];
			[openObserverDisposable dispose];
			[selfObserverDisposable dispose];
		}];
	}];
}

- (instancetype)buffer:(NSUInteger)bufferCount {
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> observer) {
		RACRedefineSelf
		RACBehaviorSubject *windowOpenSubject = [RACBehaviorSubject behaviorSubjectWithDefaultValue:@""];
		RACSubject *windowCloseSubject = [RACSubject subject];
		
		__block NSUInteger valuesReceived = 0;
		return [[self windowWithStart:windowOpenSubject close:^(id<RACSubscribable> start) {
			return windowCloseSubject;
		}] subscribeNext:^(id x) {		
			[x subscribeNext:^(id x) {
				valuesReceived++;
				if(valuesReceived % bufferCount == 0) {
					[windowCloseSubject sendNext:x];
					[windowOpenSubject sendNext:@""];
				}
			} error:^(NSError *error) {
				
			} completed:^{
				
			}];
		} error:^(NSError *error) {
			
		} completed:^{
			
		}];
	}];
}

- (instancetype)take:(NSUInteger)count {
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> observer) {
		RACRedefineSelf
		
		__block NSUInteger valuesTaken = 0;
		return [self subscribeNext:^(id x) {
			valuesTaken++;
			[observer sendNext:x];
			
			if(valuesTaken >= count) {
				[observer sendCompleted];
			}
		} error:^(NSError *error) {
			[observer sendError:error];
		} completed:^{
			[observer sendCompleted];
		}];
	}];
}

+ (instancetype)combineLatest:(NSArray *)observables reduce:(id (^)(NSArray *xs))reduceBlock {
	NSParameterAssert(reduceBlock != NULL);
	
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> observer) {
		NSMutableSet *disposables = [NSMutableSet setWithCapacity:observables.count];
		NSMutableSet *completedObservables = [NSMutableSet setWithCapacity:observables.count];
		NSMutableDictionary *lastValues = [NSMutableDictionary dictionaryWithCapacity:observables.count];
		for(id<RACSubscribable> observable in observables) {
			RACDisposable *disposable = [observable subscribe:[RACSubscriber subscriberWithNext:^(id x) {
				[lastValues setObject:x ? : [EXTNil null] forKey:[NSString stringWithFormat:@"%p", observable]];
				
				if(lastValues.count == observables.count) {
					NSMutableArray *orderedValues = [NSMutableArray arrayWithCapacity:observables.count];
					for(id<RACSubscribable> o in observables) {
						[orderedValues addObject:[lastValues objectForKey:[NSString stringWithFormat:@"%p", o]]];
					}
					
					[observer sendNext:reduceBlock(orderedValues)];
				}
			} error:^(NSError *error) {
				[observer sendError:error];
			} completed:^{
				[completedObservables addObject:observable];
				if(completedObservables.count == observables.count) {
					[observer sendCompleted];
				}
			}]];
			
			[disposables addObject:disposable];
		}
		
		return [RACDisposable disposableWithBlock:^{
			for(RACDisposable *disposable in disposables) {
				[disposable dispose];
			}
		}];
	}];
}

+ (instancetype)merge:(NSArray *)observables {
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> observer) {
		NSMutableSet *disposables = [NSMutableSet setWithCapacity:observables.count];
		NSMutableSet *completedObservables = [NSMutableSet setWithCapacity:observables.count];
		for(id<RACSubscribable> observable in observables) {
			RACDisposable *disposable = [observable subscribe:[RACSubscriber subscriberWithNext:^(id x) {
				[observer sendNext:x];
			} error:^(NSError *error) {
				[observer sendError:error];
			} completed:^{
				[completedObservables addObject:observable];
				if(completedObservables.count == observables.count) {
					[observer sendCompleted];
				}
			}]];
			
			[disposables addObject:disposable];
		}
		
		return [RACDisposable disposableWithBlock:^{
			for(RACDisposable *disposable in disposables) {
				[disposable dispose];
			}
		}];
	}];
}

- (instancetype)selectMany:(id<RACSubscribable> (^)(id x))selectBlock {
	NSParameterAssert(selectBlock != NULL);
	
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> observer) {
		RACRedefineSelf
		NSMutableSet *activeObservables = [NSMutableSet set];
		[activeObservables addObject:self];
		
		NSMutableSet *completedObservables = [NSMutableSet set];
		RACDisposable *outerDisposable = [self subscribeNext:^(id x) {
			id<RACSubscribable> observable = selectBlock(x);
			[activeObservables addObject:observable];
			[observable subscribe:[RACSubscriber subscriberWithNext:^(id x) {
				[observer sendNext:x];
			} error:^(NSError *error) {
				[observer sendError:error];
			} completed:^{
				[completedObservables addObject:observable];
				
				if(completedObservables.count == activeObservables.count) {
					[observer sendCompleted];
				}
			}]];
		} error:^(NSError *error) {
			[observer sendError:error];
		} completed:^{
			[completedObservables addObject:self];
			
			if(completedObservables.count == activeObservables.count) {
				[observer sendCompleted];
			}
		}];
		
		return [RACDisposable disposableWithBlock:^{
			[outerDisposable dispose];
		}];
	}];
}

- (instancetype)concat:(id<RACSubscribable>)subscribable {
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> subscriber) {
		RACRedefineSelf
		
		__block RACDisposable *concattedDisposable = nil;
		RACDisposable *sourceDisposable = [self subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			concattedDisposable = [subscribable subscribe:[RACSubscriber subscriberWithNext:^(id x) {
				[subscriber sendNext:x];
			} error:^(NSError *error) {
				[subscriber sendError:error];
			} completed:^{
				[subscriber sendCompleted];
			}]];
		}];
		
		return [RACDisposable disposableWithBlock:^{
			[sourceDisposable dispose];
			[concattedDisposable dispose];
		}];
	}];
}

- (instancetype)scanWithStart:(NSInteger)start combine:(NSInteger (^)(NSInteger running, NSInteger next))combineBlock {
	NSParameterAssert(combineBlock != NULL);
	
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> subscriber) {
		RACRedefineSelf
		
		NSInteger runningValue = start;
		return [self subscribeNext:^(id x) {
			[subscriber sendNext:[NSNumber numberWithInteger:combineBlock(runningValue, [x integerValue])]];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}];
}

- (instancetype)toPropery:(NSString *)keyPath onObject:(NSObject *)object {
	NSParameterAssert(keyPath != nil);
	NSParameterAssert(object != nil);
	
	__block __unsafe_unretained NSObject *weakObject = object;
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> subscriber) {
		NSObject *strongObject = weakObject;
		RACRedefineSelf
		
		return [self subscribeNext:^(id x) {
			[strongObject setValue:x forKeyPath:keyPath];
		}];
	}];
}

- (instancetype)startWith:(id)initialValue {
	RACCreateWeakSelf
	return [RACSubscribable createSubscribable:^(id<RACSubscriber> subscriber) {
		RACRedefineSelf
		
		[subscriber sendNext:initialValue];
		
		return [self subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}];
}

+ (instancetype)interval:(NSTimeInterval)interval {
	return [RACSubscribable createSubscribable:^RACDisposable *(id<RACSubscriber> observer) {
		NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(intervalTimerFired:) userInfo:observer repeats:YES];
		
		return [RACDisposable disposableWithBlock:^{
			[observer sendCompleted];
			[timer invalidate];
		}];
	}];
}

+ (void)intervalTimerFired:(NSTimer *)timer {
	id<RACSubscriber> observer = [timer userInfo];
	[observer sendNext:[RACUnit defaultUnit]];
}

@end
