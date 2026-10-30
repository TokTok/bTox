#import <AVFoundation/AVFoundation.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#include "btox_call_media.h"
#include "nv12.h"

#define MAX_FPS 24

@interface BtoxCamera : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

@implementation BtoxCamera {
  AVCaptureSession *_session;
  AVCaptureConnection *_connection;
  dispatch_queue_t _queue;
  btox_video_frame_cb *_onFrame;
  btox_camera_stopped_cb *_onStopped;
  NSMutableArray<id> *_observers;
  CMTime _lastFrame;
}

/* On a Mac the built-in one, else any. */
static AVCaptureDevice *find_camera(bool front) {
#if TARGET_OS_IPHONE
  return [AVCaptureDevice
      defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                        mediaType:AVMediaTypeVideo
                         position:front ? AVCaptureDevicePositionFront
                                        : AVCaptureDevicePositionBack];
#else
  NSArray<AVCaptureDevice *> *cameras =
      [AVCaptureDeviceDiscoverySession
          discoverySessionWithDeviceTypes:@[
            AVCaptureDeviceTypeBuiltInWideAngleCamera
          ]
                                mediaType:AVMediaTypeVideo
                                 position:AVCaptureDevicePositionUnspecified]
          .devices;
  /* Laptops have one camera. With another plugged in, it's the back one. */
  if (!front && cameras.count > 1) {
    return cameras[1];
  }
  return cameras.firstObject
             ?: [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
#endif
}

#if TARGET_OS_IPHONE
/* Upright as the phone is held: the camera's view turns the other way. */
static AVCaptureVideoOrientation
orientation_of(UIDeviceOrientation device, AVCaptureVideoOrientation current) {
  switch (device) {
  case UIDeviceOrientationPortrait:
    return AVCaptureVideoOrientationPortrait;
  case UIDeviceOrientationPortraitUpsideDown:
    return AVCaptureVideoOrientationPortraitUpsideDown;
  case UIDeviceOrientationLandscapeLeft:
    return AVCaptureVideoOrientationLandscapeRight;
  case UIDeviceOrientationLandscapeRight:
    return AVCaptureVideoOrientationLandscapeLeft;
  default:
    /* Face up or down: as it was. */
    return current;
  }
}
#endif

- (BOOL)startFront:(bool)front
           onFrame:(btox_video_frame_cb *)onFrame
         onStopped:(btox_camera_stopped_cb *)onStopped {
  AVCaptureDevice *camera = find_camera(front);
  AVCaptureDeviceInput *input =
      camera != nil
          ? [AVCaptureDeviceInput deviceInputWithDevice:camera error:nil]
          : nil;
  if (input == nil) {
    return NO;
  }
  _onFrame = onFrame;
  _onStopped = onStopped;
  _lastFrame = kCMTimeInvalid;
  _queue = dispatch_queue_create("btox camera", DISPATCH_QUEUE_SERIAL);
  _session = [[AVCaptureSession alloc] init];
  if ([_session canSetSessionPreset:AVCaptureSessionPreset640x480]) {
    _session.sessionPreset = AVCaptureSessionPreset640x480;
  }
  AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
  output.videoSettings = @{
    (id)kCVPixelBufferPixelFormatTypeKey :
        @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
  };
  output.alwaysDiscardsLateVideoFrames = YES;
  [output setSampleBufferDelegate:self queue:_queue];
  if (![_session canAddInput:input] || ![_session canAddOutput:output]) {
    return NO;
  }
  [_session addInput:input];
  [_session addOutput:output];
  _connection = [output connectionWithMediaType:AVMediaTypeVideo];
  /* The friend sees us as others do, and our own view mirrors it. */
  if (_connection.isVideoMirroringSupported) {
    _connection.automaticallyAdjustsVideoMirroring = NO;
    _connection.videoMirrored = NO;
  }

  _observers = [NSMutableArray array];
  NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
  __weak BtoxCamera *weakSelf = self;
  void (^stopped)(NSNotification *) = ^(NSNotification *note) {
    BtoxCamera *strongSelf = weakSelf;
    if (strongSelf != nil) {
      strongSelf->_onStopped();
    }
  };
  [_observers
      addObject:[center
                    addObserverForName:AVCaptureSessionRuntimeErrorNotification
                                object:_session
                                 queue:nil
                            usingBlock:stopped]];
#if TARGET_OS_IPHONE
  /* As when a call or another app takes it. In the background it comes back
     by itself. */
  [_observers
      addObject:
          [center
              addObserverForName:AVCaptureSessionWasInterruptedNotification
                          object:_session
                           queue:nil
                      usingBlock:^(NSNotification *note) {
                        NSNumber *reason =
                            note.userInfo
                                [AVCaptureSessionInterruptionReasonKey];
                        if (reason.integerValue !=
                            AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableInBackground) {
                          stopped(note);
                        }
                      }]];
  dispatch_async(dispatch_get_main_queue(), ^{
    [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
  });
  AVCaptureConnection *connection = _connection;
  connection.videoOrientation = orientation_of(
      UIDevice.currentDevice.orientation, AVCaptureVideoOrientationPortrait);
  [_observers
      addObject:[center
                    addObserverForName:UIDeviceOrientationDidChangeNotification
                                object:nil
                                 queue:nil
                            usingBlock:^(NSNotification *note) {
                              connection.videoOrientation = orientation_of(
                                  UIDevice.currentDevice.orientation,
                                  connection.videoOrientation);
                            }]];
#else
  [_observers addObject:[center addObserverForName:
                                    AVCaptureDeviceWasDisconnectedNotification
                                            object:camera
                                             queue:nil
                                        usingBlock:stopped]];
#endif
  AVCaptureSession *session = _session;
  dispatch_async(_queue, ^{
    [session startRunning];
  });
  return YES;
}

- (void)stop {
  for (id observer in _observers) {
    [NSNotificationCenter.defaultCenter removeObserver:observer];
  }
#if TARGET_OS_IPHONE
  dispatch_async(dispatch_get_main_queue(), ^{
    [UIDevice.currentDevice endGeneratingDeviceOrientationNotifications];
  });
#endif
  AVCaptureSession *session = _session;
  /* Frames already on their way are delivered first. */
  dispatch_sync(_queue, ^{
    [session stopRunning];
  });
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
  const CMTime time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
  if (CMTIME_IS_VALID(_lastFrame) &&
      CMTimeGetSeconds(CMTimeSubtract(time, _lastFrame)) < 1.0 / MAX_FPS) {
    return;
  }
  _lastFrame = time;
  CVPixelBufferRef pixels = CMSampleBufferGetImageBuffer(sampleBuffer);
  if (pixels == NULL ||
      CVPixelBufferLockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly) !=
          kCVReturnSuccess) {
    return;
  }
  const size_t width = CVPixelBufferGetWidthOfPlane(pixels, 0);
  const size_t height = CVPixelBufferGetHeightOfPlane(pixels, 0);
  uint8_t *frame = btox_nv12_to_i420(
      CVPixelBufferGetBaseAddressOfPlane(pixels, 0),
      CVPixelBufferGetBytesPerRowOfPlane(pixels, 0),
      CVPixelBufferGetBaseAddressOfPlane(pixels, 1),
      CVPixelBufferGetBytesPerRowOfPlane(pixels, 1), width, height);
  CVPixelBufferUnlockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly);
  if (frame != NULL) {
    _onFrame(frame, (int32_t)width, (int32_t)height);
  }
}

@end

static BtoxCamera *camera;

bool btox_camera_start(bool front, btox_video_frame_cb *on_frame,
                       btox_camera_stopped_cb *on_stopped) {
  btox_camera_stop();
  BtoxCamera *started = [[BtoxCamera alloc] init];
  if (![started startFront:front onFrame:on_frame onStopped:on_stopped]) {
    return false;
  }
  camera = started;
  return true;
}

void btox_camera_stop(void) {
  [camera stop];
  camera = nil;
}
