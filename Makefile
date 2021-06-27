# V=1 or VERBOSE=1 to print invocations
# DEBUG=1 to build debug build
SOURCES := src/main.c src/ortho.c

Q = $(if $(filter 1,$(V) $(VERBOSE)),,@)

SYSTEM  := $(shell uname -s)
ARCH    := $(shell uname -m)
SRCROOT := $(shell pwd)

CFLAGS := \
	-std=c11 -g -MMD \
	-fcolor-diagnostics -ffile-prefix-map=$(SRCROOT)/= \
	-Wall -Wextra -Wimplicit-fallthrough \
	-Wunused -Wno-missing-field-initializers -Wno-unused-parameter \
	$(CFLAGS)

LDFLAGS := $(LDFLAGS)

ifeq ($(SYSTEM),Darwin)
	OBJCFLAGS := -mmacosx-version-min=10.15 -fobjc-arc
  LDFLAGS += -mmacosx-version-min=10.15 -framework Foundation -framework CoreBluetooth
  SOURCES += src/ortho_mac.m
endif

FLAVOR := release
BIN_SUFFIX :=
ifneq ($(DEBUG),)
	FLAVOR := debug
	BIN_SUFFIX := -debug
	CFLAGS += -DDEBUG=1
else
	CFLAGS += -DNDEBUG
endif

OBJDIR := build/$(FLAVOR)
OBJS   := $(patsubst %,$(OBJDIR)/%.o,$(SOURCES))

all: ortho$(BIN_SUFFIX)

ortho$(BIN_SUFFIX): $(OBJS)
	@echo "link $@"
	$(Q)$(CC) $(LDFLAGS) -o $@ $^

$(OBJDIR)/%.c.o: %.c Makefile
	@echo "cc $<"
	$(Q)mkdir -p "$(dir $@)"
	$(Q)$(CC) $(CFLAGS) -o $@ -c $<

$(OBJDIR)/%.m.o: %.m Makefile
	@echo "cc $<"
	$(Q)mkdir -p "$(dir $@)"
	$(Q)$(CC) $(CFLAGS) $(OBJCFLAGS) -o $@ -c $<

clean:
	rm -rf ortho ortho-debug build

.PHONY: all clean

# .d files
-include ${OBJS:.o=.d}
