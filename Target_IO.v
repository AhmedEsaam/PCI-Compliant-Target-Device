// MODULE DESCRIPTION : PCI-compliant target IO device                     //
// FILE NAME          : Target_IO.v                                        //
// ======================================================================= //
// PRESENTED BY       : Ahmed Essam El-Din Ahmed El-Mogy      ID: 1300151  //
//                    : Islam Mohammed Abdel-Aziz Abdel-Aal   ID: 1700253  //
//                    : Islam Hisham Mohammed Abul-Fadl Awad  ID: 1700258  //
//                    : Ahmed Sayed Aabed Ahmed               ID: 1700078  //
// ======================================================================= //
// ************************ Module Characteristics *********************** //
//                                                                         //
// COMMANDS SUPPORTED : Memory_Read,                                       //
//                      Memory_Write,                                      //
//                      Configuration_Read,                                //
//                      Configuration_Write,                               //
//                      IO_Read,                                           //
//                      IO_Write,                                          //                      
//                      Memory_Read_Multiple,                              //
//                      Dual_Address_Cycle.                                //                     
// BUFFER CAPACITY    : 4 words                                            //
// TYPE               : 32-bit , can be extended to 64-bit                 //
//                                                                         //
// *********************************************************************** //                        
   
module TAR_IO (
   // Inputs
   CLK, RSTn, C_BEn, FRAMEn, IRDYn, REQ64n, IDSEL,
   // Outputs
   TRDYn, STOPn, DEVSELn, ACK64n,
   //In/Out
   AD  
   ) ;

   input        CLK;
   input        RSTn;
   input [7:0]  C_BEn;
   input        FRAMEn;
   input        IRDYn;
   input        REQ64n;
   input        IDSEL;
   
   output       TRDYn;
   output       STOPn;
   output       DEVSELn;
   output       ACK64n;

   inout [63:0] AD;

     //-------------------------------------------------------------------
     // Configuration Memory
	reg [63:0] Config[0:5];
	initial begin
	Config[0][63:32] = 32'h12341234; //Vendor ID  
	Config[0][31:0]  = 4;  //Cash line size
	Config[1][63:0]  = 0; /* Address Mapping Type to be stored in Config[1] (0: Memory mapped, 1: IO mapped)
                                 (Initially: Mem_Mapped -subject to be overwritten by master- */
	// Base Address Registers to be stored starting from Config[2] to Config[5] 
	end
        wire BAR_type; //(0: Memory mapped, 1: IO mapped)
        assign BAR_type = Config[1][0:0]; //BAR is "Base Address Registers"

     //-------------------------------------------------------------------
     // 4-words IO Buffer
        reg [63:0] Buffer[0:3];
        wire [63:2] Shared_Address; //The high 32-bits are don't cares, unless this device is configured to be 64-bit addressed
        assign Shared_Address = Config[2][63:2];  // Most significant 62 bits of addresses of the 4 registers

     //-------------------------------------------------------------------
     // Additional Buffer 
        reg [63:0] Buffer_additional[0:3];
        reg buffer_additional_fetched = 0;
        reg [3:0]  counter = 0;
       
     //-------------------------------------------------------------------
     // Driving the Bidirectional port: AD (manage the tristate condition)		
	reg dir = 1'b0; // direction of AD (0: input, 1: output)
	reg [63:0] data_to_send;
	assign AD = dir ? data_to_send : 64'bZ; 

     //-------------------------------------------------------------------
     // Internal Signals

	reg [1:0]  Pointer; //Buffer Pointer
  
     //Assigning Status Signals
	reg Target_Ready = 1'b0;
	reg Stop         = 1'b0;
	reg Dev_Sel      = 1'b0;
	reg Ack_64       = 1'b0;
	assign TRDYn   = ~Target_Ready;
	assign STOPn   = ~Stop;
	assign DEVSELn = ~Dev_Sel;
	assign ACK64n  = ~Ack_64;
   
	reg Initial_Ready = 1'b0;
 
     //Useful internal flags
	reg Targeted      = 1'b0;
	reg Transaction   = 1'b0;
	reg Transaction_End = 1'b0;
	reg Dual_Cycle_Flag = 1'b0;
	reg Enable_64       = 1'b0;
	reg PCI_Slot_Select = 1'b0;
	reg Config_end = 1'b0;
    
	reg [31:0] Dual_Address_Cycle_Lower32;

	reg [31:0] Config_Phase_Address;

	reg [3:0] Command;

     //State parameters
	parameter Idle         = 3'b000,
                  Mem_Read     = 3'b001,
                  Mem_Write    = 3'b010,
                  Config_Read  = 3'b011,
                  Config_Write = 3'b100,
                  IO_Read      = 3'b101,
                  IO_Write     = 3'b110,
                  Mem_Read_Multiple = 3'b111;

	reg [2:0] State = Idle;
  
     //CMD parameters
	parameter CMD_Mem_Read     = 4'b0110,
                  CMD_Mem_Write    = 4'b0111,
                  CMD_Config_Read  = 4'b1010,
                  CMD_Config_Write = 4'b1011,
                  CMD_IO_Read      = 4'b0010,
                  CMD_IO_Write     = 4'b0011,
                  CMD_Dual_Address_Cycle = 4'b1101,
                  CMD_Mem_Read_Multiple  = 4'b1100;
 
