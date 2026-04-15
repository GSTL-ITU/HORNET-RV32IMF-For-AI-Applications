CC32=riscv32-unknown-elf
CCFLAGS=-march=rv32imf -mabi=ilp32f -ffp-contract=off -mstrict-align -malign-data=xlen -O3 -fno-math-errno -T ../linksc.ld -lm -nostartfiles -ffunction-sections -fdata-sections -Wl,--gc-sections -o acc_fpga_uart_tx_only.elf



build:
	$(CC32)-gcc acc_fpga_uart_tx_only.c ../../drivers/uart.c ../../drivers/gpio.c ../crt0.s $(CCFLAGS)
	$(CC32)-objcopy -O binary -j .init -j .text -j .rodata -j .sdata acc_fpga_uart_tx_only.elf acc_fpga_uart_tx_only.bin
	../rom_generator acc_fpga_uart_tx_only.bin
	cp acc_fpga_uart_tx_only.data memory_init.mem


comp:
	gcc acc_fpga_uart_tx_only.c -lm -o acc_fpga_uart_tx_only