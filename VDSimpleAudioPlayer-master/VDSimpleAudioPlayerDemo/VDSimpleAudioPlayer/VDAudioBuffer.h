//
//  VDAudioBuffer.h
//  VDSimpleAudioPlayer
//
//  Created by VD on 14-7-28.
//  Copyright (c) 2014年 VD. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>
#import "VDParsedAudioData.h"

@interface VDAudioBuffer : NSObject

+ (instancetype)buffer;

- (void)enqueueData:(VDParsedAudioData *)data;
- (void)enqueueFromDataArray:(NSArray *)dataArray;

- (BOOL)hasData;
- (UInt32)bufferedSize;

//descriptions needs free
- (NSData *)dequeueDataWithSize:(UInt32)requestSize packetCount:(UInt32 *)packetCount descriptions:(AudioStreamPacketDescription **)descriptions;

- (void)clean;
@end