//----------------------------------------------------------------------------------------------------
   
   always @ (posedge CLK or negedge RSTn) begin
     if (~RSTn)
       begin
         State        <= Idle;
         Target_Ready <= 1'b0;
         Dev_Sel      <= 1'b0;
         Ack_64       <= 1'b0;
         dir          <= 1'b0;
         data_to_send <= 64'bX;
         Transaction_End = 1'b0;
         Dual_Cycle_Flag = 1'b0;
       end

     else begin // Sampling //
       Transaction   = ~FRAMEn;
       Initial_Ready = ~IRDYn; 
       case (State)
         Idle:      begin
	               if (C_BEn[3:0] == CMD_Dual_Address_Cycle) begin
	                  Dual_Address_Cycle_Lower32 <= AD[31:0];
                          Dual_Cycle_Flag = 1;
	                  Targeted = 0;
                          end
                       else begin
                          Targeted = Dual_Cycle_Flag ? ({AD[31:0], Dual_Address_Cycle_Lower32[31:2]} == Shared_Address[63:2])
                                                      : (AD[31:2] == Shared_Address[31:2]);
                          Pointer <= AD[1:0]; // The 2 least significant bits of AD refer to a specific Buffer register
                          counter = (~Dual_Cycle_Flag) ? {1'b0, AD[1:0]} : 3'b0;   
                          Command  = C_BEn[3:0];
			  Dual_Cycle_Flag <= 0;
                          PCI_Slot_Select  = IDSEL;
                          Config_Phase_Address = AD[31:0];                         
                       end
                    end
     
         Mem_Write, IO_Write: 
                      if (Initial_Ready) begin
			 if (~buffer_additional_fetched) begin
                           Buffer[Pointer][31:0]  = AD[31:0]  & { {8{~C_BEn[3]}}, {8{~C_BEn[2]}}, {8{~C_BEn[1]}}, {8{~C_BEn[0]}} } ;
                           Buffer[Pointer][63:32] = AD[63:32] & { {8{~C_BEn[7]}}, {8{~C_BEn[6]}}, {8{~C_BEn[5]}}, {8{~C_BEn[4]}} } & {32{Enable_64}} ;
			   if ((counter == 3) & (Transaction))  buffer_additional_fetched = 1;
			   Pointer <= Pointer +1;   counter <= counter +1; 
		           end
			 else begin
		           Buffer_additional[0] = Buffer[0];      Buffer_additional[1] = Buffer[1];
		           Buffer_additional[2] = Buffer[2];      Buffer_additional[3] = Buffer[3];
			   buffer_additional_fetched = 0;
                         end
                         Transaction_End = (~Transaction); 
                      end  

         Config_Write: begin
                        if (Target_Ready & Initial_Ready) begin
			   Config[Config_Phase_Address[7:2]] =  AD & {{8{~C_BEn[7]}}, {8{~C_BEn[6]}}, {8{~C_BEn[5]}}, {8{~C_BEn[4]}}, 
                                                                      {8{~C_BEn[3]}}, {8{~C_BEn[2]}}, {8{~C_BEn[1]}}, {8{~C_BEn[0]}} };
                         end  
                      end

       endcase
       Enable_64 = ~REQ64n;
     end      

   end 
   
//----------------------------------------------------------------------------------------------------------

   always @ (negedge CLK) begin
       case (State)
         Idle: if (Targeted & Transaction) begin
                  Ack_64 <= Enable_64;
                  if ((Command == CMD_Mem_Read) & ~BAR_type) begin
                    State   <= Mem_Read;
                    Dev_Sel <= 1'b1;  // DEVSELn here is Fast
                    dir     <= 1'b1;  
                    end
                  else if ((Command == CMD_Mem_Read_Multiple) & ~BAR_type) begin
                    State   <= Mem_Read_Multiple;
                    Dev_Sel <= 1'b1;  // DEVSELn here is Fast
                    dir     <= 1'b1;
                    end
                  else if ((Command == CMD_Mem_Write) & ~BAR_type) begin
                    State        <= Mem_Write;
                    Target_Ready <= 1'b1;
                    Dev_Sel      <= 1'b1;
                    dir          <= 1'b0;
                  end if ((Command == CMD_IO_Read) & BAR_type) begin
                    State   <= IO_Read;
                    Dev_Sel <= 1'b1;  // DEVSELn here is Fast
                    dir     <= 1'b1;
                    end
                  else if ((Command == CMD_IO_Write) & BAR_type) begin
                    State        <= IO_Write;
                    Target_Ready <= 1'b1;
                    Dev_Sel      <= 1'b1;
                    dir          <= 1'b0;
                  end 
               end
               else if (PCI_Slot_Select & Transaction) begin
                  if (Command == CMD_Config_Read) begin
                    State        <= Config_Read;
                    dir          <= 1'b1;
		    Config_end   <= 1'b0;
                    end 
                  else if (Command == CMD_Config_Write) begin
                    State        <= Config_Write;
                    Target_Ready <= 1'b1;
                    Dev_Sel      <= 1'b1;
                    dir          <= 1'b0;
                    end
               end
               else begin
                    Target_Ready <= 1'b0;
                    Dev_Sel      <= 1'b0;
                    Stop         <= 1'b0;
                    Ack_64       <= 1'b0;
                    end
         
         Mem_Read, IO_Read: 
		   begin 
                     Target_Ready = 1'b1;
                     if (Initial_Ready & Transaction) begin       
                          data_to_send [31:0] <= Buffer[Pointer][31:0];
                          data_to_send [63:32]<= Buffer[Pointer][63:32] & {32{Enable_64}};
                          Pointer <= Pointer +1 ;
                          end
                     else
                          begin
                            State        <= Idle;
                            Target_Ready <= 1'b0;
                            Dev_Sel      <= 1'b0;
                            Ack_64       <= 1'b0;
                            dir          <= 1'b0;
                            data_to_send <= 64'bX;
                            Dual_Cycle_Flag <= 1'b0;
                          end   
                   end

         Mem_Read_Multiple : 
		   begin
                     Target_Ready = 1'b1;
                     if (Initial_Ready & Transaction) begin
                        if (counter < 4) begin        
                          data_to_send [31:0] <= Buffer[Pointer][31:0];
                          data_to_send [63:32]<= Buffer[Pointer][63:32] & {32{Enable_64}};
                          Pointer <= Pointer +1 ;   counter <= counter +1;
                        end
		        else begin         
                          data_to_send [31:0] <= Buffer_additional[Pointer][31:0];
                          data_to_send [63:32]<= Buffer_additional[Pointer][63:32] & {32{Enable_64}};
                          Pointer <= Pointer +1 ;   counter <= counter +1;
                        end
                     end
                     else
                          begin
                            State        <= Idle;
                            Target_Ready <= 1'b0;
                            Dev_Sel      <= 1'b0;
                            Ack_64       <= 1'b0;
                            dir          <= 1'b0;
                            data_to_send <= 64'bX;
                            Dual_Cycle_Flag <= 1'b0;
                          end   
                   end
       
         Mem_Write, IO_Write: 
		       if (Transaction_End | (counter == 8))  begin
                          State        <= Idle;
                          Target_Ready <= 1'b0;
                          Dev_Sel      <= 1'b0;
                          Ack_64       <= 1'b0;
                          dir          <= 1'b0;
                          data_to_send <= 64'bX;
                          Transaction_End = 1'b0;
                          Dual_Cycle_Flag = 1'b0;
			  Stop = (counter == 8);
			end
			else Target_Ready = (~buffer_additional_fetched) ;

         Config_Read: begin
                        Target_Ready = 1'b1;
                        Dev_Sel     <= 1'b1;
                        if (Config_end)
                             begin
                               State        <= Idle;
                               Target_Ready <= 1'b0;
                               Dev_Sel      <= 1'b0;
                               Ack_64       <= 1'b0;
                               dir          <= 1'b0;
                               data_to_send <= 64'bX;
                               Dual_Cycle_Flag <= 1'b0;
                               Config_end   <= 1'b0;
                             end
                        else
                           if (Initial_Ready) begin
                               data_to_send [63:0] <= Config[Config_Phase_Address[7:2]] 
                                                      & {{8{~C_BEn[7]}}, {8{~C_BEn[6]}}, {8{~C_BEn[5]}}, {8{~C_BEn[4]}}, 
                                                         {8{~C_BEn[3]}}, {8{~C_BEn[2]}}, {8{~C_BEn[1]}}, {8{~C_BEn[0]}} };
                               Config_end = 1;
                           end   
                      end 

          Config_Write: begin
                          State        <= Idle;
                          Target_Ready <= 1'b0;
                          Dev_Sel      <= 1'b0;
                          Ack_64       <= 1'b0;
                          dir          <= 1'b0;
                          data_to_send <= 64'bX;
                          Transaction_End = 1'b0;
                          Dual_Cycle_Flag = 1'b0;
                        end  


       endcase
   end 



endmodule

