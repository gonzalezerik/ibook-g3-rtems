/*
 * USB demo for the iBook G3 (ibookg3 BSP) with rtems-libbsd.
 *
 * The Apple KeyLargo OHCI host controller (ohci0) enumerates the bus;
 * this program opens the USB keyboard device node (/dev/ukbd0) and
 * prints the characters it reads.  The run script attaches the
 * emulated keyboard through QEMU's monitor "sendkey" commands, so the
 * round trip is: host monitor -> QEMU OHCI -> FreeBSD ukbd driver ->
 * /dev/ukbd0 -> this program.
 *
 * A USB mass storage device with a FAT partition is also attached by
 * the run script.  The umass driver binds to it, the rtems-libbsd CAM
 * glue creates a block device for it, and the RTEMS media server
 * mounts the partition.  This program reads the file the host put on
 * it, writes a file of its own and unmounts, so that the host can
 * check the written file.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 * Copyright (C) 2026 Erik Gonzalez
 */
#include <rtems.h>
#include <rtems/bdbuf.h>
#include <rtems/bsd/bsd.h>
#include <rtems/media.h>

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* The device tree and driver references for this BSP */
#include <bsp/nexus-devices.h>

/* The run script sends this many keystrokes */
#define KEY_TARGET 5

/* Poll period for the non-blocking read, in milliseconds */
#define READ_POLL_MS 20

/* Mount point of the USB stick partition, set by the media listener */
static char usb_mount[64];

static rtems_id usb_mounted;

static rtems_status_code media_listener(
  rtems_media_event event,
  rtems_media_state state,
  const char *src,
  const char *dest,
  void *arg
)
{
  (void) arg;

  printf(
    "media: %s %s %s%s%s\n",
    rtems_media_event_description(event),
    rtems_media_state_description(state),
    src,
    dest != NULL ? " -> " : "",
    dest != NULL ? dest : ""
  );

  if (
    event == RTEMS_MEDIA_EVENT_MOUNT &&
    state == RTEMS_MEDIA_STATE_SUCCESS &&
    usb_mount[0] == '\0'
  ) {
    strlcpy(usb_mount, dest, sizeof(usb_mount));
    (void) rtems_semaphore_release(usb_mounted);
  }

  return RTEMS_SUCCESSFUL;
}

static void usb_storage_test(void)
{
  rtems_status_code sc;
  char path[128];
  char buf[64];
  FILE *file;
  size_t n;

  sc = rtems_semaphore_obtain(
    usb_mounted,
    RTEMS_WAIT,
    RTEMS_MILLISECONDS_TO_TICKS(60000)
  );
  if (sc != RTEMS_SUCCESSFUL) {
    printf("usb-demo: USB stick not mounted after 60 seconds\n");
    return;
  }

  printf("usb-demo: USB stick mounted at %s\n", usb_mount);

  snprintf(path, sizeof(path), "%s/hostfile.txt", usb_mount);
  file = fopen(path, "r");
  if (file == NULL) {
    printf("usb-demo: cannot open %s: %s\n", path, strerror(errno));
    return;
  }
  n = fread(buf, 1, sizeof(buf) - 1, file);
  fclose(file);
  buf[n] = '\0';
  printf("usb-demo: read %d bytes from USB: %s", (int) n, buf);

  snprintf(path, sizeof(path), "%s/usb-wrote.txt", usb_mount);
  file = fopen(path, "w");
  if (file == NULL) {
    printf("usb-demo: cannot create %s: %s\n", path, strerror(errno));
    return;
  }
  n = fwrite("written by RTEMS over USB\n", 1, 26, file);
  fclose(file);
  printf("usb-demo: wrote %d bytes to USB\n", (int) n);

  if (unmount(usb_mount) == 0) {
    printf("usb-demo: unmounted %s\n", usb_mount);
  } else {
    printf("usb-demo: unmount failed: %s\n", strerror(errno));
  }
}

