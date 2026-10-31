// Mount an MBR FAT32 SDHC card, then follow the root directory FAT chain.
module fat32_media_locator #(
    parameter [63:0] TARGET_STEM = 64'd0,
    parameter integer DYNAMIC_TARGET = 0,
    parameter integer INIT_HALF = 125,
    parameter integer READ_HALF = 4,
    parameter integer TIMEOUT = 65535
) (
    input wire clk, rst_n, sd_miso,
    input wire restart,
    input wire [63:0] runtime_target,
    input wire [23:0] runtime_extension,
    input wire file_pause,
    output wire sd_clk, sd_mosi, sd_ncs,
    output wire mounted,
    output reg complete, found, end_of_dir,
    output wire need_chain, error,
    output wire [4:0] mount_error_code,
    output wire [7:0] sd_cmd0_r1,
    output wire [31:0] file_cluster, file_size,
    input wire file_start,
    output wire file_ready, file_valid, file_done, file_error,
    output wire [31:0] file_offset,
    output wire [7:0] file_data
);
    localparam WAIT_MOUNT=0, START_SCAN=1, WAIT_SCAN=2,
               START_FAT=3, WAIT_FAT=4, FINISHED=5;
    reg [2:0] state;
    reg local_error;
    reg file_active;
    reg [31:0] scan_cluster;
    reg [32:0] remaining_sectors;
    wire scan_done, scan_found, scan_end, scan_need_chain, scan_error;
    wire fat_done, fat_end, fat_error, fat_sector_start, scan_sector_start;
    wire [31:0] fat_next_cluster, fat_sector_lba, scan_sector_lba;
    wire stream_ready, stream_sector_start, stream_error;
    wire [31:0] stream_sector_lba;
    wire client_start, client_ready, client_valid, client_done;
    wire [31:0] client_sector, volume_lba, volume_sectors;
    wire [31:0] fat_lba, sectors_per_fat, data_lba, root_cluster;
    wire [7:0] sectors_per_cluster;
    wire [8:0] client_index;
    wire [7:0] client_data;

    wire scan_active = state == START_SCAN || state == WAIT_SCAN;
    wire fat_active = state == START_FAT || state == WAIT_FAT;
    assign need_chain = fat_active;
    assign error = mount_error_code != 0 || scan_error || fat_error || local_error;
    assign file_error = stream_error;
    assign file_ready = complete && found && !error && !file_active &&
                        stream_ready && client_ready && !stream_error;
    assign client_start = file_active ? stream_sector_start :
                          scan_active ? scan_sector_start : fat_active && fat_sector_start;
    assign client_sector = file_active ? stream_sector_lba :
                           scan_active ? scan_sector_lba : fat_sector_lba;

    fat32_media_mount #(
        .INIT_HALF(INIT_HALF), .READ_HALF(READ_HALF), .TIMEOUT(TIMEOUT)
    ) mount (
        .clk(clk), .rst_n(rst_n), .sd_miso(sd_miso),
        .sd_clk(sd_clk), .sd_mosi(sd_mosi), .sd_ncs(sd_ncs),
        .client_start(client_start), .client_sector(client_sector),
        .client_pause(file_active && file_pause),
        .client_ready(client_ready), .client_valid(client_valid),
        .client_done(client_done), .client_index(client_index),
        .client_data(client_data), .mounted(mounted),
        .error_code(mount_error_code), .sd_cmd0_r1(sd_cmd0_r1), .volume_lba(volume_lba),
        .volume_sectors(volume_sectors), .fat_lba(fat_lba), .data_lba(data_lba),
        .root_cluster(root_cluster), .sectors_per_fat(sectors_per_fat),
        .sectors_per_cluster(sectors_per_cluster), .fat_count()
    );

    fat32_media_finder #(.TARGET_STEM(TARGET_STEM), .DYNAMIC_TARGET(DYNAMIC_TARGET)) finder (
        .clk(clk), .rst_n(rst_n), .start(state == START_SCAN),
        .runtime_target(runtime_target), .runtime_extension(runtime_extension),
        .volume_lba(volume_lba), .volume_sectors(volume_sectors),
        .data_lba(data_lba), .root_cluster(scan_cluster),
        .sectors_per_cluster(sectors_per_cluster),
        .sector_ready(client_ready && scan_active),
        .sector_valid(client_valid && scan_active),
        .sector_done(client_done && scan_active),
        .reader_error(mount_error_code != 0),
        .sector_index(client_index), .sector_data(client_data),
        .sector_start(scan_sector_start), .sector_lba(scan_sector_lba),
        .done(scan_done), .found(scan_found), .end_of_dir(scan_end),
        .need_chain(scan_need_chain), .error(scan_error),
        .file_cluster(file_cluster), .file_size(file_size)
    );

    fat32_fat_entry_reader fat_reader (
        .clk(clk), .rst_n(rst_n), .start(state == START_FAT),
        .fat_lba(fat_lba), .sectors_per_fat(sectors_per_fat),
        .cluster(scan_cluster), .sector_ready(client_ready && fat_active),
        .sector_valid(client_valid && fat_active),
        .sector_done(client_done && fat_active),
        .reader_error(mount_error_code != 0),
        .sector_index(client_index), .sector_data(client_data),
        .ready(), .sector_start(fat_sector_start),
        .sector_lba(fat_sector_lba), .done(fat_done),
        .end_of_chain(fat_end), .error(fat_error),
        .next_cluster(fat_next_cluster)
    );

    fat32_media_stream stream (
        .clk(clk), .rst_n(rst_n), .start(file_start && file_ready),
        .volume_lba(volume_lba), .volume_sectors(volume_sectors),
        .data_lba(data_lba), .fat_lba(fat_lba),
        .sectors_per_fat(sectors_per_fat),
        .sectors_per_cluster(sectors_per_cluster),
        .first_cluster(file_cluster), .file_size(file_size),
        .sector_ready(client_ready && file_active),
        .sector_valid(client_valid && file_active),
        .sector_done(client_done && file_active),
        .reader_error(mount_error_code != 0),
        .sector_index(client_index), .sector_data(client_data),
        .ready(stream_ready), .sector_start(stream_sector_start),
        .sector_lba(stream_sector_lba), .file_valid(file_valid),
        .file_offset(file_offset), .file_data(file_data),
        .done(file_done), .error(stream_error)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= WAIT_MOUNT; scan_cluster <= 0; remaining_sectors <= 0;
            complete <= 0; found <= 0; end_of_dir <= 0; local_error <= 0;
            file_active <= 0;
        end else begin
            if (file_start && file_ready) file_active <= 1;
            else if (file_done) file_active <= 0;
            if (restart === 1'b1 && state == FINISHED && !file_active) begin
                complete <= 0;
                found <= 0;
                end_of_dir <= 0;
                local_error <= 0;
                scan_cluster <= root_cluster;
                remaining_sectors <= {1'b0,volume_lba} + volume_sectors - data_lba;
                state <= START_SCAN;
            end else case (state)
                WAIT_MOUNT: if (mount_error_code != 0) begin
                    complete <= 1; state <= FINISHED;
                end else if (mounted) begin
                    scan_cluster <= root_cluster;
                    remaining_sectors <= {1'b0,volume_lba} + volume_sectors - data_lba;
                    state <= START_SCAN;
                end
                START_SCAN: state <= WAIT_SCAN;
                WAIT_SCAN: if (scan_done) begin
                    if (scan_error) begin
                        local_error <= 1; complete <= 1; state <= FINISHED;
                    end else if (scan_found) begin
                        found <= 1; complete <= 1; state <= FINISHED;
                    end else if (scan_end) begin
                        end_of_dir <= 1; complete <= 1; state <= FINISHED;
                    end else if (scan_need_chain) state <= START_FAT;
                    else begin local_error <= 1; complete <= 1; state <= FINISHED; end
                end
                START_FAT: state <= WAIT_FAT;
                WAIT_FAT: if (fat_done) begin
                    if (fat_error) begin
                        local_error <= 1; complete <= 1; state <= FINISHED;
                    end else if (fat_end) begin
                        end_of_dir <= 1; complete <= 1; state <= FINISHED;
                    end else if (remaining_sectors <= sectors_per_cluster) begin
                        local_error <= 1; complete <= 1; state <= FINISHED;
                    end else begin
                        remaining_sectors <= remaining_sectors - sectors_per_cluster;
                        scan_cluster <= fat_next_cluster; state <= START_SCAN;
                    end
                end
                FINISHED: ;
                default: begin local_error <= 1; complete <= 1; state <= FINISHED; end
            endcase
        end
    end
endmodule
