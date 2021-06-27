# ortho-remote

C program for reading values from the Teenage Engineering Ortho Remote.

- Currently only implemented for macOS
- Puts the remote into MIDI mode which means it has a fixed range of values

### Usage

Either build and run the provided `ortho` program
or copy the source files in `src` into your project and use the `ortho.h` interface.

### Example

```c
#include "ortho.h"
#include <stdlib.h> // malloc & free
#include <stdio.h>  // printf

static void onmsg(const OrthoMsg* msg, void* userdata) {
  switch (msg->ev) {
    case ORTHO_RESTING: printf("button is up\n"); break;
    case ORTHO_PRESSED: printf("button is down\n"); break;
    case ORTHO_VALUE:   printf("value %f\n", msg->value); break;
    default:            printf("%s\n", ortho_event_name(msg->ev));
  }
}

int main(int argc, char *argv[]) {
  Ortho* ortho = ortho_create(malloc);
  if (!ortho) {
    return 1;
  }
  ortho_runloop(ortho, onmsg, NULL);
  ortho_free(ortho, free);
  return 0;
}

```

Build & run:

```sh
$ make
$ ./ortho
CONNECT
button is up
value 0.007874
value 0.000000
value 0.007874
value 0.015748
value 0.023622
value 0.031496
button is down
value 0.039370
value 0.047244
button is up
value 0.055118
...
```
