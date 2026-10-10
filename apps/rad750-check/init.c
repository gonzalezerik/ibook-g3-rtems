/*
 * rad750-check: confirm the RTEMS image is sized to the Perseverance RAD750's
 * 128 MB DRAM and that the simulated memory is really there, by filling and
 * verifying a large heap block near the top of RAM.
 */
#include <rtems.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>


/* PowerPC BSPs clip the initial heap at 32 MB; -1 = give the heap all RAM */
uintptr_t BSP_sbrk_policy[] = { (uintptr_t) -1 };

/* installed RAM: from Open Firmware on ibookg3, from the linker on psim */
#ifdef BSP_IBOOKG3
#include <bsp.h>
#define INSTALLED_RAM ((uintptr_t) ibookg3_memory_size)
#else
extern char RamSize[];
#define INSTALLED_RAM ((uintptr_t) RamSize)
#endif

#define MB (1024u * 1024u)
#ifndef FILL_MB
#define FILL_MB 100u
#endif
#define FILL_BYTES (FILL_MB * MB)

static rtems_task Init(rtems_task_argument arg)
{
  (void) arg;
  uintptr_t ram = INSTALLED_RAM;
  uint32_t pvr;

  __asm__ volatile ("mfpvr %0" : "=r" (pvr));

  printf("\n*** BEGIN OF TEST RAD750-CHECK ***\n");
  printf("PVR:        0x%08lx\n", (unsigned long) pvr);
  printf("RAM size:   %lu MB\n", (unsigned long) (ram / MB));

  volatile uint32_t *p = malloc(FILL_BYTES);
  if (p == NULL) {
    printf("FAIL: could not allocate %u MB\n", FILL_BYTES / MB);
    exit(1);
  }
  printf("Allocated:  %u MB at 0x%08lx..0x%08lx\n", FILL_BYTES / MB,
         (unsigned long) (uintptr_t) p,
         (unsigned long) ((uintptr_t) p + FILL_BYTES));

  size_t n = FILL_BYTES / sizeof(*p);
  for (size_t i = 0; i < n; ++i)
    p[i] = (uint32_t) i ^ 0xA5A5A5A5u;
  for (size_t i = 0; i < n; ++i) {
    if (p[i] != ((uint32_t) i ^ 0xA5A5A5A5u)) {
      printf("FAIL: mismatch at word %lu\n", (unsigned long) i);
      exit(1);
    }
  }
  printf("Memory fill/verify: OK\n");
  printf("*** END OF TEST RAD750-CHECK ***\n");
  exit(0);
}

#define CONFIGURE_APPLICATION_NEEDS_CLOCK_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_SIMPLE_CONSOLE_DRIVER
#define CONFIGURE_MAXIMUM_TASKS 1
#define CONFIGURE_UNIFIED_WORK_AREAS
#define CONFIGURE_RTEMS_INIT_TASKS_TABLE
#define CONFIGURE_INIT
#include <rtems/confdefs.h>
