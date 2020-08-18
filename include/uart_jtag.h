`ifndef _UART_JTAG_H_
`define _UART_JTAG_H_

// generic libraries and function
// n/a

// configurations
`define UART_JTAG_N_BYTES_PER_PACKET 		4
`define UART_JTAG_BW_BYTES_PER_PACKET 		2
`define UART_JTAG_BW_PACKET 				8*`UART_JTAG_N_BYTES_PER_PACKET

// ip files
`include "../ip/uart_jtag_uart_0.v"

// source files
`include "../src/uart_jtag_driver.v"

`endif