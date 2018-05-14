//
//  ViewController.m
//  LearnVideoToolBox
//
//  Created by 林伟池 on 16/9/1.
//  Copyright © 2016年 林伟池. All rights reserved.
//

#import "ViewController.h"
#import "LYOpenGLView.h"
#import <VideoToolbox/VideoToolbox.h>

@interface ViewController ()
@property (nonatomic , strong) LYOpenGLView *mOpenGLView;
@property (nonatomic , strong) UILabel  *mLabel;
@property (nonatomic , strong) UIButton *mButton;
@property (nonatomic , strong) CADisplayLink *mDispalyLink;
@end

const uint8_t lyStartCode[4] = {0, 0, 0, 1};

/*
 概念介绍
 
 CVPixelBuffer
 包含未压缩的像素数据，包括图像宽度、高度等；
 
 CVPixelBufferPool
 CVPixelBuffer的缓冲池，因为CVPixelBuffer的创建和销毁代价很大；
 
 pixelBufferAttributes
 CFDictionary包括宽高、像素格式（RGBA、YUV）、使用场景（OpenGL ES、Core Animation）
 
 CMTime
 64位的value，32位的scale，media的时间格式；
 
 CMVideoFormatDescription
 video的格式，包括宽高、颜色空间、编码格式等；对于H.264的视频，PPS和SPS的数据也在这里；
 
 CMBlockBuffer
 未压缩的图像数据；
 
 CMSampleBuffer
 存放一个或者多个压缩或未压缩的媒体文件；
 
 CMClock
 时间源：A timing source object.
 
 CMTimebase
 时间控制器，可以设置rate和time：A timebase represents a timeline that clients can control by setting the rate and time. Each timebase has either a master clock or a master timebase. The rate of the timebase is expressed relative to its master.
 
 当遇到IDR帧时，更合适的做法是通过
 VTDecompressionSessionCanAcceptFormatDescription判断原来的session是否能接受新的SPS和PPS，如果不能再新建session。
 
 WWDC的视频：https://developer.apple.com/videos/play/wwdc2014/513/
 OpenGLES文集：https://www.jianshu.com/nb/2135411
 */

@implementation ViewController
{
    dispatch_queue_t mDecodeQueue;
    VTDecompressionSessionRef mDecodeSession;
    CMFormatDescriptionRef  mFormatDescription;
    uint8_t *mSPS;
    long mSPSSize;
    uint8_t *mPPS;
    long mPPSSize;
    
    // 输入
    NSInputStream *inputStream;
    uint8_t*       packetBuffer;
    long         packetSize;
    uint8_t*       inputBuffer;
    long         inputSize;
    long         inputMaxSize;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.mOpenGLView = (LYOpenGLView *)self.view;
    [self.mOpenGLView setupGL];
    
    mDecodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    self.mLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 200, 100)];
    self.mLabel.textColor = [UIColor redColor];
    [self.view addSubview:self.mLabel];
    self.mLabel.text = @"测试H264硬解码";
    
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(200, 20, 100, 100)];
    [button setTitle:@"play" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [self.view addSubview:button];
    [button addTarget:self action:@selector(onClick:) forControlEvents:UIControlEventTouchUpInside];
    self.mButton = button;
    
    
    self.mDispalyLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFrame)];
        self.mDispalyLink.frameInterval = 2; // 默认是30FPS的帧率录制
    [self.mDispalyLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.mDispalyLink setPaused:YES];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)onClick:(UIButton *)button {
    button.hidden = YES;
    [self startDecode];
}

- (void)onInputStart {
    inputStream = [[NSInputStream alloc] initWithFileAtPath:[[NSBundle mainBundle] pathForResource:@"abc" ofType:@"h264"]];
    [inputStream open];
    inputSize = 0;
    inputMaxSize = 640 * 480 * 3 * 4;
    inputBuffer = malloc(inputMaxSize);
}

- (void)onInputEnd {
    [inputStream close];
    inputStream = nil;
    if (inputBuffer) {
        free(inputBuffer);
        inputBuffer = NULL;
    }
    [self.mDispalyLink setPaused:YES];
    self.mButton.hidden = NO;
}

- (void)readPacket {
    if (packetSize && packetBuffer) {
        packetSize = 0;
        free(packetBuffer);
        packetBuffer = NULL;
    }
    if (inputSize < inputMaxSize && inputStream.hasBytesAvailable) {
        inputSize += [inputStream read:inputBuffer + inputSize maxLength:inputMaxSize - inputSize];
    }
    if (memcmp(inputBuffer, lyStartCode, 4) == 0) {
        if (inputSize > 4) { // 除了开始码还有内容
            uint8_t *pStart = inputBuffer + 4;
            uint8_t *pEnd = inputBuffer + inputSize;
            while (pStart != pEnd) { //这里使用一种简略的方式来获取这一帧的长度：通过查找下一个0x00000001来确定。
                if(memcmp(pStart - 3, lyStartCode, 4) == 0) {
                    packetSize = pStart - inputBuffer - 3;
                    if (packetBuffer) {
                        free(packetBuffer);
                        packetBuffer = NULL;
                    }
                    packetBuffer = malloc(packetSize);
                    memcpy(packetBuffer, inputBuffer, packetSize); //复制packet内容到新的缓冲区
                    memmove(inputBuffer, inputBuffer + packetSize, inputSize - packetSize); //把缓冲区前移
                    inputSize -= packetSize;
                    break;
                }
                else {
                    ++pStart;
                }
            }
        }
    }
}

void didDecompress(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
    *outputPixelBuffer = CVPixelBufferRetain(pixelBuffer);
}



