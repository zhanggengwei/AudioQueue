//
//  VDSimpleAudioPlayer.m
//  VDSimpleAudioPlayer
//
//  Created by VD on 14-7-27.
//  Copyright (c) 2014年 VD. All rights reserved.
//

#import "VDSimpleAudioPlayer.h"
#import "VDAudioSession.h"
#import "VDAudioFile.h"
#import "VDAudioFileStream.h"
#import "VDAudioOutputQueue.h"
#import "VDAudioBuffer.h"
#import <pthread.h>

@interface VDSimpleAudioPlayer ()<VDAudioFileStreamDelegate>
{
@private
    NSThread *_thread;
    pthread_mutex_t _mutex;
	pthread_cond_t _cond;
    
    VDSAPStatus _status;
    
    unsigned long long _fileSize;
    unsigned long long _offset;
    NSFileHandle *_fileHandler;
    
    UInt32 _bufferSize;
    VDAudioBuffer *_buffer;
    
    VDAudioFile *_audioFile;
    VDAudioFileStream *_audioFileStream;
    VDAudioOutputQueue *_audioQueue;
    
    BOOL _started;
    BOOL _pauseRequired;
    BOOL _stopRequired;
    BOOL _pausedByInterrupt;
    BOOL _usingAudioFile;
    
    BOOL _seekRequired;
    NSTimeInterval _seekTime;
    NSTimeInterval _timingOffset;
}
@end

@implementation VDSimpleAudioPlayer
@dynamic status;
@synthesize failed = _failed;
@synthesize fileType = _fileType;
@synthesize filePath = _filePath;
@dynamic isPlayingOrWaiting;
@dynamic duration;
@dynamic progress;

#pragma mark - init & dealloc
- (instancetype)initWithFilePath:(NSString *)filePath fileType:(AudioFileTypeID)fileType
{
    self = [super init];
    if (self)
    {
        _status = VDSAPStatusStopped;
        
        _filePath = filePath;
        _fileType = fileType;
        
        _fileHandler = [NSFileHandle fileHandleForReadingAtPath:_filePath];
        _fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:_filePath error:nil] fileSize];
        if (_fileHandler && _fileSize > 0)
        {
            _buffer = [VDAudioBuffer buffer];
        }
        else
        {
            [_fileHandler closeFile];
            _failed = YES;
        }
    }
    return self;
}

- (void)dealloc
{
    [self cleanup];
    [_fileHandler closeFile];
}

- (void)cleanup
{
    //reset file
    _offset = 0;
    [_fileHandler seekToFileOffset:0];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:VDAudioSessionInterruptionNotification object:nil];
    
    //clean buffer
    [_buffer clean];
    
    _usingAudioFile = NO;
    //close audioFileStream
    [_audioFileStream close];
    _audioFileStream = nil;
    
    //close audiofile
    [_audioFile close];
    _audioFile = nil;
    
    //stop audioQueue
    [_audioQueue stop:YES];
    _audioQueue = nil;
    
    //destory mutex & cond
    [self _mutexDestory];
    
    _started = NO;
    _timingOffset = 0;
    _seekTime = 0;
    _seekRequired = NO;
    _pauseRequired = NO;
    _stopRequired = NO;
    
    //reset status
    [self setStatusInternal:VDSAPStatusStopped];
}

#pragma mark - status
- (BOOL)isPlayingOrWaiting
{
    return self.status == VDSAPStatusWaiting || self.status == VDSAPStatusPlaying || self.status == VDSAPStatusFlushing;
}

- (VDSAPStatus)status
{
    return _status;
}

- (void)setStatusInternal:(VDSAPStatus)status
{
    if (_status == status)
    {
        return;
    }
    
    [self willChangeValueForKey:@"status"];
    _status = status;
    [self didChangeValueForKey:@"status"];
}

#pragma mark - mutex
- (void)_mutexInit
{
    pthread_mutex_init(&_mutex, NULL);
    pthread_cond_init(&_cond, NULL);
}

- (void)_mutexDestory
{
    pthread_mutex_destroy(&_mutex);
    pthread_cond_destroy(&_cond);
}

- (void)_mutexWait
{
    pthread_mutex_lock(&_mutex);
    pthread_cond_wait(&_cond, &_mutex);
	pthread_mutex_unlock(&_mutex);
}

