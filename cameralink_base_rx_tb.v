`timescale 1ns / 10ps

module cameralink_base_rx_tb();

    reg camclk, aclk;
    reg rstn;
    reg [27:0] camdata;
    
    wire camclkout;
    
    //AXIS signals
    reg tready;
    wire [31:0] tdata;
    wire tkeep, tvalid, tlast, tuser;

    cameralink_base_rx #(
        .AXIS_DATA_WIDTH(32),
        .AXIS_USER_WIDTH(1)
    )
    DUT(
        .cmlink_data_base(camdata),
        .cmlink_clk(camclk),
        .aclk(aclk),
        .aresetn(rstn),
        
        .camclk_refout(camclkout),
        
        
        .m_axis_tdata(tdata),
        .m_axis_tkeep(tkeep),
        .m_axis_tvalid(tvalid),
        .m_axis_tready(tready),
        .m_axis_tlast(tlast),
        .m_axis_tuser(tuser)
    );
    
    
    always begin
        camclk = 1;
            #7;
        camclk = 0;
            #7;
    end
    
    always begin
        aclk = 1;
            #4;
        aclk = 0;
            #4;
    end
    
    
    
    
    // 16777215 max
    integer pixelcnt = 0;
    integer linebrk = 0;
    always@(posedge camclk) begin
        if(linebrk > 0)begin
            linebrk = linebrk - 1;
        end
        else begin
            if (pixelcnt >= 20)begin
              pixelcnt = 0;
              camdata[24] = 0;
              camdata[26] = 0;
              linebrk = 5;
            end
            else begin
              camdata[23:0] = $urandom%16777215;
              camdata[24] = 1;
              camdata[26] = 1;
              pixelcnt = pixelcnt + 1;
            end
        end
    
        camdata[25] = 1;
        camdata[27] = 0;
    end
    
    
    initial begin
        rstn = 1;
        #28;
        rstn = 0;
        #26;
        rstn = 1;
        #80;
        
        tready = 1;
        #500
        tready = 0;
        #100
        tready = 1;
        #500
        tready = 0;
        #100
        tready = 1;
        #500
        tready = 0;
        #100
        tready = 1;
        
        $finish;
    end
    
endmodule
