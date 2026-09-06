
#include <stdio.h>
#include "platform.h"
#include "xparameters.h"
#include "xil_io.h"


int main()
{

	unsigned char sw_values;

	while(1){
		sw_values = Xil_In8(XPAR_MYAXI4LITE_SWLED_0_S00_AXI_BASEADDR);
		Xil_Out8(XPAR_MYAXI4LITE_SWLED_0_S00_AXI_BASEADDR+4, sw_values);
	}
}
