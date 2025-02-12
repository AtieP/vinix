ifneq (,)
We only support GNU make.
endif

ifeq ($(origin CC), default)
	CC := cc
endif
ifeq ($(origin LD), default)
	LD := ld
endif
OBJDUMP ?= objdump
V       ?= v
CFLAGS  ?= -O2 -Wall -Wextra -g -pipe
LDFLAGS ?=
VFLAGS  ?=
PROD    ?= false

override INTERNALCFLAGS :=        \
	-ffreestanding                \
	-fno-omit-frame-pointer       \
	-fno-stack-protector          \
	-fno-pic                      \
	-ffunction-sections           \
	-fdata-sections               \
	-mno-80387                    \
	-mno-mmx                      \
	-mno-3dnow                    \
	-mno-sse                      \
	-mno-sse2                     \
	-mno-red-zone                 \
	-mcmodel=kernel               \
	-Wno-address-of-packed-member \
	-Wno-unused-label             \
	-Wno-unused-function          \
	-Wno-unused-variable          \
	-Wno-unused-parameter

override INTERNALLDFLAGS :=  \
	-Tlinker.ld              \
	-nostdlib                \
	-zmax-page-size=0x200000 \
	-static                  \
	-gc-sections

override INTERNALVFLAGS := \
	-os vinix              \
	-enable-globals        \
	-nofloat               \
	-autofree              \
	-d no_backtrace

ifeq ($(PROD), true)
	override INTERNALVFLAGS += -prod
	override INTERNALCFLAGS += -DPROD
endif

override KERNEL := vinix.elf
override VFILES := $(shell find ./ -type f -name '*.v')
override CFILES := $(shell find ./ -type f -name '*.c')
override SFILES := $(shell find ./ -type f -name '*.S')
override COBJ   := $(CFILES:.c=.o) $(SFILES:.S=.o)

.PHONY: all
all: $(KERNEL)

.PHONY: clean
clean:
	rm -rf $(KERNEL) $(COBJ) blob.o blob.c

.PHONY: install
install:
	install -d "$(DESTDIR)$(PREFIX)"
	install -s $(KERNEL) "$(DESTDIR)$(PREFIX)/"

blob.o: $(VFILES)
	VMODULES=/tmp/.vmodules $(V) $(VFLAGS) $(INTERNALVFLAGS) -o blob.c .
	$(CC) -I./c $(CFLAGS) $(INTERNALCFLAGS) -w -c blob.c -o $@

%.o: %.c
	$(CC) -I./c $(CFLAGS) $(INTERNALCFLAGS) -c $< -o $@

%.o: %.S
	$(CC) -I./c $(CFLAGS) $(INTERNALCFLAGS) -c $< -o $@

$(KERNEL): blob.o $(COBJ)
	$(LD) $^ $(LDFLAGS) $(INTERNALLDFLAGS) -o $@
	mv c/symbol_table.c symbol_table.c.tmp
	./gensyms.sh $(OBJDUMP) $@ > c/symbol_table.c
	$(CC) $(CFLAGS) $(INTERNALCFLAGS) -c c/symbol_table.c -o c/symbol_table.o
	$(LD) $^ $(LDFLAGS) $(INTERNALLDFLAGS) -o $@
	mv symbol_table.c.tmp c/symbol_table.c
