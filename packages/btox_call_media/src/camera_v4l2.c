#include <errno.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include "btox_call_media.h"

#define WIDTH 640
#define HEIGHT 480
#define FPS 24
#define BUFFERS 4
/* Cameras have /dev/video nodes from 0, also ones for their metadata. */
#define MAX_DEVICES 64

static struct {
  bool running;
  int fd;
  /* Written to when it's to stop. */
  int stop[2];
  pthread_t thread;
  void *buffers[BUFFERS];
  size_t lengths[BUFFERS];
  uint32_t width;
  uint32_t height;
  btox_video_frame_cb *on_frame;
  btox_camera_stopped_cb *on_stopped;
} camera;

static int xioctl(int fd, unsigned long request, void *arg) {
  int r;
  do {
    r = ioctl(fd, request, arg);
  } while (r == -1 && errno == EINTR);
  return r;
}

/* Of those that capture video, or -1. */
static int open_camera(int index) {
  for (int i = 0; i < MAX_DEVICES; ++i) {
    char path[32];
    snprintf(path, sizeof(path), "/dev/video%d", i);
    const int fd = open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
    if (fd == -1) {
      continue;
    }
    struct v4l2_capability caps = {0};
    if (xioctl(fd, VIDIOC_QUERYCAP, &caps) == 0) {
      const uint32_t device_caps = caps.capabilities & V4L2_CAP_DEVICE_CAPS
                                       ? caps.device_caps
                                       : caps.capabilities;
      if ((device_caps & V4L2_CAP_VIDEO_CAPTURE) &&
          (device_caps & V4L2_CAP_STREAMING) && index-- == 0) {
        return fd;
      }
    }
    close(fd);
  }
  return -1;
}

/* Two pixels in four bytes. The chroma of two rows is averaged. */
static void yuyv_to_i420(const uint8_t *src, uint32_t width, uint32_t height,
                         uint8_t *dst) {
  const uint32_t cw = (width + 1) / 2;
  const uint32_t ch = (height + 1) / 2;
  uint8_t *y = dst;
  uint8_t *u = dst + width * height;
  uint8_t *v = u + cw * ch;
  const uint32_t stride = cw * 4;
  for (uint32_t row = 0; row < height; ++row) {
    const uint8_t *line = src + row * stride;
    for (uint32_t x = 0; x < width; ++x) {
      y[row * width + x] = line[x * 2];
    }
    if (row % 2 == 0) {
      const uint8_t *next = row + 1 < height ? line + stride : line;
      for (uint32_t x = 0; x < cw; ++x) {
        u[row / 2 * cw + x] =
            (uint8_t)((line[x * 4 + 1] + next[x * 4 + 1] + 1) / 2);
        v[row / 2 * cw + x] =
            (uint8_t)((line[x * 4 + 3] + next[x * 4 + 3] + 1) / 2);
      }
    }
  }
}

static void *capture(void *arg) {
  (void)arg;
  const size_t size = camera.width * camera.height +
                      2 * ((camera.width + 1) / 2) * ((camera.height + 1) / 2);
  for (;;) {
    struct pollfd fds[2] = {{.fd = camera.fd, .events = POLLIN},
                            {.fd = camera.stop[0], .events = POLLIN}};
    if (poll(fds, 2, -1) == -1) {
      if (errno == EINTR) {
        continue;
      }
      break;
    }
    if (fds[1].revents != 0) {
      return NULL;
    }
    struct v4l2_buffer buffer = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
                                 .memory = V4L2_MEMORY_MMAP};
    if (xioctl(camera.fd, VIDIOC_DQBUF, &buffer) == -1) {
      if (errno == EAGAIN) {
        continue;
      }
      /* Unplugged, or taken. */
      break;
    }
    uint8_t *frame = malloc(size);
    if (frame != NULL) {
      yuyv_to_i420(camera.buffers[buffer.index], camera.width, camera.height,
                   frame);
      camera.on_frame(frame, (int32_t)camera.width, (int32_t)camera.height);
    }
    if (xioctl(camera.fd, VIDIOC_QBUF, &buffer) == -1) {
      break;
    }
  }
  camera.on_stopped();
  return NULL;
}

