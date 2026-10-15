#import <AVFoundation/AVFoundation.h>

#include "btox_call_media.h"

void btox_request_permissions(bool camera, btox_permissions_cb *done) {
  [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio
                           completionHandler:^(BOOL microphone) {
                             if (!microphone || !camera) {
                               done(microphone);
                               return;
                             }
                             [AVCaptureDevice
                                 requestAccessForMediaType:AVMediaTypeVideo
                                         completionHandler:^(BOOL granted) {
                                           done(granted);
                                         }];
                           }];
}
