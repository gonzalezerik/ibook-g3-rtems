/*
 * Disk demo for the iBook G3 BSP: mounts the FAT image attached as the
 * secondary IDE drive, reads the file the host put there, writes one
 * back, and unmounts so the host can check both with mtools.
 *
 * run.sh attaches the data image with "-drive if=ide,index=1", which
 * the KeyLargo presents as controller 0, unit 1: /dev/hdb.
 */
#include <rtems.h>
#include <bsp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <rtems/libio.h>
#include <rtems/dosfs.h>

#define DATA_DEVICE "/dev/hdb"
#define MOUNT_POINT "/mnt"

static void rtems_perror(const char *prompt)
{
  printk("%s: %s\n", prompt, strerror(errno));
  exit(1);
}

static void read_host_file(void)
{
  char path[64];
  char buf[256];
  ssize_t n;
  int fd;

  snprintf(path, sizeof(path), "%s/hostfile.txt", MOUNT_POINT);
  fd = open(path, O_RDONLY);
  if (fd < 0) {
    rtems_perror("open hostfile.txt");
  }

  n = read(fd, buf, sizeof(buf) - 1);
  if (n < 0) {
    rtems_perror("read hostfile.txt");
  }
  close(fd);

  buf[n] = '\0';
  printf("read %zd bytes from %s:\n  %s", n, path, buf);
}

static void write_rtems_file(void)
{
  char path[64];
  const char *text = "written by RTEMS on the iBook G3 BSP\n";
  ssize_t n;
  int fd;

  snprintf(path, sizeof(path), "%s/rtems-wrote.txt", MOUNT_POINT);
  fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) {
    rtems_perror("create rtems-wrote.txt");
  }

  n = write(fd, text, strlen(text));
  if (n != (ssize_t) strlen(text)) {
    rtems_perror("write rtems-wrote.txt");
  }

  if (fsync(fd) != 0) {
    rtems_perror("fsync rtems-wrote.txt");
  }
  close(fd);

  printf("wrote %zd bytes to %s\n", n, path);
}

static rtems_task Init(rtems_task_argument arg)
{
  int rv;

  (void) arg;

  printf("\nDisk demo: KeyLargo ATA\n");

  /* RTEMS does not register DOSFS until an application asks for it */
  if (rtems_filesystem_register(
        RTEMS_FILESYSTEM_TYPE_DOSFS, rtems_dosfs_initialize
      ) != 0) {
    rtems_perror("register dosfs");
  }

  rv = mount_and_make_target_path(
    DATA_DEVICE,
    MOUNT_POINT,
    RTEMS_FILESYSTEM_TYPE_DOSFS,
    RTEMS_FILESYSTEM_READ_WRITE,
    NULL
  );
  if (rv != 0) {
    rtems_perror("mount " DATA_DEVICE);
  }
  printf("mounted %s at %s\n", DATA_DEVICE, MOUNT_POINT);

  read_host_file();
  write_rtems_file();

  rv = unmount(MOUNT_POINT);
  if (rv != 0) {
    rtems_perror("unmount");
  }

  printf("=== done ===\n");
  exit(0);
}

#define CONFIGURE_APPLICATION_NEEDS_CLOCK_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_CONSOLE_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_IDE_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_LIBBLOCK
#define CONFIGURE_MAXIMUM_TASKS 4
#define CONFIGURE_MAXIMUM_FILE_DESCRIPTORS 16
/*
 * The ATA driver creates a classic semaphore, message queue and task from
 * its initialization routine. Those need space in the classic object
 * tables; the unlimited allocator keeps them out of the fixed pools.
 */
#define CONFIGURE_UNLIMITED_OBJECTS
#define CONFIGURE_UNIFIED_WORK_AREAS
#define CONFIGURE_RTEMS_INIT_TASKS_TABLE
#define CONFIGURE_INIT
#include <rtems/confdefs.h>
