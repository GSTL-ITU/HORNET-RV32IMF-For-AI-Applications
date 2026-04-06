CC32=riscv32-unknown-elf
CCFLAGS=-march=rv32imf -mabi=ilp32f -ffp-contract=off -mstrict-align -malign-data=xlen -O3 -fno-math-errno -T ../linksc.ld -lm -nostartfiles -ffunction-sections -fdata-sections -Wl,--gc-sections -o acc_while_test.elf



build:
	$(CC32)-gcc acc_while_test.c ../crt0.s $(CCFLAGS)
	$(CC32)-objcopy -O binary -j .init -j .text -j .rodata -j .sdata acc_while_test.elf acc_while_test.bin
	../rom_generator acc_while_test.bin
	cp acc_while_test.data memory_init_tb.mem

