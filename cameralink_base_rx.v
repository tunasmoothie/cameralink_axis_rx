`timescale 1ns / 1ps

module cameralink_base_rx #
(
    parameter AXIS_DATA_WIDTH = 32,
    parameter AXIS_KEEP_WIDTH = ((AXIS_DATA_WIDTH+7)/8),
    parameter AXIS_USER_WIDTH = 1
)
(
    // CameraLink-related IO
    input  wire [27:0]                 cmlink_data_base,
    input  wire                        cmlink_clk,
    
//    output wire                        cmlink_lval,
//    output wire                        cmlink_fval,
//    output wire                        cmlink_dval,
    output wire                        camclk_refout,

    // AXIS-related IO
    input  wire                        aclk,
    input  wire                        aresetn,
    
    output reg  [AXIS_DATA_WIDTH-1:0]  m_axis_tdata,
    output reg  [AXIS_KEEP_WIDTH-1:0]  m_axis_tkeep,
    output reg                         m_axis_tvalid,
    input  wire                        m_axis_tready,
    output reg                         m_axis_tlast,
    output reg  [AXIS_USER_WIDTH-1:0]  m_axis_tuser, 
    

    //tester
    output wire [27:0] cm_pass
);
  
    //tester
    assign cm_pass = cmlink_data_base;
    assign camclk_refout = cmlink_clk;
    
    /*
     * Internal Use 
     */
    wire        cam_clk = cmlink_clk;
    wire        rst = ~aresetn;
      

    /*
     * FIFO Pipeline
     */
    wire [35:0] fifo_in;
    wire [35:0] fifo_out;
    wire        fifo_wren;
    wire        fifo_rden;
    wire        fifo_out_tvalid;
    
    assign fifo_wren = ~WRRSTBUSY & ~FIFO_FULL;
    assign fifo_rden = ~RDRSTBUSY & ~FIFO_EMPTY & m_axis_tready;
    assign fifo_out_tvalid = fifo_out[32];
    assign fifo_in[35] = 10'b0;
    
    
    /*
     * CameraLink to AXIS conversion module
     */
    cmlink_axis_convert CM_TO_AXIS_inst(
        .cam_in(cmlink_data_base),
        .cam_clk(cam_clk),
        .axis_tdata(fifo_in[31:0]),
        .axis_tvalid(fifo_in[32]),
        .axis_tlast(fifo_in[33]),
        .axis_tuser(fifo_in[34])
    );   
    
    
    
    /*
    * 36Kb Independent Clock Dual-Port BRAM FIFO
    */
    FIFO36E2 #(
       .CLOCK_DOMAINS("INDEPENDENT"),     // COMMON, INDEPENDENT
       .FIRST_WORD_FALL_THROUGH("FALSE"), // FALSE, TRUE
       .RDCOUNT_TYPE("RAW_PNTR"),         // EXTENDED_DATACOUNT, RAW_PNTR, SIMPLE_DATACOUNT, SYNC_PNTR
       .READ_WIDTH(72),                    // 18-9
       .REGISTER_MODE("UNREGISTERED"),    // DO_PIPELINED, REGISTERED, UNREGISTERED
       .RSTREG_PRIORITY("RSTREG"),        // REGCE, RSTREG
       .WRCOUNT_TYPE("RAW_PNTR"),         // EXTENDED_DATACOUNT, RAW_PNTR, SIMPLE_DATACOUNT, SYNC_PNTR
       .WRITE_WIDTH(72)                  // 18-9
    )
    FIFO36E2_inst (
       // Read Data outputs: Read output data
       .DOUT(fifo_out),               // 64-bit output: FIFO data output bus
       // Status outputs: Flags and other FIFO status outputs
       .EMPTY(FIFO_EMPTY),            // 1-bit output: Empty
       .FULL(FIFO_FULL),                   // 1-bit output: Full
       .RDCOUNT(RDCOUNT),             // 14-bit output: Read count
       .WRCOUNT(WRCOUNT),             // 14-bit output: Write count
       // Read Control Signals inputs: Read clock, enable and reset input signals
       .RDCLK(aclk),              // 1-bit input: Read clock
       .RDEN(fifo_rden),                      // 1-bit input: Read enable
       .REGCE(1),                     // 1-bit input: Output register clock enable
       .RSTREG(0),                    // 1-bit input: Output register reset
       .SLEEP(0),                     // 1-bit input: Sleep Mode
       // Write Control Signals inputs: Write clock and enable input signals
       .RST(rst),                 // 1-bit input: Reset
       .WRCLK(cam_clk),               // 1-axis_clkbit input: Write clock
       .WREN(fifo_wren),                      // 1-bit input: Write enable
       // Write Data inputs: Write input data
       .DIN(fifo_in),                 // 64-bit input: FIFO data input bus
       .RDRSTBUSY(RDRSTBUSY),         // 1-bit output: Reset busy (sync to RDCLK)
       .WRRSTBUSY(WRRSTBUSY),         // 1-bit output: Reset busy (sync to WRCLK)
       .WRERR(WRERR)                  // 1-bit output: Write Error
    );   
       
              
    /*
    *  AXIS Output Pipeline
    *  
    *  == FIFO output vector bit data ==
    *  0-31  : RGB888 data
    *  32    : Vector Set TVALID
    *  33    : AXIS TLAST EoL 
    *  34    : AXIS TUSER SoF  
    *  35    : Reserved
    *  ========================================
    */  
     
    always@(posedge aclk) begin
        m_axis_tdata = fifo_out[31:0];
        m_axis_tlast = fifo_out[33];
        m_axis_tuser[0] = fifo_out[34];
        
        // TVALID Determination
        m_axis_tvalid = fifo_out_tvalid & ~RDRSTBUSY & ~FIFO_EMPTY;

    end
    
endmodule








module cmlink_axis_convert(
    input  wire [27:0]   cam_in,
    input  wire          cam_clk,
    output wire [31:0]   axis_tdata,
    output wire          axis_tlast,
    output wire          axis_tuser,
    output wire          axis_tvalid
);
    
    reg [27:0] cam_ibuf0, cam_ibuf1;
    reg [31:0] axis_tdata_buf;
    reg        axis_tlast_buf;
    reg        axis_tuser_buf;
    reg        axis_tvalid_buf;
    
    
    assign axis_tdata = axis_tdata_buf;
    assign axis_tlast = axis_tlast_buf;
    assign axis_tuser = axis_tuser_buf;
    assign axis_tvalid = axis_tvalid_buf;
    
    /*
    *  CameraLink Data Sort
    *  
    *  == Sorted Cameralink Format ==
    *  0-23  : RGB888 data
    *  24    : LVAL  
    *  25    : FVAL
    *  26    : DVAL
    *  27    : Reserved
    *  ==============================
    */  

    reg frame_start = 0;
    wire lval, lval_next;
    wire fval, fval_next;
    wire dval, dval_next;
    assign lval = cam_ibuf1[24];
    assign fval = cam_ibuf1[25];
    assign dval = cam_ibuf1[26];
    assign lval_next = cam_ibuf0[24];
    assign fval_next = cam_ibuf0[25];
    assign dval_next = cam_ibuf0[26];

    always@(posedge cam_clk)begin
    
        // VAL signals
        cam_ibuf0[24] <= cam_in[24];
        cam_ibuf0[25] <= cam_in[25];
        cam_ibuf0[26] <= cam_in[26];
        
        // Port A   Color R
        cam_ibuf0[0] <= cam_in[0];
        cam_ibuf0[1] <= cam_in[1];
        cam_ibuf0[2] <= cam_in[2];
        cam_ibuf0[3] <= cam_in[3];
        cam_ibuf0[4] <= cam_in[4];
        cam_ibuf0[5] <= cam_in[6];
        cam_ibuf0[6] <= cam_in[27];
        cam_ibuf0[7] <= cam_in[5];
        
        // Port B   Color B
        cam_ibuf0[8] <= cam_in[15];
        cam_ibuf0[9] <= cam_in[18];
        cam_ibuf0[10] <= cam_in[19];
        cam_ibuf0[11] <= cam_in[20];
        cam_ibuf0[12] <= cam_in[21];
        cam_ibuf0[13] <= cam_in[22];
        cam_ibuf0[14] <= cam_in[16];
        cam_ibuf0[15] <= cam_in[17];
        
        // Port C   Color G
        cam_ibuf0[16] <= cam_in[7];
        cam_ibuf0[17] <= cam_in[8];
        cam_ibuf0[18] <= cam_in[9];
        cam_ibuf0[19] <= cam_in[12];
        cam_ibuf0[20] <= cam_in[13];
        cam_ibuf0[21] <= cam_in[14];
        cam_ibuf0[22] <= cam_in[10];
        cam_ibuf0[23] <= cam_in[11];
                
        cam_ibuf1 <= cam_ibuf0;
        
        
        // TDATA data pass determination
        if(lval & fval == 1'b1)begin
            axis_tdata_buf[23:0] = cam_ibuf1;
            axis_tdata_buf[31:24] = 8'b0;
            axis_tvalid_buf = 1;
        end
        else begin
            axis_tdata_buf[31:0] = 32'b0;
            axis_tvalid_buf = 0;
        end
        
        
        // TLAST determination
        axis_tlast_buf = (lval & ~lval_next) & fval;
        
        // TUSER determination
        if (~fval & fval_next)
            frame_start = 1'b1;
        
        if (frame_start & dval) begin
            axis_tuser_buf = 1;
            frame_start = 0;
        end
        else  axis_tuser_buf = 0;
        
    end
    
    
endmodule
