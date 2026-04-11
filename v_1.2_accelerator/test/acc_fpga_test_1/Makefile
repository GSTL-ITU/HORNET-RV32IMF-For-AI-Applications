CC32=riscv32-unknown-elf
CCFLAGS=-march=rv32imf -mabi=ilp32f -ffp-contract=off -mstrict-align -malign-data=xlen -O3 -fno-math-errno -T ../linksc.ld -lm -nostartfiles -ffunction-sections -fdata-sections -Wl,--gc-sections -o inference_acc.elf



build:
	$(CC32)-gcc inference_acc.c ../../drivers/uart.c ../../drivers/irq.c ../crt0.s $(CCFLAGS)
	$(CC32)-objcopy -O binary -j .init -j .text -j .rodata -j .sdata inference_acc.elf inference_acc.bin
	../rom_generator inference_acc.bin
	cp inference_acc.data memory_init.mem


comp:
	gcc inference_acc.c -lm -o inference_acc