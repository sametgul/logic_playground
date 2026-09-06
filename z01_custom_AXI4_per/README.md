# Custom AXI4-Lite IP: Switches → LEDs

This walkthrough packages a custom AXI4-Lite peripheral in Vivado, wires it to
board switches and LEDs, and drives it from a bare-metal application in Vitis.
The peripheral exposes 4 registers over AXI4-Lite; the design only uses two of
them: `reg0` (read-only, switch values) and `reg1[7:0]` (write, LED values).

**Source files:**
- [src/myAXI4lite_swled_v1_0_S00_AXI.vhd](src/myAXI4lite_swled_v1_0_S00_AXI.vhd) — AXI4-Lite slave logic (register read/write, reg0/reg1 wiring)
- [src/myAXI4lite_swled_v1_0.vhd](src/myAXI4lite_swled_v1_0.vhd) — top-level wrapper adding `sw_i`/`led_o` ports
- [src/helloworld.c](src/helloworld.c) — Vitis application

## 1. Create the IP

**Tools → Create and Package New IP**

![Create and Package New IP](images/create_and_package_ip.png)

Choose **Create a new AXI4 Peripheral**. Give it a name and a location — pick
a dedicated folder to hold your custom IPs, since Vivado will later point at
this folder as an IP repository. A description is optional.

![New AXI4 peripheral name and location](images/new_axi4_peripheral.png)

## 2. Configure the interface

![Interface configuration](images/interface_config.png)

- **Interface Type:** Lite
- **Interface Mode:** Slave
- **Number of Registers:** 4 (the minimum)

Interface type matters here:
- **Lite** — simple memory-mapped registers, no burst support. Used for this design.
- **Full** — backed by a BRAM, supports burst transactions.
- **Stream** — no addressing at all; data flows as a continuous stream (AXI4-Stream).

Click **Create Peripheral**, then check **Edit IP** on the finish screen so
the generated IP project opens immediately for editing.

## 3. Edit the IP source

The IP project opens with the generated AXI4-Lite slave template.

![Generated IP project](images/generated_ip_project.png)

Only I/O ports were added to the top-level entity; the register read/write
logic already comes from the Xilinx template.

![Added IO ports](images/added_io_ports.png)

Since `reg0` is used to read switch values, the PS must never write to it.
All write logic touching `slv_reg0` is commented out in the generated write
process (see the `when b"00"` case and reset branch in
[myAXI4lite_swled_v1_0_S00_AXI.vhd](src/myAXI4lite_swled_v1_0_S00_AXI.vhd)),
so `reg0` is effectively read-only from the AXI side.

![reg0 write logic disabled](images/reg0_write_disabled.png)

The functional wiring, added at the end of the same file's architecture body:
- `slv_reg0` ← switch inputs (driven combinationally from `reg0_i`, not AXI writes)
- `slv_reg1[7:0]` → LED outputs (`reg1_o`, written by the PS over AXI)

![Register-to-port wiring](images/register_port_wiring.png)

## 4. Update the wrapper

The wrapper file, [myAXI4lite_swled_v1_0.vhd](src/myAXI4lite_swled_v1_0.vhd),
only adds the new I/O ports (`sw_i`, `led_o`) and connects them through to the
underlying AXI4-Lite subentity — its component instantiation/generic map has
to be updated to match.

![Wrapper file port connections](images/wrapper_ports.png)

## 5. Synthesize and package

Run **Synthesis** first to catch structural errors before packaging — a
malformed interface definition is much easier to debug at this stage than
after the IP is packaged and instantiated in a block design. Once synthesis
is clean, click **Package IP**.

![Synthesize then Package IP](images/synthesize_package_ip.png)

## 6. Add the IP repository to your project

In the target project (not the IP project): **Settings → IP → Repository →
add the IP folder** chosen in step 1. Vivado indexes IPs there, and the new
peripheral becomes searchable in the block design's **Add IP** dialog.

![Add IP repository](images/add_ip_repository.png)

## 7. Edit the IP later (if needed)

Right-click the IP block in the block design → **Edit in IP Packager**. This
reopens the same IP project from step 3. After making changes, **Re-Package
IP** and refresh/upgrade the IP in the block design.

![Edit in IP Packager](images/edit_in_ip_packager.png)

## 8. Wire up the block design

Run **Block Automation** and **Connection Automation**, then **Create HDL
Wrapper** for the block design. Add an XDC constraints file that maps the
`switches` and `led_o` ports to the physical pins for your board, matching
the I/O standard and voltage of the switches/LEDs used.

![Completed block design](images/completed_block_design.png)

## 9. Export hardware and build the application

**File → Export Hardware → Fixed**, include the bitstream, and save the
`.xsa` file.

Launch **Vitis IDE** from Tools and create an application project against
that `.xsa`, following the same steps as the previous project in this repo.

## 10. Find the register addresses

Vitis generates a `xparameters.h` under the BSP with the base address of
every peripheral in the design:

![xparameters.h location](images/xparameters_location.png)

The generated address for this custom peripheral:

![Address assignment in xparameters.h](images/address_assignment.png)

## 11. Application code

Full source: [src/helloworld.c](src/helloworld.c)

`Xil_In8` reads an 8-bit value from a memory-mapped address.
`Xil_Out8` writes an 8-bit value to a memory-mapped address.

```c
#include <stdio.h>
#include "platform.h"
#include "xparameters.h"
#include "xil_io.h"

int main()
{
    unsigned char sw_values;

    while (1) {
        sw_values = Xil_In8(XPAR_MYAXI4LITE_SWLED_0_S00_AXI_BASEADDR);
        Xil_Out8(XPAR_MYAXI4LITE_SWLED_0_S00_AXI_BASEADDR + 4, sw_values);
    }
}
```

`BASEADDR` is `reg0` (switches, offset `0x0`). `BASEADDR + 4` is `reg1`
(LEDs, offset `0x4`) — AXI4-Lite registers are word-addressed 4 bytes apart.

## References

1. [Mehmet Burak Aykenar – GitHub](https://github.com/mbaykenar/zynq-soc-hw-sw-design)

