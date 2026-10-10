/*
 * Starter RTEMS application for the iBook G3 (ibookg3 BSP) or psim.
 * Copy this directory to begin a new program.
 */
#include <rtems.h>
#include <stdio.h>
#include <stdlib.h>

static rtems_task Init(rtems_task_argument arg)
{
  (void) arg;

  printf("\nHello from RTEMS on PowerPC\n");

  for (int i = 0; i < 3; ++i) {
    printf("tick %d\n", i);
    rtems_task_wake_after(rtems_clock_get_ticks_per_second());
  }

  exit(0);
}

#define CONFIGURE_APPLICATION_NEEDS_CLOCK_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_CONSOLE_DRIVER
#define CONFIGURE_MAXIMUM_TASKS 4
#define CONFIGURE_UNIFIED_WORK_AREAS
#define CONFIGURE_RTEMS_INIT_TASKS_TABLE
#define CONFIGURE_INIT
#include <rtems/confdefs.h>
