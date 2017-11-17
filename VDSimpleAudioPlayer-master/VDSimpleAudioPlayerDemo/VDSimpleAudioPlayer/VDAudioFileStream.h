//
//  VDAudioFileStream.h
//  VDAudioFileStream
//
//  Created by VD on 14-7-12.
//  Copyright (c) 2014年 VD. All rights reserved.
//  https://github.com/msching/VDAudioFileStream

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "VDParsedAudioData.h"

@class VDAudioFileStream;
@protocol VDAudioFileStreamDelegate <NSObject>
@required
- (void)audioFileStream:(VDAudioFileStream *)audioFileStream audioDataParsed:(NSArray *)audioData;
@optional
- (void)audioFileStreamReadyToProducePackets:(VDAudioFileStream *)audioFileStream;
@end

@interface VDAudioFileStream : NSObject

@property (nonatomic,assign,readonly) AudioFileTypeID fileType;
@property (nonatomic,assign,readonly) BOOL available;
@property (nonatomic,assign,readonly) BOOL readyToProducePackets;
@property (nonatomic,weak) id<VDAudioFileStreamDelegate> delegate;

@property (nonatomic,assign,readonly) AudioStreamBasicDescription format;
@property (nonatomic,assign,readonly) unsigned long long fileSize;
@property (nonatomic,assign,readonly) NSTimeInterval duration;
@property (nonatomic,assign,readonly) UInt32 bitRate;
@property (nonatomic,assign,readonly) UInt32 maxPacketSize;
@property (nonatomic,assign,readonly) UInt64 audioDataByteCount;

- (instancetype)initWithFileType:(AudioFileTypeID)fileType fileSize:(unsigned long long)fileSize error:(NSError **)error;

- (BOOL)parseData:(NSData *)data error:(NSError **)error;

/**
 *  seek to timeinterval
 *
 *  @param time On input, timeinterval to seek.
                On output, fixed timeinterval.
 *
 *  @return seek byte offset
 */
- (SInt64)seekToTime:(NSTimeInterval *)time;

- (NSData *)fetchMagicCookie;

- (void)close;
@end
