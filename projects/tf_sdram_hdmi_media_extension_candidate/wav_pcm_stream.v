// RIFF/WAVE PCM stream. Unknown chunks are skipped with RIFF padding.
module wav_pcm_stream (
    input wire clk, rst_n, start,
    input wire [31:0] file_size,
    input wire file_valid,
    input wire [31:0] file_offset,
    input wire [7:0] file_data,
    input wire file_done, file_error,
    output wire input_ready,
    input wire pcm_ready,
    output reg pcm_valid,
    output reg [31:0] pcm_data,
    output reg done, error,
    output reg [7:0] error_code
);
    localparam HEADER=0, CHUNK=1, FMT=2, SKIP=3, DATA=4, BAD=6;
    reg [2:0] state;
    reg [31:0] expected_offset, riff_tag, wave_tag, riff_size;
    reg [31:0] chunk_tag, chunk_size, remaining, pcm_build;
    reg [31:0] sample_rate, byte_rate;
    reg [15:0] format_tag, channels, block_align, bits;
    reg [4:0] fmt_position;
    reg [2:0] chunk_position;
    reg [1:0] sample_position;
    reg fmt_seen, data_seen, file_done_seen, reported;
    wire [31:0] size_next={file_data,chunk_size[23:0]};
    wire [32:0] chunk_end={1'b0,file_offset}+1+{1'b0,size_next}+size_next[0];

    assign input_ready = state!=DATA || (!pcm_valid && pcm_ready);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=HEADER; expected_offset<=0; riff_tag<=0; wave_tag<=0; riff_size<=0;
            chunk_tag<=0; chunk_size<=0; remaining<=0; pcm_build<=0;
            sample_rate<=0; byte_rate<=0; format_tag<=0; channels<=0;
            block_align<=0; bits<=0; fmt_position<=0; chunk_position<=0;
            sample_position<=0; fmt_seen<=0; data_seen<=0; file_done_seen<=0; reported<=0;
            pcm_valid<=0; pcm_data<=0; done<=0; error<=0; error_code<=0;
        end else begin
            done<=0;
            if (pcm_valid && pcm_ready) pcm_valid<=0;
            if (start) begin
                state<=HEADER; expected_offset<=0; riff_tag<=0; wave_tag<=0; riff_size<=0;
                chunk_tag<=0; chunk_size<=0; remaining<=0; pcm_build<=0;
                sample_rate<=0; byte_rate<=0; format_tag<=0; channels<=0;
                block_align<=0; bits<=0; fmt_position<=0; chunk_position<=0;
                sample_position<=0; fmt_seen<=0; data_seen<=0; file_done_seen<=0; reported<=0;
                pcm_valid<=0; error<=0; error_code<=0;
            end else begin
                if (file_valid) expected_offset<=expected_offset+1'b1;
                if (file_done) begin
                    file_done_seen<=1;
                    if (expected_offset!=file_size || !data_seen || state!=CHUNK || chunk_position!=0) begin
                        error<=1; error_code<=8'd8; state<=BAD;
                    end
                end
                if (file_done_seen && !reported &&
                    (error || (state==CHUNK && chunk_position==0 && data_seen && !pcm_valid))) begin
                    reported<=1; done<=1;
                end
                if (file_error || (file_valid && file_offset!=expected_offset)) begin
                    error<=1; error_code<=8'd7; state<=BAD;
                end else if (!error && file_valid) case (state)
                    HEADER: begin
                        case (file_offset)
                            0,1,2,3: riff_tag<={riff_tag[23:0],file_data};
                            4: riff_size[7:0]<=file_data;
                            5: riff_size[15:8]<=file_data;
                            6: riff_size[23:16]<=file_data;
                            7: riff_size[31:24]<=file_data;
                            8,9,10: wave_tag<={wave_tag[23:0],file_data};
                            11: begin
                                if (riff_tag!="RIFF" || {wave_tag[23:0],file_data}!="WAVE") begin
                                    error<=1; error_code<=8'd1; state<=BAD;
                                end else if ({1'b0,riff_size}+8!={1'b0,file_size} || file_size<48) begin
                                    error<=1; error_code<=8'd2; state<=BAD;
                                end else begin state<=CHUNK; chunk_position<=0; end
                            end
                            default: begin error<=1; error_code<=8'd1; state<=BAD; end
                        endcase
                    end
                    CHUNK: begin
                        chunk_position<=chunk_position+1'b1;
                        case (chunk_position)
                            0,1,2,3: chunk_tag<={chunk_tag[23:0],file_data};
                            4: chunk_size[7:0]<=file_data;
                            5: chunk_size[15:8]<=file_data;
                            6: chunk_size[23:16]<=file_data;
                            7: begin
                                chunk_size[31:24]<=file_data;
                                if (chunk_end>{1'b0,file_size}) begin
                                    error<=1; error_code<=8'd3; state<=BAD;
                                end else if (chunk_tag=="fmt ") begin
                                    if (fmt_seen || size_next<16) begin
                                        error<=1; error_code<=8'd4; state<=BAD;
                                    end else begin
                                        remaining<=size_next; fmt_position<=0; state<=FMT;
                                    end
                                end else if (chunk_tag=="data") begin
                                    if (!fmt_seen || data_seen || size_next==0 || size_next[1:0]!=0) begin
                                        error<=1; error_code<=8'd6; state<=BAD;
                                    end else begin
                                        remaining<=size_next; sample_position<=0; data_seen<=1; state<=DATA;
                                    end
                                end else begin
                                    remaining<=size_next+size_next[0];
                                    state<=size_next==0 ? CHUNK : SKIP;
                                end
                            end
                        endcase
                    end
                    FMT: begin
                        fmt_position<=fmt_position+1'b1;
                        remaining<=remaining-1'b1;
                        case (fmt_position)
                            0: format_tag[7:0]<=file_data;
                            1: format_tag[15:8]<=file_data;
                            2: channels[7:0]<=file_data;
                            3: channels[15:8]<=file_data;
                            4: sample_rate[7:0]<=file_data;
                            5: sample_rate[15:8]<=file_data;
                            6: sample_rate[23:16]<=file_data;
                            7: sample_rate[31:24]<=file_data;
                            8: byte_rate[7:0]<=file_data;
                            9: byte_rate[15:8]<=file_data;
                            10: byte_rate[23:16]<=file_data;
                            11: byte_rate[31:24]<=file_data;
                            12: block_align[7:0]<=file_data;
                            13: block_align[15:8]<=file_data;
                            14: bits[7:0]<=file_data;
                            15: begin
                                bits[15:8]<=file_data;
                                if (format_tag!=1 || channels!=2 || sample_rate!=48000 ||
                                    byte_rate!=192000 || block_align!=4 || {file_data,bits[7:0]}!=16) begin
                                    error<=1; error_code<=8'd5; state<=BAD;
                                end else begin
                                    fmt_seen<=1; chunk_position<=0;
                                    remaining<=remaining-1'b1+chunk_size[0];
                                    state<=remaining==1 ? CHUNK : SKIP;
                                end
                            end
                            default: begin error<=1; error_code<=8'd4; state<=BAD; end
                        endcase
                    end
                    SKIP: begin
                        remaining<=remaining-1'b1;
                        if (remaining==1) begin state<=CHUNK; chunk_position<=0; end
                    end
                    DATA: begin
                        remaining<=remaining-1'b1;
                        sample_position<=sample_position+1'b1;
                        case (sample_position)
                            0: pcm_build[7:0]<=file_data;
                            1: pcm_build[15:8]<=file_data;
                            2: pcm_build[23:16]<=file_data;
                            3: begin pcm_data<={file_data,pcm_build[23:0]}; pcm_valid<=1; end
                        endcase
                        if (remaining==1) begin state<=CHUNK; chunk_position<=0; end
                    end
                    BAD: ;
                    default: begin error<=1; error_code<=8'd4; state<=BAD; end
                endcase
            end
        end
    end
endmodule
