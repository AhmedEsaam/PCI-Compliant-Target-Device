//------------------------------------------------------------------------
// File:    IO_Mapped_Tar_TestBench.v
// Purpose: Monitoring Inputs/Outputs signals in a PCI-Compliant
//          Target IO Module through different test scenarios.
//------------------------------------------------------------------------
`timescale 1ns / 1ns

module IO_Mapped_Tar_TestBench;

       `include "Target_IO.v"

     //-------------------------------------------------------------------
     // inputs to TAR_IO (reg or wire type)
	wire CLK;
	reg  RSTn, FRAMEn, IRDYn, REQ64n;
        reg  [7:0] C_BEn;
	// since each PCI slot has different IDSEL port
        // to make it possible to config yet-to-be-addressed devices:
        reg  IDSEL[0:1];
     
     //-------------------------------------------------------------------
     // outputs from TAR_IO (wire type)
	wire TRDYn, STOPn, DEVSELn, ACK64n;
    
     //-------------------------------------------------------------------
     // driving the bidirectional port: AD 
	wire  [63:0] AD;
	reg   dir; // direction: (0: input, 1: output) by master
	reg   [63:0] data_to_send;
	assign AD = dir ? data_to_send : 64'bZ; //continous assignment
	
     //-------------------------------------------------------------------
     // create a 33 Mhz (30 ns cycle) clock
	module ClockGen (Clock);
	output Clock; 
	reg Clock;
	initial Clock = 0;
	always  #15 Clock = ~Clock;
	endmodule
	ClockGen C (CLK);

     //-------------------------------------------------------------------
     // create 2 instances of TAR_IO (One is Memory_Mapped, and One is IO_Mapped)
        
        // This target device will be configured to be Memory-mapped
	TAR_IO tar_io_0 ( .CLK(CLK),        .RSTn(RSTn),   .C_BEn(C_BEn), .FRAMEn(FRAMEn),   .IRDYn(IRDYn),   .REQ64n(REQ64n),
                          .IDSEL(IDSEL[0]), .TRDYn(TRDYn), .STOPn(STOPn), .DEVSELn(DEVSELn), .ACK64n(ACK64n), .AD(AD)  
			) ;

	// This target device will be configured to be IO-mapped
	TAR_IO tar_io_1 ( .CLK(CLK),        .RSTn(RSTn),   .C_BEn(C_BEn), .FRAMEn(FRAMEn),   .IRDYn(IRDYn),   .REQ64n(REQ64n),
                          .IDSEL(IDSEL[1]), .TRDYn(TRDYn), .STOPn(STOPn), .DEVSELn(DEVSELn), .ACK64n(ACK64n), .AD(AD)  
			) ;

     //-------------------------------------------------------------------
     // Address Spaces
	reg [63:0] Mem_Address_Space[0:15];
	reg [31:0] IO_Address_Space[0:7];

     //-------------------------------------------------------------------
     // supported commands' parameters
	parameter CMD_Mem_Read     = 4'b0110,
                  CMD_Mem_Write    = 4'b0111,
                  CMD_Config_Read  = 4'b1010,
                  CMD_Config_Write = 4'b1011,
                  CMD_IO_Read      = 4'b0010,
                  CMD_IO_Write     = 4'b0011,
                  CMD_Dual_Address_Cycle = 4'b1101;

     // data parameters
	parameter D1 = 64'h1111111122222222;
   	parameter D2 = 64'h3333333344444444;
   	parameter D3 = 64'h5555555566666666;
   	parameter D4 = 64'h7777777788888888;
        
     // This will be the same base address for both devices (first register address)
        parameter a = 32'h11110000;
   
	integer i,j;
	reg [31:0] cash_line_sizes[0:1]; 

	reg [63:0] address;
     

     initial begin

     //-------------------------------------------------------------------
     // Assigning addresses to the memory address spaces
	
        for (i = 0; i < 4; i = i + 1) begin 
           Mem_Address_Space[i][31:0] = a + i;  //addresses for the first device
        end 
        for (i = 0; i < 4; i = i + 1) begin
	   IO_Address_Space[i] = a + i;      //addresses for the second device (IO mappped)
        end




     //-------------------------------------------------------------------
     //************************* TEST SCENARIOS **************************


     //___________________________________________________________________
     // 1. First we configure the TAR_IO instances   /////////////////////

	//// 1.1 Configuration Read of the cash_line_sizes for the 2 devices

	for (i = 0; i < 2; i = i + 1) begin
	   
	   #30 FRAMEn = 0;  IDSEL[i] = 1;  dir = 1;
               //the [7:2] bits in the configuration address: point to a certain DWORD in the configuration space
	       //the lower 2-bits of the configurtion address must be 00 
	       data_to_send[7:0] = {6'b000000, 2'b00};  // pointer to first DWORD which carries (Device ID) and (cash line size) 
	       C_BEn[3:0] = CMD_Config_Read; //Command
	     
	   #30 dir    = 0;  
	       IRDYn  = 0;
	       FRAMEn = 1;  
               IDSEL[i] = 0;
	       C_BEn[7:0] = {4'b1111, 4'b0000}; // to read the lower half of the DWORD which stores the cash line size   

	   #30
	   #15 cash_line_sizes[i] = AD[31:0]; //@pos edge
  
	   #15 IRDYn = 1; //@neg
	       data_to_send = 64'bX;
	       C_BEn[7:0] = 8'bX; 
	   #30;
	end
	#30



	//// 1.2 Configuration Write of the (Base Addresses) and (mapping type) for the 2 devices

	for (i = 0; i < 2; i = i + 1) begin

	   //first: writing the Base Addresses 
           for (j = 0; j < cash_line_sizes[i]; j = j + 1) begin
	     //@neg edge
	     #30 FRAMEn = 0;   IDSEL[i] = 1;   dir = 1;
	         data_to_send[7:2] = 2 + j;  // pointer to DWORDS which will carry (Base Addresses)
	         data_to_send[1:0] = 2'b00;
	         C_BEn[3:0] = CMD_Config_Write;  //Command

	     #30 FRAMEn = 1;   IDSEL[i] = 0;  IRDYn = 0; 
	         if (i == 0) data_to_send[63:0] = Mem_Address_Space[j];
	         else data_to_send[63:0] = {32'bX, IO_Address_Space[j]};
	         C_BEn[7:0] = 8'b0;  
	
	     #30 IRDYn = 1;
	         data_to_send = 64'bX;
	         C_BEn[7:0] = 8'bX;
	     #30;
	   end

           //second: writing the address mapping type
	   //@neg edge
	   #30 FRAMEn = 0;   IDSEL[i] = 1;   dir = 1;
	       data_to_send[7:0] = {6'b000001, 2'b00};  // pointer to second DWORD which will carry (address mapping type)
	       C_BEn[3:0] = CMD_Config_Write;  //Command

	   #30 FRAMEn = 1;   IDSEL[i] = 0;  IRDYn = 0; 
	       if (i == 0) data_to_send[63:0] = 0; //memory mppped
	       else data_to_send[63:0] = 1; //IO mapped
	       C_BEn[7:0] = 8'b0;   
	
	   #30 IRDYn = 1;
	       data_to_send = 64'bX;
	       C_BEn[7:0] = 8'bX;
	   #30;
	end
	#30


     //___________________________________________________________________
     // 2. Memory write / read on the first device (Memory_Mapped)  //////

	//// 2.1 write 4 words ////

	   address = Mem_Address_Space[0][31:0]; //first register
           RSTn = 1;   FRAMEn = 1;  IRDYn = 1; 
	   //@neg edge
	   #30 FRAMEn = 0;   dir = 1;
	       data_to_send[31:0] = address;
	       C_BEn[3:0] = CMD_Mem_Write;  //Command
 
	   #30 IRDYn = 0;
	       data_to_send[31:0] = D1[31:0];
	       C_BEn[3:0] = 4'b0000;

	   #30 data_to_send[31:0] = D2[31:0];
	       C_BEn[3:0] = 4'b0000;

	   #30 data_to_send[31:0] = D3[31:0];
	       C_BEn[3:0] = 4'b0000;

	   #30 data_to_send[31:0] = D4[31:0];
	       C_BEn[3:0] = 4'b0000;
	       FRAMEn = 1;	    
	
	   #30 IRDYn = 1;
	       data_to_send = 64'bX;
	       C_BEn[7:0] = 8'bX;
	   #30;
	#30


 	//// 2.2 Read the 4 words from the device ////
	
	   address = Mem_Address_Space[0][31:0]; //first register
	   #30 FRAMEn = 0;   dir = 1'b1;
	       data_to_send[31:0] = address;
	       C_BEn[3:0] = CMD_Mem_Read; //Command
	     
	   #30 dir   = 1'b0;  
	       IRDYn = 1'b0;  
	       C_BEn[3:0] = 4'b0000;

	   #30
	 
	   #15 //D1 //turning to pos. edges to sample received data
 
	   #30 //D2

	   #30 //D3

	   #15 FRAMEn = 1; //@neg edge
 
	   #15 //D4 //@pos

	   #15 IRDYn = 1; //@neg
	       C_BEn[7:0] = 8'bX;
	   #30;
	   #90

     //___________________________________________________________________
     // 3. IO write / read on the second device (IO_Mapped)  //////

	//// 3.1 write 4 words  ////

	   address = IO_Address_Space[0][31:0]; //first register
           RSTn = 1;   FRAMEn = 1;  IRDYn = 1; 
	   //@neg edge
	   #30 FRAMEn = 0;   dir = 1;
	       data_to_send[31:0] = address;
	       C_BEn[3:0] = CMD_IO_Write;  //Command
 
	   #30 IRDYn = 0;
	       data_to_send[31:0] = D1[31:0];
	       C_BEn[3:0] = 4'b0000;

	   #30 data_to_send[31:0] = D2[31:0];
	       C_BEn[3:0] = 4'b0000;

	   #30 data_to_send[31:0] = D3[31:0];
	       C_BEn[3:0] = 4'b0000;

	   #30 data_to_send[31:0] = D4[31:0];
	       C_BEn[3:0] = 4'b0000;
	       FRAMEn = 1;	    
	
	   #30 IRDYn = 1;
	       data_to_send = 64'bX;
	       C_BEn[7:0] = 8'bX;
	   #30;
	#30


 	//// 3.2 Read the 4 words from the device ////
	
	   address = IO_Address_Space[0][31:0]; //first register
	   #30 FRAMEn = 0;   dir = 1'b1;
	       data_to_send[31:0] = address;
	       C_BEn[3:0] = CMD_IO_Read; //Command
	     
	   #30 dir   = 1'b0;  
	       IRDYn = 1'b0;  
	       C_BEn[3:0] = 4'b0000;

	   #30
	 
	   #15 //D1 //turning to pos. edges to sample received data
 
	   #30 //D2

	   #30 //D3

	   #15 FRAMEn = 1; //@neg edge
 
	   #15 //D4 //@pos

	   #15 IRDYn = 1; //@neg
	       C_BEn[7:0] = 8'bX;
	   #30;
	   #90;

    end   

endmodule

