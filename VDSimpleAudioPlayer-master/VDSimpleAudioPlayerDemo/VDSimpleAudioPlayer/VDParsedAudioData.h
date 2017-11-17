//
//  VDParsedAudioData.h
//  VDAudioFileStream
//
//  Created by VD on 14-7-12.
//  Copyright (c) 2014年 VD. All rights reserved.
//  https://github.com/msching/VDAudioFileStream

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudioTypes.h>

@interface VDParsedAudioData : NSObject

@property (nonatomic,readonly) NSData *data;
@property (nonatomic,readonly) AudioStreamPacketDescription packetDescription;

+ (instancetype)parsedAudioDataWithBytes:(const void *)bytes
                       packetDescription:(AudioStreamPacketDescription)packetDescription;
@end
