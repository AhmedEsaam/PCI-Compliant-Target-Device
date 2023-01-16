//------------------------------------------------------------------------
// File:    Dual_address_target_TestBench.v
// Purpose: Monitoring Inputs/Outputs signals through Mem_Read and Mem_Write
//          in a PCI-Compliant Target IO Device with dual-cycle address
//------------------------------------------------------------------------
`timescale 1ns / 1ns

module Dual_Address_TAR_IO_TestBench;

       `include "Target_IO.v"

     //-------------------------------------------------------------------
     // inputs to TAR_IO (reg or wire type)
	wire CLK;
	reg  RSTn, FRAMEn, IRDYn, REQ64n;
        reg  [7:0] C_BEn;
	// since each PCI slot has different IDSEL port
        // to make it possible to config yet-to-be-addressed devices:
        reg  IDSEL;
     
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
     // create an instance of TAR_IO
        
	TAR_IO tar_io( .CLK(CLK),     .RSTn(RSTn),   .C_BEn(C_BEn), .FRAMEn(FRAMEn),   .IRDYn(IRDYn),   .REQ64n(REQ64n),
                       .IDSEL(IDSEL), .TRDYn(TRDYn), .STOPn(STOPn), .DEVSELn(DEVSELn), .ACK64n(ACK64n), .AD(AD)  
			) ;

     //-------------------------------------------------------------------
     // Address Space
	reg [63:0] Mem_Address_Space[0:15];

     //-------------------------------------------------------------------
     // supported commands' parameters
	parameter CMD_Mem_Read     = 4'b0110,
            	  CMD_Mem_Write    = 4'b0111,
             	  CMD_Config_Read  = 4'b1010,
             	  CMD_Config_Write = 4'b1011,
             	  CMD_Dual_Address_Cycle = 4'b1101;

     // data parameters
	parameter D1 = 64'h1111111122222222;
   	parameter D2 = 64'h3333333344444444;
   	parameter D3 = 64'h5555555566666666;
   	parameter D4 = 64'h7777777788888888;
        
     // an address sample
        parameter a = 32'h11110000;
   
	integer i,j;
	reg [31:0] cash_line_size; 
	reg [63:0] address;
     

     initial begin

     //-------------------------------------------------------------------
     // Assigning addresses to the memory address space
	
	for (i = 0; i < 4; i = i + 1) begin 
           Mem_Address_Space[i] = (64'h1111222233330000) + i; //addresses for the 4th device (64-bit-length addresses)
        end 


     //-------------------------------------------------------------------
     //************************* TEST SCENARIOS **************************


     //___________________________________________________________________
     // 1. First we configure the TAR_IO instance  ///////////////////////

	//// 1.1 Configuration Read of the cash_line_size for the device

	   #30 FRAMEn = 0;  IDSEL = 1;  dir = 1;
               //the [7:2] bits in the configuration address: point to a certain DWORD in the configuration space
	       //the lower 2-bits of the configurtion address must be 00 
	       data_to_send[7:0] = {6'b000000, 2'b00};  // pointer to first DWORD which carries (Device ID) and (cash line size) 
	       C_BEn[3:0] = CMD_Config_Read; //Command
	     
	   #30 dir    = 0;  
	       IRDYn  = 0;
	       FRAMEn = 1;  
               IDSEL = 0;
	       C_BEn[7:0] = {4'b1111, 4'b0000}; // to read the lower half of the DWORD which stores the cash line size   

	   #30
	   #15 cash_line_size = AD[31:0]; //@pos edge
  
	   #15 IRDYn = 1; //@neg
	       data_to_send = 64'bX;
	       C_BEn[7:0] = 8'bX; 
	   #30;


	//// 1.2 Configuration Write of the (Base Addresses) and (mapping type) for the device

	   //first: writing the Base Addresses 
           for (j = 0; j < cash_line_size; j = j + 1) begin
	     //@neg edge
	     #30 FRAMEn = 0;   IDSEL = 1;   dir = 1;
	         data_to_send[7:2] = 2 + j;  // pointer to DWORDS which will carry (Base Addresses)
	         data_to_send[1:0] = 2'b00;
	         C_BEn[3:0] = CMD_Config_Write;  //Command

	     #30 FRAMEn = 1;   IDSEL = 0;  IRDYn = 0; 
	         data_to_send[63:0] = Mem_Address_Space[j];
	         C_BEn[7:0] = 8'b0;
	
	     #30 IRDYn = 1;
	         data_to_send = 64'bX;
	         C_BEn[7:0] = 8'bX;
	     #30;
	   end

           //second: writing the address mapping type (it will be Memory-Mapped)
	   //@neg edge
	   #30 FRAMEn = 0;   IDSEL = 1;   dir = 1;
	       data_to_send[7:0] = {6'b000001, 2'b00};  // pointer to second DWORD which will carry (address mapping type)
	       C_BEn[3:0] = CMD_Config_Write;  //Command

	   #30 FRAMEn = 1;   IDSEL = 0;  IRDYn = 0; 
	       data_to_send[63:0] = 0; //memory mppped
	       C_BEn[7:0] = 8'b0;   
	
	   #30 IRDYn = 1;
	       data_to_send = 64'bX;
	       C_BEn[7:0] = 8'bX;
	   #30;
	#30




     //___________________________________________________________________
     // 2. Memory_Read and Memory_Write 4 DWORDs   //////////////////////////
 	//// 2.1 Memory_Write  ////

	RSTn = 1;   FRAMEn = 1;  IRDYn = 1;  

	  //@neg edge
	#30 FRAMEn = 0;  dir = 1;
	    data_to_send[31:0] = Mem_Address_Space[0][31:0];
	    C_BEn[3:0] = CMD_Dual_Address_Cycle;  //Command

	#30 data_to_send[31:0] = Mem_Address_Space[0][63:32];
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
 

	//// 2.2 Mem_Read  ////

	#30 FRAMEn = 0;  dir = 1;
	    data_to_send[31:0] = Mem_Address_Space[0][31:0];
	    C_BEn[3:0] = CMD_Dual_Address_Cycle;  //Command

	#30 data_to_send[31:0] = Mem_Address_Space[0][63:32];
	    C_BEn[3:0] = CMD_Mem_Read;  //Command
	     
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

	#90;
	
     end   

endmodule






	
	

