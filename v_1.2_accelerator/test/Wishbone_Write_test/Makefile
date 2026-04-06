CC32=riscv32-unknown-elf
CCFLAGS=-march=rv32imf -mabi=ilp32f -ffp-contract=off -mstrict-align -malign-data=xlen -O3 -fno-math-errno -T ../linksc.ld -lm -nostartfiles -ffunction-sections -fdata-sections -Wl,--gc-sections -o wb_regfile_write_test.elf



build:
	$(CC32)-gcc wb_regfile_write_test.c ../crt0.s $(CCFLAGS)
	$(CC32)-objcopy -O binary -j .init -j .text -j .rodata -j .sdata wb_regfile_write_test.elf wb_regfile_write_test.bin
	../rom_generator wb_regfile_write_test.bin
	cp wb_regfile_write_test.data memory_init_tb.mem

