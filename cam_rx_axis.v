module cam_in_axi4s #
(
    parameter DATA_WIDTH = 24,
    //parameter KEEP_WIDTH = ((DATA_WIDTH+7)/8),
    parameter USER_WIDTH = 1
)
(
    /*
     * CameraLink input
     */
    input wire                    cam_clk,
    input wire [27:0]             cam_data_in,
    
    
    /*
     * AXI output
     */
    input  wire                   aclk,
    //input  wire                   aclken,
    input  wire                   aresetn,
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    //output wire [KEEP_WIDTH-1:0]  m_axis_tkeep,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [USER_WIDTH-1:0]  m_axis_tuser,
    
    /*
     * Diagnostics
     */
     output wire                  overflow,
     output wire                  underflow
);
   
    // Reset variables
    wire        rst = ~aresetn;
    reg         rst_busy = 1;
    reg         axis_wait_newframe = 1;
    

  
    // ================================================
    // Input parsing
    // ================================================   
    wire        parsed_dval;
    wire        parsed_lval;   
    wire        parsed_fval; 
    wire [7:0]  parsed_port_A;
    wire [7:0]  parsed_port_B;
    wire [7:0]  parsed_port_C;
    
    // Parser instantiation
    cam_data_parser cam_data_parser_inst(
        .data(cam_data_in),
        .dval(parsed_dval),
        .lval(parsed_lval),
        .fval(parsed_fval),
        .port_A(parsed_port_A),
        .port_B(parsed_port_B),
        .port_C(parsed_port_C)
    );
   
    // ================================================
    // Timing signal extraction
    // ================================================  
    reg         ibuf_dval;
    reg         ibuf_lval;
    reg         ibuf_fval;
    reg  [7:0]  ibuf_port_A;
    reg  [7:0]  ibuf_port_B;
    reg  [7:0]  ibuf_port_C;
    
    reg         iibuf_dval;
    reg         iibuf_lval;
    reg         iibuf_fval;
    reg  [7:0]  iibuf_port_A;
    reg  [7:0]  iibuf_port_B;
    reg  [7:0]  iibuf_port_C;
    
    reg         SoL;
    wire        EoL;
    wire        SoF;  // ***** REDUNDANT VARIABLE *****
    reg         frame_ready = 0;
    
    
    // EoL detection
    assign EoL = iibuf_dval & ~ibuf_dval;
    
    always @ (posedge cam_clk) begin
        // SoL detection
        SoL <= ~iibuf_lval & ibuf_lval;
        // Frame ready detection (FVAL posedge,  SR latched)
        frame_ready <= (~iibuf_fval & ibuf_fval) + (~SoL & frame_ready);
    end
    
    // ***** REDUNDANT VARIABLE *****
    // SoF detection (frame_ready and DVAL posedge)
    assign SoF = frame_ready & SoL;
    
    always @ (posedge cam_clk) begin
        ibuf_dval <= parsed_dval;
        ibuf_lval <= parsed_lval;
        ibuf_fval <= parsed_fval;
        ibuf_port_A <= parsed_port_A;
        ibuf_port_B <= parsed_port_B;
        ibuf_port_C <= parsed_port_C;
        
        iibuf_dval <= ibuf_dval;
        iibuf_lval <= ibuf_lval;
        iibuf_fval <= ibuf_fval;
        iibuf_port_A <= ibuf_port_A;
        iibuf_port_B <= ibuf_port_B;
        iibuf_port_C <= ibuf_port_C;
    end
    
  
  
   
    // ================================================
    // FIFO Connections
    // ================================================
    
    // Write-side
    wire [35:0]     fifo_in;
    wire            fifo_wren;
    wire            fifo_wrrstbusy;
    wire            fifo_full;
    
    assign fifo_in[7:0]   = iibuf_port_A;
    assign fifo_in[15:8]  = iibuf_port_B;
    assign fifo_in[23:16] = iibuf_port_C;
    assign fifo_in[24]    = iibuf_dval;
    assign fifo_in[25]    = EoL;
    assign fifo_in[26]    = frame_ready;
    assign fifo_in[35:27] = 8'b0;
    
    assign fifo_wren = ~rst_busy & ~fifo_full; 
    assign overflow = fifo_full;
    
    // Read-side
    wire [35:0]     fifo_out;
    wire            fifo_rden;
    wire            fifo_rdrstbusy;
    wire            fifo_empty;
    
    assign fifo_rden = ~rst_busy & ~fifo_empty & m_axis_tready;
    assign underflow = fifo_empty;
    
    // FIFO instantiation
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
       .RST(rst),                     // 1-bit input: Reset
        // Status outputs: Flags and other FIFO status outputs
       .EMPTY(fifo_empty),            // 1-bit output: Empty
       .FULL(fifo_full),              // 1-bit output: Full
       .RDCOUNT(RDCOUNT),             // 14-bit output: Read count
       .WRCOUNT(WRCOUNT),             // 14-bit output: Write count
       .RDRSTBUSY(fifo_rdrstbusy),         // 1-bit output: Reset busy (sync to RDCLK)
       .WRRSTBUSY(fifo_wrrstbusy),         // 1-bit output: Reset busy (sync to WRCLK)
       .WRERR(WRERR),                 // 1-bit output: Write Error
        
       // Read Control Signals inputs: Read clock, enable and reset input signals
       .RDCLK(aclk),                  // 1-bit input: Read clock
       .RDEN(fifo_rden),              // 1-bit input: Read enable
       // Read Data outputs: Read output data
       .DOUT(fifo_out),               // 64-bit output: FIFO data output bus
       
       // Write Control Signals inputs: Write clock and enable input signals
       .WRCLK(cam_clk),               // 1-axis_clkbit input: Write clock
       .WREN(fifo_wren),              // 1-bit input: Write enable
       // Write Data inputs: Write input data
       .DIN(fifo_in)                  // 64-bit input: FIFO data input bus
    );   
     
     

    
    // ================================================
    // AXIS Preperation
    // ================================================
    
    reg [DATA_WIDTH-1:0]  obuf_tdata;
    reg                   obuf_tvalid;
    reg                   obuf_tlast;
    reg                   obuf_tuser;
    
    wire [7:0]            cm_port_a;
    wire [7:0]            cm_port_b;
    wire [7:0]            cm_port_c;
    
    assign cm_port_a = fifo_out[7:0];
    assign cm_port_b = fifo_out[15:8];
    assign cm_port_c = fifo_out[23:16];
    
    assign m_axis_tdata[23:0] = obuf_tdata[23:0];
    assign m_axis_tvalid      = obuf_tvalid;
    assign m_axis_tlast       = obuf_tlast;
    assign m_axis_tuser       = obuf_tuser;
    
    always @ (posedge aclk) begin
        obuf_tuser = fifo_out[26];
        obuf_tvalid = (axis_wait_newframe) ? 1'b0 : fifo_out[24];
        obuf_tlast  = (axis_wait_newframe) ? 1'b0 : fifo_out[25];
        if (fifo_out[24] == 0 || axis_wait_newframe) begin
            obuf_tdata[23:0] = 24'b0; 
        end
        else begin
            //AXIS pixel data arrangment is R-B-G
            obuf_tdata[23:16] = cm_port_c;
            obuf_tdata[15:8]  = cm_port_b;
            obuf_tdata[7:0]   = cm_port_a;    
        end

    end
    
    
    // ================================================
    // Reset subprocess
    // ================================================
    always @ (posedge aclk) begin
        rst_busy <= rst | (~(~fifo_wrrstbusy & ~fifo_wrrstbusy) & rst_busy);
        axis_wait_newframe <= rst | (~(obuf_tuser) & axis_wait_newframe);
    end    
    