-(void)startDecode {
    [self onInputStart];
    [self.mDispalyLink setPaused:NO];
}

-(void)updateFrame {
    if (inputStream){
        dispatch_sync(mDecodeQueue, ^{
            [self readPacket];
            if (packetBuffer == NULL || packetSize == 0) {
                [self onInputEnd];
                return ;
            }
            //替换头字节长度
            uint32_t nalSize = (uint32_t)(packetSize - 4);
            uint32_t *pNalSize = (uint32_t *)packetBuffer;
            *pNalSize = CFSwapInt32HostToBig(nalSize);
            
            // 在buffer的前面填入代表长度的int
            CVPixelBufferRef pixelBuffer = NULL;
            int nalType = packetBuffer[4] & 0x1F;
            switch (nalType) {
                case 0x05:
                    NSLog(@"Nal type is IDR frame");
                    [self initVideoToolBox];
                    pixelBuffer = [self decode];
                    break;
                case 0x07:
                    NSLog(@"Nal type is SPS");
                    mSPSSize = packetSize - 4;
                    mSPS = malloc(mSPSSize);
                    memcpy(mSPS, packetBuffer + 4, mSPSSize);
                    break;
                case 0x08:
                    NSLog(@"Nal type is PPS");
                    mPPSSize = packetSize - 4;
                    mPPS = malloc(mPPSSize);
                    memcpy(mPPS, packetBuffer + 4, mPPSSize);
                    break;
                default:
                    NSLog(@"Nal type is B/P frame");
                    pixelBuffer = [self decode];
                    break;
            }
            
            if(pixelBuffer) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    //显示解码的结果
                    [self.mOpenGLView displayPixelBuffer:pixelBuffer];
                    CVPixelBufferRelease(pixelBuffer);
                });
            }
            NSLog(@"Read Nalu size %ld", packetSize);
        });
    }
}

- (CVPixelBufferRef)decode {
    CVPixelBufferRef outputPixelBuffer = NULL;
    if (mDecodeSession) {
        //用CMBlockBuffer把NALUnit包装起来
        CMBlockBufferRef blockBuffer = NULL;
        OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                              (void*)packetBuffer, packetSize,
                                                              kCFAllocatorNull,
                                                              NULL, 0, packetSize,
                                                              0, &blockBuffer);
        if (status == kCMBlockBufferNoErr) {
            //创建CMSampleBuffer
            CMSampleBufferRef sampleBuffer = NULL;
            const size_t sampleSizeArray[] = {packetSize};
            status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                               blockBuffer,
                                               mFormatDescription,
                                               1, 0, NULL, 1, sampleSizeArray,
                                               &sampleBuffer);
            if (status == kCMBlockBufferNoErr && sampleBuffer) {
                //传入CMSampleBuffer
                VTDecodeFrameFlags flags = 0;
                VTDecodeInfoFlags flagOut = 0;
                // 默认是同步操作。
                // 调用didDecompress，返回后再回调
                OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(mDecodeSession,
                                                                          sampleBuffer,
                                                                          flags,
                                                                          &outputPixelBuffer,
                                                                          &flagOut);
                
                if(decodeStatus == kVTInvalidSessionErr) {
                    NSLog(@"IOS8VT: Invalid session, reset decoder session");
                } else if(decodeStatus == kVTVideoDecoderBadDataErr) {
                    NSLog(@"IOS8VT: decode failed status=%d(Bad data)", decodeStatus);
                } else if(decodeStatus != noErr) {
                    NSLog(@"IOS8VT: decode failed status=%d", decodeStatus);
                }
                
                CFRelease(sampleBuffer);
            }
            CFRelease(blockBuffer);
        }
    }
    
    return outputPixelBuffer;
}



- (void)initVideoToolBox {
    if (!mDecodeSession) {
        //把SPS和PPS包装成CMVideoFormatDescription
        const uint8_t* parameterSetPointers[2] = {mSPS, mPPS};
        const size_t parameterSetSizes[2] = {mSPSSize, mPPSSize};
        OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                              2, //param count
                                                                              parameterSetPointers,
                                                                              parameterSetSizes,
                                                                              4, //nal start code size
                                                                              &mFormatDescription);
        if (status == noErr) {
            CFDictionaryRef attrs = NULL;
            const void *keys[] = { kCVPixelBufferPixelFormatTypeKey };
            //      kCVPixelFormatType_420YpCbCr8Planar is YUV420
            //      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is NV12
            uint32_t v = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
            const void *values[] = { CFNumberCreate(NULL, kCFNumberSInt32Type, &v) };
            attrs = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
            
            VTDecompressionOutputCallbackRecord callBackRecord;
            callBackRecord.decompressionOutputCallback = didDecompress;
            callBackRecord.decompressionOutputRefCon = NULL;
            
            status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                                  mFormatDescription,
                                                  NULL, attrs,
                                                  &callBackRecord,
                                                  &mDecodeSession);
            CFRelease(attrs);
        } else {
            NSLog(@"IOS8VT: reset decoder session failed status=%d", status);
        }
        
        
    }
}

- (void)EndVideoToolBox
{
    if(mDecodeSession) {
        VTDecompressionSessionInvalidate(mDecodeSession);
        CFRelease(mDecodeSession);
        mDecodeSession = NULL;
    }
    
    if(mFormatDescription) {
        CFRelease(mFormatDescription);
        mFormatDescription = NULL;
    }
    
    free(mSPS);
    free(mPPS);
    mSPSSize = mPPSSize = 0;
}


@end
