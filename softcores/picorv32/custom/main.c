#include "../picorv32/firmware/firmware.h"

int main(void)
{
	print_str("usercode: hello from PicoRV32\n");
	print_str("edit picorv32/usercode/main.c and return 0 on success.\n");
	print_str("return any non-zero value to make the testbench fail.\n");
	print_str("lmao this is so funny\n");
	print_str("LLLLL\n");
	return 0;
}
