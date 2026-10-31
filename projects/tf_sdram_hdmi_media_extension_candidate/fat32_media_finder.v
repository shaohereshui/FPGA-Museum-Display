// Scan the first root-directory cluster for the first ordinary 8.3 BMP entry.
// A full cluster without an end marker requires the caller to follow the root FAT chain.
module fat32_media_finder #(
    parameter [63:0] TARGET_STEM = 64'd0,
    parameter integer DYNAMIC_TARGET = 0
) (
    input wire clk, rst_n, start,
    input wire [63:0] runtime_target,
    input wire [23:0] runtime_extension,
    input wire [31:0] volume_lba, volume_sectors, data_lba, root_cluster,
    input wire [7:0] sectors_per_cluster,
    input wire sector_ready, sector_valid, sector_done, reader_error,
    input wire [8:0] sector_index,
    input wire [7:0] sector_data,
    output wire sector_start,
    output wire [31:0] sector_lba,
    output reg done, found, end_of_dir, need_chain, error,
    output reg [31:0] file_cluster, file_size
);
    localparam IDLE=0, ISSUE=1, READ=2, FINISHED=3;
    reg [1:0] state;
    reg [31:0] base_lba;
    reg [7:0] sector_number;
    reg [9:0] expected_index;
    reg bad_stream, hit, ended, bad_file;
    reg [7:0] first_byte, attribute, ext0, ext1, ext2;
    reg [63:0] name_bytes;
    reg [31:0] entry_cluster, entry_size;
    wire [39:0] cluster_lba = {8'b0,data_lba} +
        ({8'b0,root_cluster} - 40'd2) * sectors_per_cluster;
    wire [33:0] volume_end = {2'b0,volume_lba} + {2'b0,volume_sectors};
    wire [33:0] cluster_end = {2'b0,cluster_lba[31:0]} + sectors_per_cluster;
    wire [4:0] offset = sector_index[4:0];
    wire [63:0] selected_stem = DYNAMIC_TARGET ? runtime_target : TARGET_STEM;
    wire bmp_entry = first_byte != 0 && first_byte != 8'he5 &&
        (selected_stem == 0 || name_bytes == selected_stem) &&
        attribute != 8'h0f && !(attribute & 8'h18) &&
        {ext0,ext1,ext2} == runtime_extension;

    assign sector_start = state == ISSUE && sector_ready && !reader_error;
    assign sector_lba = base_lba + sector_number;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; base_lba <= 0; sector_number <= 0;
            expected_index <= 0; bad_stream <= 0; hit <= 0;
            ended <= 0; bad_file <= 0; first_byte <= 0;
            attribute <= 0; ext0 <= 0; ext1 <= 0; ext2 <= 0;
            name_bytes <= 0;
            entry_cluster <= 0; entry_size <= 0;
            done <= 0; found <= 0; end_of_dir <= 0;
            need_chain <= 0; error <= 0; file_cluster <= 0; file_size <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: if (start) begin
                    found <= 0; end_of_dir <= 0; need_chain <= 0; error <= 0;
                    file_cluster <= 0; file_size <= 0;
                    sector_number <= 0;
                    if (root_cluster < 2 || sectors_per_cluster == 0 ||
                        cluster_lba > 40'h00ffffffff ||
                        cluster_end > volume_end || cluster_lba < data_lba) begin
                        error <= 1; done <= 1; state <= FINISHED;
                    end else begin
                        base_lba <= cluster_lba[31:0]; state <= ISSUE;
                    end
                end
                ISSUE: if (reader_error) begin
                    error <= 1; done <= 1; state <= FINISHED;
                end else if (sector_ready) begin
                    expected_index <= 0; bad_stream <= 0;
                    hit <= 0; ended <= 0; bad_file <= 0;
                    state <= READ;
                end
                READ: if (reader_error) begin
                    error <= 1; done <= 1; state <= FINISHED;
                end else begin
                    if (sector_valid) begin
                        if (sector_index != expected_index) bad_stream <= 1;
                        expected_index <= expected_index + 1'b1;
                        if (!hit && !ended) begin
                            case (offset)
                                0: begin
                                    first_byte <= sector_data;
                                    name_bytes[63:56] <= sector_data;
                                    if (sector_data == 0) ended <= 1;
                                end
                                1: name_bytes[55:48] <= sector_data;
                                2: name_bytes[47:40] <= sector_data;
                                3: name_bytes[39:32] <= sector_data;
                                4: name_bytes[31:24] <= sector_data;
                                5: name_bytes[23:16] <= sector_data;
                                6: name_bytes[15:8] <= sector_data;
                                7: name_bytes[7:0] <= sector_data;
                                8: ext0 <= sector_data;
                                9: ext1 <= sector_data;
                                10: ext2 <= sector_data;
                                11: attribute <= sector_data;
                                20: entry_cluster[23:16] <= sector_data;
                                21: entry_cluster[31:24] <= sector_data;
                                26: entry_cluster[7:0] <= sector_data;
                                27: entry_cluster[15:8] <= sector_data;
                                28: entry_size[7:0] <= sector_data;
                                29: entry_size[15:8] <= sector_data;
                                30: entry_size[23:16] <= sector_data;
                                31: begin
                                    entry_size[31:24] <= sector_data;
                                    if (bmp_entry) begin
                                        hit <= 1;
                                        if (entry_cluster < 2 || {sector_data,entry_size[23:0]} == 0)
                                            bad_file <= 1;
                                        else begin
                                            file_cluster <= entry_cluster;
                                            file_size <= {sector_data,entry_size[23:0]};
                                        end
                                    end
                                end
                                default: ;
                            endcase
                        end
                    end
                    if (sector_done) begin
                        if (bad_stream || expected_index != 512 || bad_file) begin
                            error <= 1; done <= 1; state <= FINISHED;
                        end else if (hit) begin
                            found <= 1; done <= 1; state <= FINISHED;
                        end else if (ended) begin
                            end_of_dir <= 1; done <= 1; state <= FINISHED;
                        end else if (sector_number + 1'b1 == sectors_per_cluster) begin
                            need_chain <= 1; done <= 1; state <= FINISHED;
                        end else begin
                            sector_number <= sector_number + 1'b1; state <= ISSUE;
                        end
                    end
                end
                FINISHED: state <= IDLE;
                default: begin error <= 1; done <= 1; state <= FINISHED; end
            endcase
        end
    end
endmodule