- (void)_mutexSignal
{
    pthread_mutex_lock(&_mutex);
    pthread_cond_signal(&_cond);
    pthread_mutex_unlock(&_mutex);
}

#pragma mark - thread
- (BOOL)createAudioQueue
{
    if (_audioQueue)
    {
        return YES;
    }
    
    NSTimeInterval duration = self.duration;
    UInt64 audioDataByteCount = _usingAudioFile ? _audioFile.audioDataByteCount : _audioFileStream.audioDataByteCount;
    _bufferSize = 0;
    if (duration != 0)
    {
        _bufferSize = (0.2 / duration) * audioDataByteCount;
    }
    
    if (_bufferSize > 0)
    {
        AudioStreamBasicDescription format = _usingAudioFile ? _audioFile.format : _audioFileStream.format;
        NSData *magicCookie = _usingAudioFile ? [_audioFile fetchMagicCookie] : [_audioFileStream fetchMagicCookie];
        _audioQueue = [[VDAudioOutputQueue alloc] initWithFormat:format bufferSize:_bufferSize macgicCookie:magicCookie];
        if (!_audioQueue.available)
        {
            _audioQueue = nil;
            return NO;
        }
    }
    return YES;
}

- (void)threadMain
{
    _failed = YES;
    NSError *error = nil;
    //set audiosession category
    if ([[VDAudioSession sharedInstance] setCategory:kAudioSessionCategory_MediaPlayback error:NULL])
    {
        //active audiosession
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(interruptHandler:) name:VDAudioSessionInterruptionNotification object:nil];
        if ([[VDAudioSession sharedInstance] setActive:YES error:NULL])
        {
            //create audioFileStream
            _audioFileStream = [[VDAudioFileStream alloc] initWithFileType:_fileType fileSize:_fileSize error:&error];
            if (!error)
            {
                _failed = NO;
                _audioFileStream.delegate = self;
            }
        }
    }
    
    if (_failed)
    {
        [self cleanup];
        return;
    }
    
    [self setStatusInternal:VDSAPStatusWaiting];
    BOOL isEof = NO;
    while (self.status != VDSAPStatusStopped && !_failed && _started)
    {
        @autoreleasepool
        {
            //read file & parse
            if (_usingAudioFile)
            {
                if (!_audioFile)
                {
                    _audioFile = [[VDAudioFile alloc] initWithFilePath:_filePath fileType:_fileType];
                }
                [_audioFile seekToTime:_seekTime];
                if ([_buffer bufferedSize] < _bufferSize || !_audioQueue)
                {
                    NSArray *parsedData = [_audioFile parseData:&isEof];
                    if (parsedData)
                    {
                        [_buffer enqueueFromDataArray:parsedData];
                    }
                    else
                    {
                        _failed = YES;
                        break;
                    }
                }
            }
            else
            {
                if (_offset < _fileSize && (!_audioFileStream.readyToProducePackets || [_buffer bufferedSize] < _bufferSize || !_audioQueue))
                {
                    NSData *data = [_fileHandler readDataOfLength:1000];
                    _offset += [data length];
                    if (_offset >= _fileSize)
                    {
                        isEof = YES;
                    }
                    [_audioFileStream parseData:data error:&error];
                    if (error)
                    {
                        _usingAudioFile = YES;
                        continue;
                    }
                }
            }
            
            
            
            if (_audioFileStream.readyToProducePackets || _usingAudioFile)
            {
                if (![self createAudioQueue])
                {
                    _failed = YES;
                    break;
                }
                
                if (!_audioQueue)
                {
                    continue;
                }
                
                if (self.status == VDSAPStatusFlushing && !_audioQueue.isRunning)
                {
                    break;
                }
                
                //stop
                if (_stopRequired)
                {
                    _stopRequired = NO;
                    _started = NO;
                    [_audioQueue stop:YES];
                    break;
                }
                
                //pause
                if (_pauseRequired)
                {
                    [self setStatusInternal:VDSAPStatusPaused];
                    [_audioQueue pause];
                    [self _mutexWait];
                    _pauseRequired = NO;
                }
                
                //play
                if ([_buffer bufferedSize] >= _bufferSize || isEof)
                {
                    UInt32 packetCount;
                    AudioStreamPacketDescription *desces = NULL;
                    NSData *data = [_buffer dequeueDataWithSize:_bufferSize packetCount:&packetCount descriptions:&desces];
                    if (packetCount != 0)
                    {
                        [self setStatusInternal:VDSAPStatusPlaying];
                        _failed = ![_audioQueue playData:data packetCount:packetCount packetDescriptions:desces isEof:isEof];
                        free(desces);
                        if (_failed)
                        {
                            break;
                        }
                        
                        if (![_buffer hasData] && isEof && _audioQueue.isRunning)
                        {
                            [_audioQueue stop:NO];
                            [self setStatusInternal:VDSAPStatusFlushing];
                        }
                    }
                    else if (isEof)
                    {
                        //wait for end
                        if (![_buffer hasData] && _audioQueue.isRunning)
                        {
                            [_audioQueue stop:NO];
                            [self setStatusInternal:VDSAPStatusFlushing];
                        }
                    }
                    else
                    {
                        _failed = YES;
                        break;
                    }
                }
                
                //seek
                if (_seekRequired && self.duration != 0)
                {
                    [self setStatusInternal:VDSAPStatusWaiting];
                    
                    _timingOffset = _seekTime - _audioQueue.playedTime;
                    [_buffer clean];
                    if (_usingAudioFile)
                    {
                        [_audioFile seekToTime:_seekTime];
                    }
                    else
                    {
                        _offset = [_audioFileStream seekToTime:&_seekTime];
                        [_fileHandler seekToFileOffset:_offset];
                    }
                    _seekRequired = NO;
                    [_audioQueue reset];
                }
            }
        }
    }
    
    //clean
    [self cleanup];
}


