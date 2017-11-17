//
//  VDSimpleAudioPlayer.h
//  VDSimpleAudioPlayer
//
//  Created by VD on 14-7-27.
//  Copyright (c) 2014年 VD. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioFile.h>

typedef NS_ENUM(NSUInteger, VDSAPStatus)
{
    VDSAPStatusStopped = 0,
    VDSAPStatusPlaying = 1,
    VDSAPStatusWaiting = 2,
    VDSAPStatusPaused = 3,
    VDSAPStatusFlushing = 4,
};

@interface VDSimpleAudioPlayer : NSObject

@property (nonatomic,copy,readonly) NSString *filePath;
@property (nonatomic,assign,readonly) AudioFileTypeID fileType;

@property (nonatomic,readonly) VDSAPStatus status;
@property (nonatomic,readonly) BOOL isPlayingOrWaiting;
@property (nonatomic,assign,readonly) BOOL failed;

@property (nonatomic,assign) NSTimeInterval progress;
@property (nonatomic,readonly) NSTimeInterval duration;

- (instancetype)initWithFilePath:(NSString *)filePath fileType:(AudioFileTypeID)fileType;

- (void)play;
- (void)pause;
- (void)stop;
@end
