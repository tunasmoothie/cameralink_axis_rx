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
    output wire [USER_WIDTH-1:0]  m_axis_tuser
);

    reg [15:0] pixel_cnt = 0;
    reg [15:0] h_ptr     = 0;
    reg [15:0] v_ptr     = 0;
    

    reg [DATA_WIDTH-1:0] buf_tdata;
    reg                  buf_tuser;
    reg                  buf_tlast;
    reg                  buf_tvalid;
    reg                  buf_tready;
    
    // Pointers
    always @ (posedge axis_clk) begin
        if (s_axis_tuser && s_axis_tvalid) begin
            pixel_cnt = 0;
            h_ptr     = 0;
            v_ptr     = 0;
        end
        else if (s_axis_tvalid && m_axis_tready) begin
            pixel_cnt = pixel_cnt + 1;
            h_ptr = (h_ptr + 1) % VIDEO_IN_W;
            v_ptr = pixel_cnt / VIDEO_IN_W;
        end  
    end

    
    assign m_axis_tdata  = buf_tdata;
    assign m_axis_tvalid = buf_tvalid;
    assign m_axis_tuser  = buf_tuser;
    assign m_axis_tlast  = buf_tlast;
    assign s_axis_tready = buf_tready;
    
    always @ (posedge axis_clk) begin
        if( v_ptr < V_OFFSET || v_ptr >= V_OFFSET + VIDEO_OUT_H  || 
            h_ptr < H_OFFSET || h_ptr >= H_OFFSET + VIDEO_OUT_W
        ) begin
            buf_tready = m_axis_tready;
            buf_tvalid = 0;
            buf_tuser  = 0;
            buf_tlast  = 0;
        end
        else begin
            if (s_axis_tvalid && m_axis_tready) begin
                buf_tready = m_axis_tready;
                buf_tvalid = 1;
                buf_tdata  = s_axis_tdata;
                buf_tuser = (h_ptr == H_OFFSET && v_ptr == V_OFFSET) ? 1 : 0;
                buf_tlast = (h_ptr == (H_OFFSET + VIDEO_OUT_W) - 1 ) ? 1 : 0;
            end
            else begin
                buf_tvalid = s_axis_tvalid;
                buf_tready = m_axis_tready;
            end
        end
     end
  
endmodule
