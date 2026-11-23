/*
 * Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
 * See the file COPYING for copying conditions.
 */

/* AI-Assisted */

/*
 * Regression test for build_input_path() in emerg-shutdown.c.
 *
 * Guards the latent overflow CodeQL flagged as cpp/unsafe-strcat: the input
 * device path was built by strcat-ing a decimal index (up to 10 digits for a
 * uint32_t) onto "/dev/input/event" in a fixed 20-byte buffer. An index whose
 * decimal form did not fit overran the buffer. build_input_path() must stay
 * bounded by the caller's buffer size for every index.
 *
 * Buffers are malloc'd at exactly (or one below) the required size so
 * AddressSanitizer red-zones catch any out-of-bounds write - a naive
 * strcpy+strcat implementation aborts here under ASan.
 *
 * EMERG_SHUTDOWN_NO_MAIN compiles the daemon's translation unit without its
 * main() so this test can call the helper directly against the real code.
 */

#define EMERG_SHUTDOWN_NO_MAIN
#include "emerg-shutdown.c"

#include <stdio.h>
#include <string.h>

static int failures = 0;

/* Index whose rendering fits exactly: expect success and exact string. */
static void expect_ok(uint32_t idx, const char *want) {
  size_t need = strlen(want) + 1;
  char *buf = malloc(need);
  if (buf == NULL) {
    fprintf(stderr, "FAIL: malloc(%zu) failed\n", need);
    failures++;
    return;
  }
  if (!build_input_path(buf, need, idx)) {
    fprintf(stderr, "FAIL: idx %u rejected by exact-fit %zu-byte buffer\n",
      idx, need);
    failures++;
  } else if (strcmp(buf, want) != 0) {
    fprintf(stderr, "FAIL: idx %u produced '%s', want '%s'\n", idx, buf, want);
    failures++;
  } else {
    printf("PASS: idx %u -> '%s'\n", idx, want);
  }
  free(buf);
}

/* Buffer one byte too small: expect rejection with no write past the buffer. */
static void expect_reject(uint32_t idx, size_t bufsize) {
  char *buf = malloc(bufsize);
  if (buf == NULL) {
    fprintf(stderr, "FAIL: malloc(%zu) failed\n", bufsize);
    failures++;
    return;
  }
  memset(buf, 'A', bufsize);
  if (build_input_path(buf, bufsize, idx)) {
    fprintf(stderr, "FAIL: idx %u accepted into %zu-byte buffer (too small)\n",
      idx, bufsize);
    failures++;
  } else {
    printf("PASS: idx %u rejected for %zu-byte buffer\n", idx, bufsize);
  }
  free(buf);
}

int main(void) {
  /* "/dev/input/event" is 16 chars; +digits +NUL must fit. */
  expect_ok(0, "/dev/input/event0");
  expect_ok(9, "/dev/input/event9");
  expect_ok(10, "/dev/input/event10");
  expect_ok(255, "/dev/input/event255");             /* old loop cap */
  expect_ok(4294967295U, "/dev/input/event4294967295"); /* UINT32_MAX: 26 chars */

  /* idx 100 needs 16 + 3 + 1 = 20 bytes. */
  expect_reject(100, 19);
  /* UINT32_MAX needs 16 + 10 + 1 = 27 bytes. */
  expect_reject(4294967295U, 26);

  if (failures != 0) {
    fprintf(stderr, "%d assertion(s) failed\n", failures);
    return 1;
  }
  printf("all build_input_path assertions passed\n");
  return 0;
}