static rtems_task Init(rtems_task_argument arg)
{
  rtems_status_code sc;
  char text[KEY_TARGET + 1];
  unsigned int polls;
  size_t count;
  ssize_t n;
  int fd;

  (void) arg;

  sc = rtems_semaphore_create(
    rtems_build_name('U', 'S', 'B', 'M'),
    0,
    RTEMS_COUNTING_SEMAPHORE,
    0,
    &usb_mounted
  );
  assert(sc == RTEMS_SUCCESSFUL);

  sc = rtems_bdbuf_init();
  assert(sc == RTEMS_SUCCESSFUL);

  sc = rtems_media_initialize();
  assert(sc == RTEMS_SUCCESSFUL);

  sc = rtems_media_listener_add(media_listener, NULL);
  assert(sc == RTEMS_SUCCESSFUL);

  sc = rtems_media_server_initialize(
    200,
    32 * 1024,
    RTEMS_DEFAULT_MODES,
    RTEMS_DEFAULT_ATTRIBUTES
  );
  assert(sc == RTEMS_SUCCESSFUL);

  sc = rtems_bsd_initialize();
  assert(sc == RTEMS_SUCCESSFUL);

  printf("\nUSB demo: KeyLargo OHCI (ohci0), USB keyboard and storage\n");

  /* Let the callout timer allocate its resources */
  sc = rtems_task_wake_after(2);
  assert(sc == RTEMS_SUCCESSFUL);

  /*
   * Enumeration and the ukbd attach take a few seconds after the BSD
   * kernel starts, so retry the open until the device node exists.
   */
  fd = -1;
  polls = 0;
  while (fd < 0 && polls < 1500) {
    fd = open("/dev/ukbd0", O_RDWR | O_NONBLOCK);
    if (fd < 0) {
      sc = rtems_task_wake_after(RTEMS_MILLISECONDS_TO_TICKS(20));
      assert(sc == RTEMS_SUCCESSFUL);
      ++polls;
    }
  }
  if (fd < 0) {
    printf("usb-demo: no /dev/ukbd0 after 30 seconds\n");
    exit(1);
  }

  printf("usb-demo: keyboard open\n");
  fflush(stdout);

  /*
   * Read the keystrokes.  The run script sends them over the QEMU
   * monitor once it sees the line above, so wait up to 60 seconds.
   */
  count = 0;
  polls = 0;
  while (count < KEY_TARGET && polls < 3000) {
    n = read(fd, &text[count], 1);
    if (n == 1) {
      ++count;
    } else if (n < 0 && errno != EAGAIN && errno != EINTR) {
      printf("usb-demo: read error %d\n", errno);
      break;
    } else {
      sc = rtems_task_wake_after(RTEMS_MILLISECONDS_TO_TICKS(READ_POLL_MS));
      assert(sc == RTEMS_SUCCESSFUL);
      ++polls;
    }
  }
  text[count] = '\0';

  if (count == KEY_TARGET) {
    printf("usb-demo: received %d bytes: %s\n", (int) count, text);
  } else {
    printf("usb-demo: received %d bytes in 60 seconds\n", (int) count);
  }

  close(fd);

  usb_storage_test();

  printf("=== done ===\n");
  exit(0);
}

#define CONFIGURE_APPLICATION_NEEDS_CLOCK_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_CONSOLE_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_LIBBLOCK

#define CONFIGURE_FILESYSTEM_DOSFS

#define CONFIGURE_MAXIMUM_FILE_DESCRIPTORS 32

#define CONFIGURE_MAXIMUM_USER_EXTENSIONS 1

#define CONFIGURE_UNLIMITED_OBJECTS
#define CONFIGURE_UNIFIED_WORK_AREAS

#define RTEMS_BSD_CONFIG_BSP_CONFIG
#define RTEMS_BSD_CONFIG_INIT
#include <machine/rtems-bsd-config.h>

#define CONFIGURE_RTEMS_INIT_TASKS_TABLE

#define CONFIGURE_INIT_TASK_STACK_SIZE (32 * 1024)
#define CONFIGURE_INIT_TASK_INITIAL_MODES RTEMS_DEFAULT_MODES
#define CONFIGURE_INIT_TASK_ATTRIBUTES RTEMS_FLOATING_POINT

#define CONFIGURE_INIT
#include <rtems/confdefs.h>

/* The run-g3.sh machine provides the keyboard; only the driver is here */
SYSINIT_DRIVER_REFERENCE(ukbd, uhub);
