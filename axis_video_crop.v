module axis_video_crop #
(
    parameter VIDEO_IN_W  = 1920,
    parameter VIDEO_IN_H  = 1080,
    parameter H_OFFSET    = 640,
    parameter V_OFFSET    = 300,
    parameter VIDEO_OUT_W = 640,
    parameter VIDEO_OUT_H = 480,
    
    parameter DATA_WIDTH  = 24,
    parameter USER_WIDTH  = 1
)
(
    /*
     * AXIS input
     */
    input  wire                   axis_clk,
    input  wire                   aresetn,
    
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,
    input  wire [USER_WIDTH-1:0]  s_axis_tuser,
    
    
    /*
     * AXIS ouptput
     */
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,
    output wire [USER_WIDTH-1:0]  m_axis_tuser,
    
    
    output wire [15:0]            pixel_ptr,
    output wire [15:0]            hor_ptr,
    output wire [15:0]            ver_ptr
);
   
    reg [15:0] pixel_cnt = 0;
    reg [15:0] h_ptr     = 0;
    reg [15:0] v_ptr     = 0;
    
    reg  rst = 1;
    wire open_path;
    
    assign open_path = m_axis_tready & s_axis_tvalid;
    
    assign pixel_ptr = pixel_cnt;
    assign hor_ptr = h_ptr;
    assign ver_ptr = v_ptr;
       
    
    always @ (posedge axis_clk) begin
        if (!aresetn) rst = 1;
        else if (rst) begin
            if (s_axis_tuser) rst = 0;
            else rst = rst;
        end
        
        if (open_path) begin
            if (s_axis_tuser & s_axis_tvalid) begin
                pixel_cnt = 0;
                h_ptr     = 0;
                v_ptr     = 0;
            end
            else begin
                pixel_cnt = pixel_cnt + 1;
                h_ptr = (h_ptr + 1) % VIDEO_IN_W;
                v_ptr = pixel_cnt / VIDEO_IN_W;
            end
        end
    end
    
    
    assign m_axis_tvalid = !rst & 
                           s_axis_tvalid & 
                           !( v_ptr < V_OFFSET || v_ptr >= V_OFFSET + VIDEO_OUT_H  || 
                           h_ptr < H_OFFSET || h_ptr >= H_OFFSET + VIDEO_OUT_W  );
    assign s_axis_tready = m_axis_tready;
    assign m_axis_tuser  = (h_ptr == H_OFFSET && v_ptr == V_OFFSET) ? 1 : 0;
    assign m_axis_tlast  = (h_ptr == (H_OFFSET + VIDEO_OUT_W) - 1 ) ? 1 : 0;
    assign m_axis_tdata  = s_axis_tdata;
    
endmodule
