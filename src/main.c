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
  Ortho* ortho = ortho_create(malloc, free);
  if (!ortho) {
    return 1;
  }
  ortho_runloop(ortho, onmsg, NULL);
  ortho_free(ortho);
  return 0;
}
