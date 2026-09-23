CAN to SPI Bridge (FPGA RTL)

 Overview

This repository contains a Verilog-based RTL architecture that bridges a Controller Area Network (CAN) bus to a Serial Peripheral Interface (SPI).
Designed and tested on the Intel DE10-Lite (MAX 10 - 10M50DAF484C7G) FPGA, this system ingests a 500 kbps serial CAN frame, validates the data (CRC and EOF), packages the identifier and payload into a 112-bit parallel register, and transmits it serially via an SPI Master interface.

System Architecture and Data Flow

The bridge operates through three distinct hardware phases:

1. CAN Frame Ingestion: The `can_controller` state machine parses the incoming serial CAN bitstream (500 kbps) via the `can_rx` pin. It actively calculates the CRC-15 and handles bit-stuffing logic.
2.Parallel Assembly: Upon successful End of Frame (EOF) validation, the parsed CAN ID, Data Length Code (DLC), and payload are packaged into a single 112-bit internal parallel register (`spi_rx_packet`).
3. SPI Transmission: Once the parallel packet is assembled, the SPI master activates the Chip Select (`cs_n`), pulses the SPI Clock (`sck`), and shifts the 112-bit payload out serially over the `mosi` pin.

## Module Breakdown

* `can_spi_master_top.v` - The top-level wrapper that connects the physical FPGA pins to the internal bridge logic.
* `can_controller.v` - The FSM that handles the CAN protocol parsing, idle state detection, CRC validation, and EOF checking.
* `can_generator.v` - An internal hardware bypass module. It acts as an on-chip test pattern generator that injects a pre-recorded, perfectly timed CAN frame directly into the controller, triggered by a physical slide switch.

Hardware Requirements

* Board: Terasic DE10-Lite (Intel MAX 10 FPGA)
* Target Device: 10M50DAF484C7G
* Clock: 50 MHz internal oscillator

Pin Assignments (DE10-Lite)

| Signal Name | FPGA Pin | Board Component / I/O Standard |
| --- | --- | --- |
| `clk_50mhz` | `PIN_P11` | 50 MHz MAX 10 Clock (3.3-V LVTTL) |
| `rst_n` | `PIN_B8` | KEY[0] Push Button (3.3-V LVTTL) |
| `can_rx` | `PIN_V10` | GPIO Expansion Header (3.3-V LVTTL) |
| `mosi` | `PIN_V9` | GPIO Expansion Header (3.3-V LVTTL) |
| `cs_n` | `PIN_W9` | GPIO Expansion Header (3.3-V LVTTL) |
| `sck` | `PIN_W10` | GPIO Expansion Header (3.3-V LVTTL) |
| `test_switch` | `PIN_C10` | SW[0] Slide Switch (Internal test trigger) |

 Simulation and Verification

This project has been verified using both RTL Simulation (for mathematical and state machine validation) and
Gate-Level Simulation (GLS) (for physical timing, synthesis mapping, and propagation delay validation).


2. Open Signal Tap and set the trigger to `cs_n` (Falling Edge).
3. Flick `SW[0]` on the board to activate the `can_generator.v` module.
4. The internal generator will feed a simulated 500 kbps CAN frame to the controller, allowing Signal Tap to capture the resulting SPI output on `mosi` and `sck`.