#pragma mark - interrupt
- (void)interruptHandler:(NSNotification *)notification
{
    UInt32 interruptionState = [notification.userInfo[VDAudioSessionInterruptionStateKey] unsignedIntValue];
    
    if (interruptionState == kAudioSessionBeginInterruption)
    {
        _pausedByInterrupt = YES;
        [_audioQueue pause];
        [self setStatusInternal:VDSAPStatusPaused];
        
    }
    else if (interruptionState == kAudioSessionEndInterruption)
    {
        AudioSessionInterruptionType interruptionType = [notification.userInfo[VDAudioSessionInterruptionTypeKey] unsignedIntValue];
        if (interruptionType == kAudioSessionInterruptionType_ShouldResume)
        {
            if (self.status == VDSAPStatusPaused && _pausedByInterrupt)
            {
                if ([[VDAudioSession sharedInstance] setActive:YES error:NULL])
                {
                    [self play];
                }
            }
        }
    }
}

#pragma mark - parser
- (void)audioFileStream:(VDAudioFileStream *)audioFileStream audioDataParsed:(NSArray *)audioData
{
    [_buffer enqueueFromDataArray:audioData];
}

#pragma mark - progress
- (NSTimeInterval)progress
{
    if (_seekRequired)
    {
        return _seekTime;
    }
    return _timingOffset + _audioQueue.playedTime;
}

- (void)setProgress:(NSTimeInterval)progress
{
    _seekRequired = YES;
    _seekTime = progress;
}

- (NSTimeInterval)duration
{
    return _usingAudioFile ? _audioFile.duration : _audioFileStream.duration;
}

#pragma mark - method
- (void)play
{
    if (!_started)
    {
        _started = YES;
        [self _mutexInit];
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain) object:nil];
        [_thread start];
    }
    else
    {
        if (_status == VDSAPStatusPaused || _pauseRequired)
        {
            _pausedByInterrupt = NO;
            _pauseRequired = NO;
            if ([[VDAudioSession sharedInstance] setActive:YES error:NULL])
            {
                [[VDAudioSession sharedInstance] setCategory:kAudioSessionCategory_MediaPlayback error:NULL];
                [self _resume];
            }
        }
    }
}

- (void)_resume
{
    [_audioQueue resume];
    [self _mutexSignal];
}

- (void)pause
{
    if (self.isPlayingOrWaiting && self.status != VDSAPStatusFlushing)
    {
        _pauseRequired = YES;
    }
}

- (void)stop
{
    _stopRequired = YES;
    [self _mutexSignal];
}
@end
