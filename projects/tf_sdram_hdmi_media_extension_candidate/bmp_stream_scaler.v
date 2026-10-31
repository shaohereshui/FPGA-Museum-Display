// Stream one source row into BRAM, then emit nearest-neighbor output rows.
// Output rows follow the file's orientation; the SDRAM writer normalizes it.
module bmp_stream_scaler #(
    parameter integer OUT_WIDTH = 720,
    parameter integer OUT_HEIGHT = 480
) (
    input wire clk, rst_n, start,
    input wire [31:0] file_size,
    input wire file_valid,
    input wire [31:0] file_offset,
    input wire [7:0] file_data,
    input wire file_done, file_error,
    output wire input_ready,
    input wire write_ready,
    output wire write_en,
    output wire [18:0] write_addr,
    output wire [23:0] write_rgb,
    output reg top_down,
    output reg done, error,
    output reg [7:0] error_code
);
    localparam HEADER=0, META1=1, META2=2, META3=3, SEEK=4,
               ROW=5, FETCH=6, EMIT=7, TAIL=8, BAD=9;
    localparam MAX_WIDTH=2560, MAX_HEIGHT=1440;
    reg [3:0] state;
    reg [15:0] signature, planes, bits;
    reg [31:0] pixel_offset, dib_size, raw_width, raw_height, compression;
    reg [31:0] expected_offset;
    reg [11:0] source_width, source_column;
    reg [10:0] source_height, source_row;
    reg [12:0] stride, row_bytes, row_position;
    reg [1:0] channel;
    reg [7:0] blue, green;
    reg [32:0] pixel_end;
    reg [10:0] target_row;
    reg [11:0] sample_x;
    reg [11:0] x_phase, y_phase;
    reg [9:0] output_x, output_y;
    reg source_complete, output_complete, file_done_seen, reported;
    reg [23:0] row_memory [0:MAX_WIDTH-1];
    reg [23:0] row_pixel;
    wire [31:0] absolute_height = raw_height[31] ? (~raw_height + 1'b1) : raw_height;
    wire [23:0] source_bytes = stride * source_height;
    integer x, y;
    reg [12:0] next_x_phase, next_y_phase;
    reg [11:0] next_sample_x;
    reg [10:0] next_target_row;

    assign input_ready = state==HEADER || state==SEEK || state==ROW ||
                         state==TAIL || state==BAD;
    assign write_en = state==EMIT && !error;
    assign write_rgb = row_pixel;
    assign write_addr = output_y * OUT_WIDTH + output_x;

    always @* begin
        next_x_phase = x_phase + source_width;
        next_sample_x = sample_x;
        for (x=0; x<(MAX_WIDTH+OUT_WIDTH-1)/OUT_WIDTH; x=x+1)
            if (next_x_phase >= OUT_WIDTH) begin
                next_x_phase = next_x_phase - OUT_WIDTH;
                next_sample_x = next_sample_x + 1'b1;
            end
        next_y_phase = y_phase + source_height;
        next_target_row = target_row;
        for (y=0; y<(MAX_HEIGHT+OUT_HEIGHT-1)/OUT_HEIGHT; y=y+1)
            if (next_y_phase >= OUT_HEIGHT) begin
                next_y_phase = next_y_phase - OUT_HEIGHT;
                next_target_row = next_target_row + 1'b1;
            end
    end

    always @(posedge clk) begin
        if (file_valid && state==ROW && row_position<row_bytes && channel==2)
            row_memory[source_column] <= {file_data, green, blue};
        if (state==FETCH)
            row_pixel <= row_memory[sample_x];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=HEADER; signature<=0; planes<=0; bits<=0;
            pixel_offset<=0; dib_size<=0; raw_width<=0; raw_height<=0;
            compression<=0; expected_offset<=0;
            source_width<=0; source_height<=0; source_row<=0; source_column<=0;
            stride<=0; row_bytes<=0; row_position<=0; channel<=0;
            blue<=0; green<=0; pixel_end<=0;
            target_row<=0; sample_x<=0; x_phase<=0; y_phase<=0;
            output_x<=0; output_y<=0; top_down<=0;
            source_complete<=0; output_complete<=0; file_done_seen<=0;
            reported<=0; done<=0; error<=0; error_code<=0;
        end else begin
            done<=0;
            if (start) begin
                state<=HEADER; signature<=0; planes<=0; bits<=0;
                pixel_offset<=0; dib_size<=0; raw_width<=0; raw_height<=0;
                compression<=0; expected_offset<=0;
                source_width<=0; source_height<=0; source_row<=0; source_column<=0;
                stride<=0; row_bytes<=0; row_position<=0; channel<=0;
                target_row<=0; sample_x<=0; x_phase<=0; y_phase<=0;
                output_x<=0; output_y<=0; top_down<=0;
                source_complete<=0; output_complete<=0; file_done_seen<=0;
                reported<=0; error<=0; error_code<=0;
            end else begin
                if (file_valid) expected_offset<=expected_offset+1'b1;
                if (file_done) begin
                    file_done_seen<=1;
                    if (expected_offset!=file_size || !source_complete) begin
                        error<=1; error_code<=8'd7; state<=BAD;
                    end
                end
                if (file_done_seen && !reported && (error || output_complete)) begin
                    reported<=1; done<=1;
                end
                if (file_error || (file_valid && file_offset!=expected_offset)) begin
                    error<=1; error_code<=8'd6; state<=BAD;
                end else if (!error) case (state)
                    HEADER: if (file_valid) begin
                        case (file_offset)
                            0: signature[7:0]<=file_data;
                            1: signature[15:8]<=file_data;
                            10: pixel_offset[7:0]<=file_data;
                            11: pixel_offset[15:8]<=file_data;
                            12: pixel_offset[23:16]<=file_data;
                            13: pixel_offset[31:24]<=file_data;
                            14: dib_size[7:0]<=file_data;
                            15: dib_size[15:8]<=file_data;
                            16: dib_size[23:16]<=file_data;
                            17: dib_size[31:24]<=file_data;
                            18: raw_width[7:0]<=file_data;
                            19: raw_width[15:8]<=file_data;
                            20: raw_width[23:16]<=file_data;
                            21: raw_width[31:24]<=file_data;
                            22: raw_height[7:0]<=file_data;
                            23: raw_height[15:8]<=file_data;
                            24: raw_height[23:16]<=file_data;
                            25: raw_height[31:24]<=file_data;
                            26: planes[7:0]<=file_data;
                            27: planes[15:8]<=file_data;
                            28: bits[7:0]<=file_data;
                            29: bits[15:8]<=file_data;
                            30: compression[7:0]<=file_data;
                            31: compression[15:8]<=file_data;
                            32: compression[23:16]<=file_data;
                            33: compression[31:24]<=file_data;
                            default: ;
                        endcase
                        if (file_offset==53) state<=META1;
                    end
                    META1: begin
                        if (signature!=16'h4D42 || dib_size<40 || dib_size>124 ||
                            planes!=1 || bits!=24 || compression!=0) begin
                            error<=1; error_code<=8'd1; state<=BAD;
                        end else if (raw_width==0 || raw_width>MAX_WIDTH ||
                                     absolute_height==0 || absolute_height>MAX_HEIGHT) begin
                            error<=1; error_code<=8'd2; state<=BAD;
                        end else if (pixel_offset<dib_size+14 || pixel_offset>=file_size) begin
                            error<=1; error_code<=8'd3; state<=BAD;
                        end else begin
                            source_width<=raw_width[11:0];
                            source_height<=absolute_height[10:0];
                            top_down<=raw_height[31];
                            row_bytes<=raw_width[11:0]*3;
                            stride<=(raw_width[11:0]*3+3)&13'h1FFC;
                            state<=META2;
                        end
                    end
                    META2: begin
                        pixel_end<={1'b0,pixel_offset}+source_bytes;
                        // Mirrored DDA makes both BMP orientations produce the
                        // same visual floor(y*source_height/OUT_HEIGHT) mapping.
                        target_row<=top_down ? 0 : (source_height-1)/OUT_HEIGHT;
                        y_phase<=top_down ? 0 : (source_height-1)%OUT_HEIGHT;
                        state<=META3;
                    end
                    META3: begin
                        if (pixel_end>{1'b0,file_size}) begin
                            error<=1; error_code<=8'd4; state<=BAD;
                        end else state<=SEEK;
                    end
                    SEEK: if (file_valid && file_offset>=pixel_offset) begin
                        if (file_offset!=pixel_offset) begin
                            error<=1; error_code<=8'd6; state<=BAD;
                        end else begin
                            blue<=file_data; channel<=1; row_position<=1; state<=ROW;
                        end
                    end
                    ROW: if (file_valid) begin
                        if (row_position<row_bytes) case (channel)
                            0: begin blue<=file_data; channel<=1; end
                            1: begin green<=file_data; channel<=2; end
                            2: begin channel<=0; source_column<=source_column+1'b1; end
                            default: begin error<=1; error_code<=8'd5; state<=BAD; end
                        endcase
                        if (row_position==stride-1) begin
                            row_position<=0; source_column<=0; channel<=0;
                            if (source_row==source_height-1) source_complete<=1;
                            if (!output_complete && source_row==target_row) begin
                                output_x<=0; sample_x<=0; x_phase<=0; state<=FETCH;
                            end else if (source_row==source_height-1) state<=TAIL;
                            else source_row<=source_row+1'b1;
                        end else row_position<=row_position+1'b1;
                    end
                    FETCH: state<=EMIT;
                    EMIT: if (write_ready) begin
                        if (output_x==OUT_WIDTH-1) begin
                            output_x<=0; sample_x<=0; x_phase<=0;
                            if (output_y==OUT_HEIGHT-1) begin
                                output_complete<=1;
                                if (source_complete) state<=TAIL;
                                else begin source_row<=source_row+1'b1; state<=ROW; end
                            end else begin
                                output_y<=output_y+1'b1;
                                target_row<=next_target_row; y_phase<=next_y_phase[11:0];
                                if (next_target_row==source_row) state<=FETCH;
                                else if (source_complete) begin
                                    error<=1; error_code<=8'd5; state<=BAD;
                                end else begin source_row<=source_row+1'b1; state<=ROW; end
                            end
                        end else begin
                            output_x<=output_x+1'b1;
                            sample_x<=next_sample_x; x_phase<=next_x_phase[11:0];
                            state<=FETCH;
                        end
                    end
                    TAIL: ;
                    BAD: ;
                    default: begin error<=1; error_code<=8'd5; state<=BAD; end
                endcase
            end
        end
    end
endmodule
