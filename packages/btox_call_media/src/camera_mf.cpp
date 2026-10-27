#include <windows.h>

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>

#include <atomic>
#include <future>
#include <thread>

#include "btox_call_media.h"
#include "nv12.h"

namespace {

constexpr UINT32 kWidth = 640;
constexpr UINT32 kHeight = 480;
constexpr LONGLONG kMaxFps = 24;
// Media Foundation's time unit, 100 ns.
constexpr LONGLONG kSecond = 10'000'000;

template <typename T> struct Ref {
  T *p = nullptr;
  Ref() = default;
  Ref(const Ref &) = delete;
  Ref &operator=(const Ref &) = delete;
  ~Ref() {
    if (p != nullptr) {
      p->Release();
    }
  }
  T **put() { return &p; }
  T *operator->() const { return p; }
};

struct Camera {
  std::thread thread;
  std::atomic<bool> stopping{false};
  btox_video_frame_cb *on_frame;
  btox_camera_stopped_cb *on_stopped;
};

Camera *camera;

// Else the first.
bool open_source(UINT32 index, Ref<IMFMediaSource> &source) {
  Ref<IMFAttributes> attributes;
  if (FAILED(MFCreateAttributes(attributes.put(), 1)) ||
      FAILED(attributes->SetGUID(
          MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
          MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID))) {
    return false;
  }
  IMFActivate **devices = nullptr;
  UINT32 count = 0;
  if (FAILED(MFEnumDeviceSources(attributes.p, &devices, &count))) {
    return false;
  }
  bool opened =
      count > 0 && SUCCEEDED(devices[index < count ? index : 0]->ActivateObject(
                       IID_PPV_ARGS(source.put())));
  for (UINT32 i = 0; i < count; ++i) {
    devices[i]->Release();
  }
  CoTaskMemFree(devices);
  return opened;
}

// The camera's own size nearest [kWidth] by [kHeight], as NV12.
bool choose_format(IMFSourceReader *reader, UINT32 &width, UINT32 &height) {
  UINT64 best = UINT64_MAX;
  for (DWORD i = 0;; ++i) {
    Ref<IMFMediaType> type;
    if (FAILED(reader->GetNativeMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM,
                                          i, type.put()))) {
      break;
    }
    UINT32 w = 0;
    UINT32 h = 0;
    if (FAILED(MFGetAttributeSize(type.p, MF_MT_FRAME_SIZE, &w, &h))) {
      continue;
    }
    const UINT64 distance = static_cast<UINT64>(
        llabs(static_cast<LONGLONG>(w) * h - kWidth * kHeight));
    if (distance < best) {
      best = distance;
      width = w;
      height = h;
    }
  }
  Ref<IMFMediaType> nv12;
  return best != UINT64_MAX && SUCCEEDED(MFCreateMediaType(nv12.put())) &&
         SUCCEEDED(nv12->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video)) &&
         SUCCEEDED(nv12->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12)) &&
         SUCCEEDED(
             MFSetAttributeSize(nv12.p, MF_MT_FRAME_SIZE, width, height)) &&
         SUCCEEDED(reader->SetCurrentMediaType(
             MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, nv12.p));
}

void deliver(IMFSample *sample, UINT32 width, UINT32 height) {
  Ref<IMFMediaBuffer> buffer;
  if (FAILED(sample->ConvertToContiguousBuffer(buffer.put()))) {
    return;
  }
  Ref<IMF2DBuffer> picture;
  BYTE *data = nullptr;
  LONG pitch = static_cast<LONG>(width);
  uint8_t *frame = nullptr;
  // NV12, its chroma after its luma, rows [pitch] apart.
  const auto i420 = [&] {
    return btox_nv12_to_i420(data, pitch, data + height * pitch, pitch, width,
                             height);
  };
  if (SUCCEEDED(buffer->QueryInterface(IID_PPV_ARGS(picture.put()))) &&
      SUCCEEDED(picture->Lock2D(&data, &pitch))) {
    frame = i420();
    picture->Unlock2D();
  } else if (SUCCEEDED(buffer->Lock(&data, nullptr, nullptr))) {
    frame = i420();
    buffer->Unlock();
  }
  if (frame != nullptr) {
    camera->on_frame(frame, static_cast<int32_t>(width),
                     static_cast<int32_t>(height));
  }
}

// All on this thread. [started] hears whether it opened.
void capture(UINT32 index, std::promise<bool> started) {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  MFStartup(MF_VERSION, MFSTARTUP_LITE);
  {
    Ref<IMFMediaSource> source;
    Ref<IMFAttributes> attributes;
    Ref<IMFSourceReader> reader;
    UINT32 width = 0;
    UINT32 height = 0;
    const bool opened =
        open_source(index, source) &&
        SUCCEEDED(MFCreateAttributes(attributes.put(), 1)) &&
        SUCCEEDED(attributes->SetUINT32(
            MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE)) &&
        SUCCEEDED(MFCreateSourceReaderFromMediaSource(source.p, attributes.p,
                                                      reader.put())) &&
        choose_format(reader.p, width, height);
    started.set_value(opened);
    LONGLONG last = -kSecond;
    while (opened && !camera->stopping) {
      DWORD flags = 0;
      LONGLONG time = 0;
      Ref<IMFSample> sample;
      if (FAILED(reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0,
                                    nullptr, &flags, &time, sample.put())) ||
          (flags & (MF_SOURCE_READERF_ERROR | MF_SOURCE_READERF_ENDOFSTREAM)) !=
              0) {
        // Unplugged, or taken.
        camera->on_stopped();
        break;
      }
      if (sample.p != nullptr && time - last >= kSecond / kMaxFps) {
        last = time;
        deliver(sample.p, width, height);
      }
    }
    if (source.p != nullptr) {
      source->Shutdown();
    }
  }
  MFShutdown();
  CoUninitialize();
}

} // namespace

bool btox_camera_start(bool front, btox_video_frame_cb *on_frame,
                       btox_camera_stopped_cb *on_stopped) {
  btox_camera_stop();
  camera = new Camera{{}, {false}, on_frame, on_stopped};
  std::promise<bool> started;
  std::future<bool> opened = started.get_future();
  // Tablets have a front camera and a back one. With another plugged in,
  // it's the back one.
  camera->thread = std::thread(capture, front ? 0 : 1, std::move(started));
  if (!opened.get()) {
    btox_camera_stop();
    return false;
  }
  return true;
}

void btox_camera_stop(void) {
  if (camera == nullptr) {
    return;
  }
  camera->stopping = true;
  camera->thread.join();
  delete camera;
  camera = nullptr;
}
