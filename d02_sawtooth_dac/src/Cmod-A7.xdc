## d02_sawtooth_dac — Cmod A7 rev. B constraints

## 12 MHz Clock
set_property -dict { PACKAGE_PIN L17  IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 83.33 -waveform {0 41.66} [get_ports { clk }];

## LED
set_property -dict { PACKAGE_PIN A17  IOSTANDARD LVCMOS33 } [get_ports { led }];

## Pmod Header JA — PmodDA4
set_property -dict { PACKAGE_PIN G17  IOSTANDARD LVCMOS33 } [get_ports { cs_n }];  # JA1
set_property -dict { PACKAGE_PIN G19  IOSTANDARD LVCMOS33 } [get_ports { mosi }];  # JA2
set_property -dict { PACKAGE_PIN L18  IOSTANDARD LVCMOS33 } [get_ports { sclk }];  # JA4
