`ifndef _UART_JTAG_DRIVER_V_
`define _UART_JTAG_DRIVER_V_

`include "../include/uart_jtag.h"

module uart_jtag_driver #(
	parameter BYTES_PER_PACKET 		= 0,
	parameter BW_BYTES_PER_PACKET 	= 0,
	parameter BW_PACKET 			= 0
)(
	// general ports
	input 						clock_i, 	 		// uart_jtag and driver clock (must be at least speed of jtag Tclk)	
	input 						resetn_i, 			// reset active low
	// host2client buffer ports
	input 						full_i, 			// 0: can write to buffer, 1: cannot write to buffer
	output 						write_o, 			// if (1) -> write item to buffer
	output 	[BW_PACKET-1:0]		data_o, 			// data to write to buffer
	// client2host buffer ports
	input 						empty_i,  			// 0: can read buffer, 1: cannot read buffer
	output 						read_o, 			// if (1) -> point to next buffered item
	input 	[BW_PACKET-1:0]	 	data_i  			// data bus from buffer
);

// jtag port hardware
// -------------------------------------------------------------------------------------------------------------------------------
reg 					uart_jtag_rx_reg, 			// logic low to receive data
						uart_jtag_tx_reg; 			// logic low to transmit data
wire 	[BW_PACKET-1:0] uart_jtag_rx_data_bus; 		// data being received from host
reg 	[BW_PACKET-1:0] uart_jtag_tx_data_reg; 		// data being sent to host
wire 					uart_jtag_rx_ready_flag, 	// logic high if data can be received from host
						uart_jtag_tx_ready_flag; 	// logic high if data can be sent to host

uart_jtag_uart_0 uart_jtag_inst (
	.av_address		(1'b0 						),	// zero for data, 1 for interrupt (ignore interrupt)
	.av_chipselect	(resetn_i 					),	// 1 to enable jtag
	.av_read_n		(uart_jtag_rx_reg 			),		
	.av_write_n		(uart_jtag_tx_reg 			),
	.av_writedata	(uart_jtag_tx_data_reg		),
	.clk 			(clock_i 					),					
	.rst_n			(resetn_i 					),	// reset active low
   	.av_irq 		( 							),	// unused - goes high if internal fifo is full
   	.av_readdata	(uart_jtag_rx_data_bus		), 	// rx data
   	.av_waitrequest	( 							),	// unused - jtag_uart out-of-reset wait
   	.dataavailable 	(uart_jtag_rx_ready_flag 	),	// 1: data in rx fifo
   	.readyfordata 	(uart_jtag_tx_ready_flag 	)	// 1: tx fifo full
);


// uart controller state machine
// -------------------------------------------------------------------------------------------------------------------------------

// state machine parameterizations
localparam ST_IDLE 		=	2'b00;
localparam ST_RECEIVE 	=	2'b01;
localparam ST_TRANSMIT 	=	2'b10;
localparam ST_WRITEOUT	=	2'b11;
localparam ACTIVE 		= 	1'b0;
localparam NONACTIVE 	= 	1'b1;

// sequencing signals
reg [1:0]						state_reg,  			// sequencing control
								state_next_reg; 		// sequencing control
reg 		 					delay_counter_reg;  	// sequencing control
reg								switch_flag_reg; 		// byte transfer sequencing control
reg [BW_BYTES_PER_PACKET-1:0]	byte_counter_reg; 		// byte transfer sequencing control

// data signals
reg 							read_reg,  				// read-in from client
								write_reg; 				// write-out to client
reg [BW_PACKET-1:0]				write_data_reg; 		// data to write-out to client

assign read_o 	= read_reg;
assign write_o 	= write_reg;
assign data_o 	= write_data_reg;

// uart_jtag_driver controller logic
always @(posedge clock_i) begin
	// synchronous reset state
	if (!resetn_i) begin
		// sequencing signals
		state_reg 				<= ST_IDLE;
		state_next_reg 			<= ST_TRANSMIT;
		delay_counter_reg 		<= 1'b0;
		switch_flag_reg 		<= 1'b0;
		byte_counter_reg 		<= 'b0;
		// data signals
		read_reg 				<= 1'b0;
		write_reg 				<= 1'b0;
		write_data_reg 			<= 'b0;
		uart_jtag_rx_reg 		<= NONACTIVE;
		uart_jtag_tx_reg 		<= NONACTIVE;
		uart_jtag_tx_data_reg 	<= 'b0;
	end
	// active sequencing states
	else begin

		// default signals
		read_reg 			<= 1'b0;
		write_reg 			<= 1'b0;
		uart_jtag_tx_reg 	<= NONACTIVE;
		uart_jtag_rx_reg 	<= NONACTIVE;

		// delay counter
		if (delay_counter_reg) delay_counter_reg <= delay_counter_reg - 1'b1;
		else begin
			// state machine sequencing
			case(state_reg)

				// 
				ST_IDLE: begin	
					// uart_jtag has data to receive and read-in buffer has data to send
					// prevent a priority lock by using an explicit next state
					if (!empty_i & uart_jtag_rx_ready_flag) begin
						state_reg 				<= ST_TRANSMIT;
						state_next_reg 			<= ST_RECEIVE;
					end
					// uart_jtag has data to receive only
					else if (uart_jtag_rx_ready_flag) begin
						state_reg 				<= ST_RECEIVE;
						state_next_reg 			<= ST_IDLE;
					end
					// read-in buffer has data to send only
					else if (!empty_i) begin
						uart_jtag_tx_data_reg 	<= data_i;
						read_reg 				<= 1'b1;
						state_reg 				<= ST_TRANSMIT;
						state_next_reg 			<= ST_IDLE;
					end
				end

				// serially read one byte per transaction cycle from the uart_jtag receiver
				ST_RECEIVE: begin
					if (uart_jtag_rx_ready_flag) begin
						case(switch_flag_reg)
							1'b0: begin
								uart_jtag_rx_reg 		<= ACTIVE;
								switch_flag_reg 		<= 1'b1;
								delay_counter_reg 		<= 1'b1;
								
							end
							1'b1: begin
								switch_flag_reg 		<= 1'b0;
								write_data_reg 			<= {write_data_reg[23:0], uart_jtag_rx_data_bus[7:0]};

								// if entire packet received then continue sequencing, else repeat
								if (byte_counter_reg == (BYTES_PER_PACKET-1)) begin
									byte_counter_reg 	<= 'b0;
									state_reg 			<= ST_WRITEOUT;
								end
								else begin
									byte_counter_reg 	<= byte_counter_reg + 1'b1;
								end
							end
						endcase
					end
				end

				// serially send one byte per transaction cycle to the uart_jtag receiver
				ST_TRANSMIT: begin
					// wait until hardware is ready to send
					if (uart_jtag_tx_ready_flag & uart_jtag_rx_data_bus[13]) begin	
						case(switch_flag_reg)
							1'b0: begin
								uart_jtag_tx_reg 		<= ACTIVE;
								switch_flag_reg 		<= 1'b1;
								delay_counter_reg 		<= 1'b1;
							end
							1'b1: begin
								switch_flag_reg 		<= 1'b0;
								uart_jtag_tx_data_reg 	<= uart_jtag_tx_data_reg >> 8;

								// if entire word transferred then continue sequencing, else repeat
								if (byte_counter_reg == (BYTES_PER_PACKET-1)) begin
									byte_counter_reg 	<= 2'b00;
									state_reg 			<= state_next_reg;
								end
								else begin
									byte_counter_reg 	<= byte_counter_reg + 1'b1;
								end
							end
						endcase
					end
				end

				// wirte-out received data to the client
				ST_WRITEOUT: begin
					// wait until client has cleared the buffer to be written to
					if (!full_i) begin 
						write_reg 		<= 1'b1;
						state_reg 		<= ST_IDLE;
					end
				end
			endcase
		end
	end
end

endmodule

`endif // _UART_JTAG_DRIVER_V_