static void close_camera(void) {
  for (int i = 0; i < BUFFERS; ++i) {
    if (camera.buffers[i] != NULL && camera.buffers[i] != MAP_FAILED) {
      munmap(camera.buffers[i], camera.lengths[i]);
    }
  }
  close(camera.fd);
  close(camera.stop[0]);
  close(camera.stop[1]);
  memset(&camera, 0, sizeof(camera));
}

bool btox_camera_start(bool front, btox_video_frame_cb *on_frame,
                       btox_camera_stopped_cb *on_stopped) {
  btox_camera_stop();
  /* Laptops have one camera. With another plugged in, it's the back one. */
  int fd = open_camera(front ? 0 : 1);
  if (fd == -1 && !front) {
    fd = open_camera(0);
  }
  if (fd == -1) {
    return false;
  }
  camera.fd = fd;
  camera.on_frame = on_frame;
  camera.on_stopped = on_stopped;
  if (pipe(camera.stop) == -1) {
    close(fd);
    memset(&camera, 0, sizeof(camera));
    return false;
  }

  struct v4l2_format format = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE};
  format.fmt.pix.width = WIDTH;
  format.fmt.pix.height = HEIGHT;
  format.fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
  format.fmt.pix.field = V4L2_FIELD_NONE;
  if (xioctl(fd, VIDIOC_S_FMT, &format) == -1 ||
      format.fmt.pix.pixelformat != V4L2_PIX_FMT_YUYV ||
      format.fmt.pix.bytesperline != (format.fmt.pix.width + 1) / 2 * 4) {
    close_camera();
    return false;
  }
  camera.width = format.fmt.pix.width;
  camera.height = format.fmt.pix.height;
  struct v4l2_streamparm rate = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE};
  rate.parm.capture.timeperframe.numerator = 1;
  rate.parm.capture.timeperframe.denominator = FPS;
  xioctl(fd, VIDIOC_S_PARM, &rate);

  struct v4l2_requestbuffers request = {.count = BUFFERS,
                                        .type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
                                        .memory = V4L2_MEMORY_MMAP};
  if (xioctl(fd, VIDIOC_REQBUFS, &request) == -1 || request.count < 2) {
    close_camera();
    return false;
  }
  for (uint32_t i = 0; i < request.count && i < BUFFERS; ++i) {
    struct v4l2_buffer buffer = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
                                 .memory = V4L2_MEMORY_MMAP,
                                 .index = i};
    if (xioctl(fd, VIDIOC_QUERYBUF, &buffer) == -1) {
      close_camera();
      return false;
    }
    camera.lengths[i] = buffer.length;
    camera.buffers[i] = mmap(NULL, buffer.length, PROT_READ | PROT_WRITE,
                             MAP_SHARED, fd, buffer.m.offset);
    if (camera.buffers[i] == MAP_FAILED ||
        xioctl(fd, VIDIOC_QBUF, &buffer) == -1) {
      close_camera();
      return false;
    }
  }
  enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (xioctl(fd, VIDIOC_STREAMON, &type) == -1) {
    close_camera();
    return false;
  }
  if (pthread_create(&camera.thread, NULL, capture, NULL) != 0) {
    xioctl(fd, VIDIOC_STREAMOFF, &type);
    close_camera();
    return false;
  }
  camera.running = true;
  return true;
}

void btox_camera_stop(void) {
  if (!camera.running) {
    return;
  }
  const char stop = 0;
  if (write(camera.stop[1], &stop, 1) == 1) {
    pthread_join(camera.thread, NULL);
  }
  enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  xioctl(camera.fd, VIDIOC_STREAMOFF, &type);
  close_camera();
}
