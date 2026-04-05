# ──────────────────────────────────────────────────────────────────────────
# SoCLabs Ethernet MAC — C Driver Build & Generation
# ──────────────────────────────────────────────────────────────────────────

RDL2C       := python3 ../../scripts/rdl2c.py
RDL_DIR     := ../rdl
OUT_DIR     := .

CC          := arm-none-eabi-gcc
CFLAGS      := -mcpu=cortex-m0 -mthumb -Wall -Wextra -Werror -I.

GENERATED_HEADERS := $(OUT_DIR)/ethmac_regs.generated.h

SRCS := ethmac.c
OBJS := $(SRCS:.c=.o)

.PHONY: all generate compile clean

all: generate compile

generate: $(GENERATED_HEADERS)

compile: generate $(OBJS)

clean:
	rm -f $(GENERATED_HEADERS) $(OBJS)

$(OUT_DIR)/ethmac_regs.generated.h: $(RDL_DIR)/ethmac_regs.rdl
	$(RDL2C) $< -o $@

%.o: %.c $(GENERATED_HEADERS)
	$(CC) $(CFLAGS) -c $< -o $@
