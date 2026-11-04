PS5_HOST ?= 192.168.0.125
PS5_PORT ?= 9021
include $(PS5_PAYLOAD_SDK)/toolchain/prospero.mk
CFLAGS := -Wall -O1
ELF := ncdt_oracle.elf ncdt_oracle_server.elf
all: $(ELF)
ncdt_oracle.elf: main.c
	$(CC) $(CFLAGS) -o $@ $<
ncdt_oracle_server.elf: server.c
	$(CC) $(CFLAGS) -o $@ $<
clean:
	rm -f *.o *.elf
test: $(ELF)
	cat $(ELF) | nc $(PS5_HOST) $(PS5_PORT)