endmodule




module cam_data_parser
(
    input  wire [27:0]            data,
    
    output wire                   dval,
    output wire                   lval,
    output wire                   fval,
    output wire [7:0]             port_A,
    output wire [7:0]             port_B,
    output wire [7:0]             port_C
);

    assign dval = data[26];
    assign lval = data[24];
    assign fval = data[25];
    
    assign port_A[0] = data[0];
    assign port_A[1] = data[1];
    assign port_A[2] = data[2];
    assign port_A[3] = data[3];
    assign port_A[4] = data[4];
    assign port_A[5] = data[6];
    assign port_A[6] = data[27];
    assign port_A[7] = data[5];
    
    assign port_B[0] = data[7];
    assign port_B[1] = data[8];
    assign port_B[2] = data[9];
    assign port_B[3] = data[12];
    assign port_B[4] = data[13];
    assign port_B[5] = data[14];
    assign port_B[6] = data[10];
    assign port_B[7] = data[11];
    
    assign port_C[0] = data[15];
    assign port_C[1] = data[18];
    assign port_C[2] = data[19];
    assign port_C[3] = data[20];
    assign port_C[4] = data[21];
    assign port_C[5] = data[22];
    assign port_C[6] = data[16];
    assign port_C[7] = data[17];
    
endmodule
