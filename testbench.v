`timescale 1ns / 10ps

module tb_timing();

    reg aclk;
    reg aresetn;
    
    
    //AXIS signals
    reg tready;
    wire [23:0] tdata;
    wire tkeep, tvalid, tlast, tuser; 


    wire camclk;
    wire [27:0] camdata;
    cam_traffic_gen cam_traffic_gen_inst
    (
        .clk(camclk),
        .data(camdata)
    );
    
    cam_in_axi4s  DUT
    (
        .cam_clk(camclk),
        .cam_data_in(camdata),
        .aclk(aclk),
        .aresetn(aresetn),
        .m_axis_tdata(tdata),
        .m_axis_tready(tready),
        .m_axis_tvalid(tvalid),
        .m_axis_tuser(tuser),
        .m_axis_tlast(tlast)
    );
    
    
    
    always begin
        aclk = 1;
            #13;
        aclk = 0;
            #13;
    end    
    
    
    
    initial begin
        tready = 0;
        aresetn = 1;
        #52
        
        aresetn = 0;
        #780
        
        aresetn = 1;
        tready = 1;
        #13000
        
        aresetn = 0;
        #130
        aresetn = 1;
        $finish;
    end
    
endmodule


module cam_traffic_gen(
    output reg clk,
    output reg [27:0] data
);

    wire lval = data[24];
    wire fval = data[25];
    wire dval = data[26];
    
    always begin
        #13
        clk = 0;
        #13
        clk = 1;
    end
    
    
    integer pixel_cnt = 20;
    integer line_cnt = 10;
    integer linebreak = 5;
    integer framebreak = 5;
    
    always @ (posedge clk) begin
        
        if (pixel_cnt == 0) begin
            pixel_cnt = pixel_cnt - 1;
            linebreak = 5;
            
            if (line_cnt == 0) begin
                line_cnt = line_cnt - 1;
                framebreak = 5;
            end
            else if (line_cnt > 0) begin
                line_cnt = line_cnt - 1;
            end
            else begin
                if(framebreak == 0)
                    line_cnt = 10;
                else begin
                    framebreak = framebreak - 1;
                end
            end  
        end
        else if (pixel_cnt > 0) begin
            pixel_cnt = pixel_cnt - 1;
        end
        else begin
            if(linebreak == 0)
                pixel_cnt = 20;
            else begin
                linebreak = linebreak - 1;
            end
        end
            
            
            
        if(line_cnt > 0)  
            data[25] = 1;
        else
            data[25] = 0;
            
        if(pixel_cnt > 0) begin
            data[24] = 1;
            if(line_cnt > 0) begin
                data[23:0] = $urandom%16777215;
                data[26] = 1;
            end
        end
        else begin
            data[24] = 0;
            data[26] = 0;
        end

        data[27] = 0;
    end
    
endmodule
