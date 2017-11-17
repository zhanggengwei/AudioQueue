//
//  NSTimer+BlocksSupport.h
//  VDSimpleAudioPlayerDemo
//
//  Created by VD on 15-3-13.
//  Copyright (c) 2015年 Netease. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSTimer (BlocksSupport)
+ (NSTimer*)bs_scheduledTimerWithTimeInterval:(NSTimeInterval)interval block:(void(^)())block repeats:(BOOL)repeats;
@end
