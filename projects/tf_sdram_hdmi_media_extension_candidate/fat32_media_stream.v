// Stream a FAT32 file in offset order through a mounted single-sector reader.
// The consumer must accept every file_valid byte; there is no backpressure.
module fat32_media_stream (
    input wire clk, rst_n, start,
    input wire [31:0] volume_lba, volume_sectors, data_lba,
    input wire [31:0] fat_lba, sectors_per_fat,
    input wire [7:0] sectors_per_cluster,
    input wire [31:0] first_cluster, file_size,
    input wire sector_ready, sector_valid, sector_done, reader_error,
    input wire [8:0] sector_index,
    input wire [7:0] sector_data,
    output wire ready, sector_start,
    output wire [31:0] sector_lba,
    output wire file_valid,
    output wire [31:0] file_offset,
    output wire [7:0] file_data,
    output reg done, error
);
    localparam IDLE=0, CHECK=1, ISSUE=2, READ=3,
               START_FAT=4, WAIT_FAT=5, FINISHED=6;
    reg [2:0] state;
    reg [31:0] cluster, sent;
    reg [7:0] sector_number;
    reg [9:0] expected_index;
    reg bad_stream;
    wire fat_active = state == START_FAT || state == WAIT_FAT;
    wire fat_start, fat_done, fat_end, fat_error;
    wire [31:0] fat_sector_lba, next_cluster;
    wire [39:0] cluster_lba = {8'b0,data_lba} +
        ({8'b0,cluster} - 40'd2) * sectors_per_cluster;
    wire [32:0] volume_end = {1'b0,volume_lba} + volume_sectors;
    wire [39:0] cluster_end = cluster_lba + sectors_per_cluster;

    assign ready = state == IDLE;
    assign sector_start = (state == ISSUE && sector_ready && !reader_error) ||
                          (fat_active && fat_start);
    assign sector_lba = fat_active ? fat_sector_lba : cluster_lba[31:0] + sector_number;
    assign file_valid = state == READ && sector_valid && sent < file_size;
    assign file_offset = sent;
    assign file_data = sector_data;

    fat32_fat_entry_reader fat_reader (
        .clk(clk), .rst_n(rst_n), .start(state == START_FAT),
        .fat_lba(fat_lba), .sectors_per_fat(sectors_per_fat),
        .cluster(cluster), .sector_ready(sector_ready && fat_active),
        .sector_valid(sector_valid && fat_active),
        .sector_done(sector_done && fat_active), .reader_error(reader_error),
        .sector_index(sector_index), .sector_data(sector_data),
        .ready(), .sector_start(fat_start), .sector_lba(fat_sector_lba),
        .done(fat_done), .end_of_chain(fat_end), .error(fat_error),
        .next_cluster(next_cluster)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; cluster <= 0; sent <= 0;
            sector_number <= 0; expected_index <= 0; bad_stream <= 0;
            done <= 0; error <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: if (start) begin
                    cluster <= first_cluster; sent <= 0; sector_number <= 0;
                    error <= 0; state <= CHECK;
                    if (file_size == 0) begin error <= 1; done <= 1; state <= FINISHED; end
                end
                CHECK: if (cluster < 2 || cluster >= 32'h0ffffff0 ||
                           sectors_per_cluster == 0 ||
                           cluster_lba > 40'h00ffffffff ||
                           cluster_end > {7'b0,volume_end} ||
                           cluster_lba < data_lba) begin
                    error <= 1; done <= 1; state <= FINISHED;
                end else state <= ISSUE;
                ISSUE: if (reader_error) begin
                    error <= 1; done <= 1; state <= FINISHED;
                end else if (sector_ready) begin
                    expected_index <= 0; bad_stream <= 0; state <= READ;
                end
                READ: if (reader_error) begin
                    error <= 1; done <= 1; state <= FINISHED;
                end else begin
                    if (sector_valid) begin
                        if (sector_index != expected_index) bad_stream <= 1;
                        expected_index <= expected_index + 1'b1;
                        if (sent < file_size) sent <= sent + 1'b1;
                    end
                    if (sector_done) begin
                        if (bad_stream || expected_index != 512) begin
                            error <= 1; done <= 1; state <= FINISHED;
                        end else if (sent == file_size) begin
                            done <= 1; state <= FINISHED;
                        end else if (sector_number + 1'b1 == sectors_per_cluster) begin
                            state <= START_FAT;
                        end else begin
                            sector_number <= sector_number + 1'b1; state <= ISSUE;
                        end
                    end
                end
                START_FAT: state <= WAIT_FAT;
                WAIT_FAT: if (fat_done) begin
                    if (fat_error || fat_end) begin
                        error <= 1; done <= 1; state <= FINISHED;
                    end else begin
                        cluster <= next_cluster; sector_number <= 0; state <= CHECK;
                    end
                end
                FINISHED: state <= IDLE;
                default: begin error <= 1; done <= 1; state <= FINISHED; end
            endcase
        end
    end
endmodule
