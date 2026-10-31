// Read one FAT32 FAT1 entry through the mounted 512-byte sector interface.
module fat32_fat_entry_reader (
    input wire clk, rst_n, start,
    input wire [31:0] fat_lba, sectors_per_fat, cluster,
    input wire sector_ready, sector_valid, sector_done, reader_error,
    input wire [8:0] sector_index,
    input wire [7:0] sector_data,
    output wire ready, sector_start,
    output wire [31:0] sector_lba,
    output reg done, end_of_chain, error,
    output reg [31:0] next_cluster
);
    localparam IDLE=0, ISSUE=1, READ=2, FINISHED=3;
    reg [1:0] state;
    reg [8:0] entry_offset;
    reg [9:0] expected_index;
    reg bad_stream;
    reg [31:0] entry;
    reg [31:0] requested_lba;
    wire [20:0] fat_sector_offset = cluster[27:7];
    wire [32:0] fat_sector = {1'b0,fat_lba} + {12'b0,fat_sector_offset};
    wire [27:0] entry_cluster = entry[27:0];

    assign ready = state == IDLE;
    assign sector_start = state == ISSUE && sector_ready && !reader_error;
    assign sector_lba = requested_lba;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; entry_offset <= 0; expected_index <= 0;
            bad_stream <= 0; entry <= 0; requested_lba <= 0;
            done <= 0; end_of_chain <= 0; error <= 0; next_cluster <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: if (start) begin
                    end_of_chain <= 0; error <= 0; next_cluster <= 0;
                    if (cluster < 2 || cluster >= 32'h0ffffff0 ||
                        fat_sector_offset >= sectors_per_fat ||
                        fat_sector > 33'h0ffffffff) begin
                        error <= 1; done <= 1; state <= FINISHED;
                    end else begin
                        requested_lba <= fat_sector[31:0];
                        entry_offset <= {cluster[6:0],2'b00};
                        state <= ISSUE;
                    end
                end
                ISSUE: if (reader_error) begin
                    error <= 1; done <= 1; state <= FINISHED;
                end else if (sector_ready) begin
                    expected_index <= 0; bad_stream <= 0; entry <= 0;
                    state <= READ;
                end
                READ: if (reader_error) begin
                    error <= 1; done <= 1; state <= FINISHED;
                end else begin
                    if (sector_valid) begin
                        if (sector_index != expected_index) bad_stream <= 1;
                        expected_index <= expected_index + 1'b1;
                        if (sector_index == entry_offset) entry[7:0] <= sector_data;
                        if (sector_index == entry_offset + 1'b1) entry[15:8] <= sector_data;
                        if (sector_index == entry_offset + 2'd2) entry[23:16] <= sector_data;
                        if (sector_index == entry_offset + 2'd3) entry[31:24] <= sector_data;
                    end
                    if (sector_done) begin
                        done <= 1;
                        state <= FINISHED;
                        if (bad_stream || expected_index != 512) error <= 1;
                        else if (entry_cluster >= 28'hffffff8) end_of_chain <= 1;
                        else if (entry_cluster < 2 || entry_cluster >= 28'hffffff0 ||
                                 entry_cluster == cluster[27:0] ||
                                 {11'b0,entry_cluster[27:7]} >= sectors_per_fat)
                            error <= 1;
                        else next_cluster <= {4'b0,entry_cluster};
                    end
                end
                FINISHED: state <= IDLE;
                default: begin error <= 1; done <= 1; state <= FINISHED; end
            endcase
        end
    end
endmodule
