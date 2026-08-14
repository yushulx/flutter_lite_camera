// Fake V4L2 capture device for CI.
//
// GitHub-hosted runners have no camera, the azure kernel ships no V4L2 core
// modules, and mid-job reboots are not supported, so v4l2loopback cannot be
// used. This LD_PRELOAD shim intercepts open("/dev/video*") plus the ioctls
// the plugin uses and serves a synthetic YUYV test pattern, allowing the
// full camera pipeline (open -> stream -> texture -> captureFrame) to run
// end-to-end in userspace.
//
// Build: gcc -shared -fPIC -O2 -o fake_v4l2.so fake_v4l2.c -ldl

#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <linux/videodev2.h>

#define NUM_BUFFERS 4
#define FRAME_W 640
#define FRAME_H 480
#define FRAME_SIZE (FRAME_W * FRAME_H * 2) /* YUYV: 2 bytes per pixel */

static int fake_fds[8];
static int num_fake_fds = 0;
static unsigned char fake_buffers[NUM_BUFFERS][FRAME_SIZE];
static int buffers_initialized = 0;
static unsigned int dq_index = 0;

static int is_fake_fd(int fd)
{
    for (int i = 0; i < num_fake_fds; i++)
    {
        if (fake_fds[i] == fd)
            return 1;
    }
    return 0;
}

/* Grayscale gradient with neutral chroma; buffer index shifts the pattern. */
static void init_buffers(void)
{
    if (buffers_initialized)
        return;
    for (int b = 0; b < NUM_BUFFERS; b++)
    {
        for (int p = 0; p < FRAME_W * FRAME_H; p++)
        {
            fake_buffers[b][p * 2] = (unsigned char)((p + b * 16) & 0xFF); /* Y */
            fake_buffers[b][p * 2 + 1] = 128;                            /* U or V */
        }
    }
    buffers_initialized = 1;
}

static int open_impl(const char *path, int flags, mode_t mode, int has_mode)
{
    static int (*real_open)(const char *, int, ...) = NULL;
    if (!real_open)
        real_open = dlsym(RTLD_NEXT, "open");

    if (strncmp(path, "/dev/video", 10) == 0)
    {
        /* Back the fake device with a real fd so poll() behaves. */
        int fd = real_open("/dev/null", O_RDWR);
        if (fd >= 0 && num_fake_fds < 8)
            fake_fds[num_fake_fds++] = fd;
        return fd;
    }
    if (has_mode)
        return real_open(path, flags, mode);
    return real_open(path, flags);
}

int open(const char *path, int flags, ...)
{
    int has_mode = (flags & O_CREAT) != 0;
    mode_t mode = 0;
    if (has_mode)
    {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return open_impl(path, flags, mode, has_mode);
}

int open64(const char *path, int flags, ...)
{
    int has_mode = (flags & O_CREAT) != 0;
    mode_t mode = 0;
    if (has_mode)
    {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    return open_impl(path, flags, mode, has_mode);
}

int ioctl(int fd, unsigned long request, ...)
{
    static int (*real_ioctl)(int, unsigned long, ...) = NULL;
    if (!real_ioctl)
        real_ioctl = dlsym(RTLD_NEXT, "ioctl");

    va_list ap;
    va_start(ap, request);
    void *arg = va_arg(ap, void *);
    va_end(ap);

    if (!is_fake_fd(fd))
        return real_ioctl(fd, request, arg);

    init_buffers();

    switch (request)
    {
    case VIDIOC_QUERYCAP:
    {
        struct v4l2_capability *cap = (struct v4l2_capability *)arg;
        memset(cap, 0, sizeof(*cap));
        strcpy((char *)cap->driver, "fakev4l2");
        strcpy((char *)cap->card, "CI Camera");
        cap->capabilities = V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING;
        return 0;
    }
    case VIDIOC_S_FMT:
    case VIDIOC_G_FMT:
    {
        struct v4l2_format *fmt = (struct v4l2_format *)arg;
        fmt->fmt.pix.width = FRAME_W;
        fmt->fmt.pix.height = FRAME_H;
        fmt->fmt.pix.pixelformat = V4L2_PIX_FMT_YUYV;
        fmt->fmt.pix.sizeimage = FRAME_SIZE;
        fmt->fmt.pix.bytesperline = FRAME_W * 2;
        return 0;
    }
    case VIDIOC_REQBUFS:
    {
        struct v4l2_requestbuffers *req = (struct v4l2_requestbuffers *)arg;
        if (req->count == 0 || req->count > NUM_BUFFERS)
            req->count = NUM_BUFFERS;
        return 0;
    }
    case VIDIOC_QUERYBUF:
    {
        struct v4l2_buffer *buf = (struct v4l2_buffer *)arg;
        buf->length = FRAME_SIZE;
        buf->m.offset = buf->index * FRAME_SIZE;
        return 0;
    }
    case VIDIOC_QBUF:
        return 0;
    case VIDIOC_DQBUF:
    {
        struct v4l2_buffer *buf = (struct v4l2_buffer *)arg;
        /* Throttle to roughly camera frame rates. */
        usleep(16000);
        buf->index = dq_index;
        buf->bytesused = FRAME_SIZE;
        dq_index = (dq_index + 1) % NUM_BUFFERS;
        return 0;
    }
    case VIDIOC_STREAMON:
    case VIDIOC_STREAMOFF:
        return 0;
    default:
        return 0;
    }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset)
{
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t) = NULL;
    if (!real_mmap)
        real_mmap = dlsym(RTLD_NEXT, "mmap");

    if (is_fake_fd(fd))
    {
        int idx = (int)(offset / FRAME_SIZE);
        if (idx < 0)
            idx = 0;
        if (idx >= NUM_BUFFERS)
            idx = NUM_BUFFERS - 1;
        init_buffers();
        return fake_buffers[idx];
    }
    return real_mmap(addr, length, prot, flags, fd, offset);
}

int munmap(void *addr, size_t length)
{
    static int (*real_munmap)(void *, size_t) = NULL;
    if (!real_munmap)
        real_munmap = dlsym(RTLD_NEXT, "munmap");

    unsigned char *p = (unsigned char *)addr;
    if (p >= &fake_buffers[0][0] && p <= &fake_buffers[NUM_BUFFERS - 1][FRAME_SIZE - 1])
        return 0; /* static fake buffer; nothing to unmap */
    return real_munmap(addr, length);
}
