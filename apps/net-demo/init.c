/*
 * Network demo for the iBook G3 (ibookg3 BSP) with rtems-libbsd.
 *
 * Brings up the UniNorth GMAC (FreeBSD gem driver), gets an address
 * from the QEMU user networking DHCP server, pings the gateway, and
 * then serves or makes one TCP connection so both directions of the
 * TCP stack are exercised.  The run script attaches the guest with
 * hostfwd ports and drives the host side through them.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 * Copyright (C) 2026 Erik Gonzalez
 */
#include <rtems.h>
#include <rtems/bsd/bsd.h>
#include <rtems/dhcpcd.h>
#include <machine/rtems-bsd-commands.h>

#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

/* The device tree and driver references for this BSP */
#include <bsp/nexus-devices.h>

#define TCP_SERVE_PORT 7007
#define TCP_FETCH_PORT (TCP_SERVE_PORT + 1)
#define TCP_ECHO_REPLY "hello from rtems\n"

static volatile bool dhcpcd_bound = false;

/*
 * The dhcpcd hook gets one call per client event with the script
 * environment: "reason=BOUND", "interface=gem0", "ip_address=...".
 */
static void
dhcpcd_hook_handler(rtems_dhcpcd_hook *hook, char *const *env)
{
  (void) hook;

  while (*env != NULL) {
    printf("dhcpcd: %s\n", *env);
    if (strcmp(*env, "reason=BOUND") == 0) {
      dhcpcd_bound = true;
    }
    ++env;
  }
}

static rtems_dhcpcd_hook dhcpcd_hook = {
  .name = "netdemo",
  .handler = dhcpcd_hook_handler
};

/*
 * A short configuration so dhcpcd sends a stable client identifier to
 * the QEMU user networking DHCP server.
 */
static void
write_dhcpcd_conf(void)
{
  static const char conf[] = "clientid netdemo\n";
  ssize_t n;
  int fd;
  int rv;

  fd = open(
    "/etc/dhcpcd.conf",
    O_CREAT | O_WRONLY,
    S_IRWXU | S_IRWXG | S_IRWXO
  );
  assert(fd >= 0);

  n = write(fd, conf, sizeof(conf) - 1);
  assert(n == (ssize_t) (sizeof(conf) - 1));

  rv = close(fd);
  assert(rv == 0);
}

/*
 * Serve one connection on TCP_SERVE_PORT (the up direction: the host
 * connects in through a hostfwd port), echoing a greeting.
 */
static void
tcp_serve_once(void)
{
  struct timeval timeout;
  struct sockaddr_in addr;
  char buf[64];
  ssize_t n;
  int lfd;
  int cfd;

  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  addr.sin_port = htons(TCP_SERVE_PORT);

  lfd = socket(AF_INET, SOCK_STREAM, 0);
  assert(lfd >= 0);
  assert(bind(lfd, (struct sockaddr *) &addr, sizeof(addr)) == 0);
  assert(listen(lfd, 1) == 0);

  printf("net-demo: listening on port %d\n", TCP_SERVE_PORT);

  /*
   * A host connect can land on the forwarder just as listen() starts
   * and arrive with no data, so accept until a connection carries the
   * request line.
   */
  timeout.tv_sec = 2;
  timeout.tv_usec = 0;
  for (;;) {
    cfd = accept(lfd, NULL, NULL);
    assert(cfd >= 0);
    setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    n = read(cfd, buf, sizeof(buf) - 1);
    if (n > 0) {
      break;
    }
    close(cfd);
  }
  buf[n] = '\0';
  printf("net-demo: got %d bytes: %s\n", (int) n, buf);

  n = write(cfd, TCP_ECHO_REPLY, strlen(TCP_ECHO_REPLY));
  printf("net-demo: sent %d bytes\n", (int) n);

  close(cfd);
  close(lfd);
}

/*
 * Connect to the host's TCP port reachable through the 10.0.2.2
 * user networking alias and fetch one line (the down direction).
 */
static void
tcp_fetch_once(void)
{
  struct sockaddr_in addr;
  char buf[64];
  ssize_t n;
  int fd;

  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = inet_addr("10.0.2.2");
  addr.sin_port = htons(TCP_FETCH_PORT);

  fd = socket(AF_INET, SOCK_STREAM, 0);
  assert(fd >= 0);
  printf("net-demo: connecting to 10.0.2.2:%d\n", TCP_FETCH_PORT);
  assert(connect(fd, (struct sockaddr *) &addr, sizeof(addr)) == 0);

  n = read(fd, buf, sizeof(buf) - 1);
  if (n > 0) {
    buf[n] = '\0';
    printf("net-demo: fetched %zd bytes: %s", n, buf);
  }

  close(fd);
}

static rtems_task Init(rtems_task_argument arg)
{
  rtems_status_code sc;
  char *ifup[] = { "ifconfig", "gem0", "up", NULL };
  char *show[] = { "ifconfig", "gem0", NULL };
  char *ping[] = {
    "ping", "-c", "3", "10.0.2.2", NULL
  };
  unsigned int timeout;
  int exit_code;

  (void) arg;

  sc = rtems_bsd_initialize();
  assert(sc == RTEMS_SUCCESSFUL);

  printf("\nNetwork demo: UniNorth GMAC (gem0), QEMU user networking\n");

  /* Let the callout timer allocate its resources */
  sc = rtems_task_wake_after(2);
  assert(sc == RTEMS_SUCCESSFUL);

  exit_code = rtems_bsd_ifconfig_lo0();
  assert(exit_code == 0);

  exit_code = rtems_bsd_command_ifconfig(RTEMS_BSD_ARGC(ifup), ifup);
  if (exit_code != 0) {
    printf("net-demo: ifconfig gem0 up exited with %d\n", exit_code);
  }

  write_dhcpcd_conf();
  rtems_dhcpcd_add_hook(&dhcpcd_hook);

  sc = rtems_dhcpcd_start(NULL);
  assert(sc == RTEMS_SUCCESSFUL);

  timeout = 40;
  while (!dhcpcd_bound && timeout > 0) {
    sleep(1);
    --timeout;
  }
  if (!dhcpcd_bound) {
    printf("net-demo: no DHCP lease after 40 seconds\n");
  }

  /* Report what we got */
  (void) rtems_bsd_command_ifconfig(RTEMS_BSD_ARGC(show), show);

  /* The user networking gateway answers ping */
  exit_code = rtems_bsd_command_ping(RTEMS_BSD_ARGC(ping), ping);
  printf("net-demo: ping 10.0.2.2 exit %d\n", exit_code);

  /* TCP both directions; the host side is driven by run.sh */
  tcp_serve_once();
  tcp_fetch_once();

  printf("=== done ===\n");
  exit(0);
}

#define CONFIGURE_APPLICATION_NEEDS_CLOCK_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_CONSOLE_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_LIBBLOCK

#define CONFIGURE_MAXIMUM_FILE_DESCRIPTORS 64

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
