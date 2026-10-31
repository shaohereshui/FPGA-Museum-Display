// Parses one FAT32 volume boot sector supplied as ordered bytes 0..511.
// volume_lba is the already-known start of the volume, not the MBR sector.
module fat32_boot_sector (
    input wire clk, rst_n, valid,
    input wire [8:0] index,
    input wire [7:0] data,
    input wire [31:0] volume_lba, volume_sectors,
    output reg complete, accepted,
    output reg [31:0] fat_lba, data_lba, root_cluster, sectors_per_fat,
    output reg [7:0] sectors_per_cluster, fat_count
);
    reg invalid;
    reg [8:0] next_index;
    reg [15:0] bytes_build, reserved_build, root_entries_build;
    reg [15:0] total16_build, fat16_build, version_build;
    reg [7:0] cluster_size_build, fat_count_build;
    reg [31:0] total_build, fat_size_build, root_build;
    wire [39:0] fat_span = {32'b0,fat_count_build} * {8'b0,fat_size_build};
    wire [39:0] data_relative = {24'b0,reserved_build} + fat_span;
    wire [39:0] fat_absolute = {8'b0,volume_lba} + reserved_build;
    wire [39:0] data_absolute = {8'b0,volume_lba} + data_relative;
    wire [39:0] data_sectors = {8'b0,total_build} - data_relative;
    wire [32:0] volume_end = {1'b0,volume_lba} + {1'b0,volume_sectors};
    wire layout_ok = bytes_build == 512 && reserved_build != 0 &&
        cluster_size_build != 0 && cluster_size_build <= 128 &&
        (cluster_size_build & (cluster_size_build - 1'b1)) == 0 &&
        fat_count_build != 0 && root_entries_build == 0 &&
        total16_build == 0 && fat16_build == 0 && version_build == 0 &&
        fat_size_build != 0 && root_build >= 2 &&
        volume_sectors != 0 && total_build <= volume_sectors &&
        volume_end <= 33'h100000000 &&
        {8'b0,total_build} > data_relative &&
        data_sectors >= 40'd65525 * cluster_size_build &&
        fat_absolute <= 40'h00ffffffff && data_absolute <= 40'h00ffffffff;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            complete <= 0; accepted <= 0; invalid <= 0; next_index <= 0;
            fat_lba <= 0; data_lba <= 0; root_cluster <= 0;
            sectors_per_fat <= 0; sectors_per_cluster <= 0; fat_count <= 0;
            bytes_build <= 0; reserved_build <= 0; root_entries_build <= 0;
            total16_build <= 0; fat16_build <= 0; version_build <= 0;
            cluster_size_build <= 0; fat_count_build <= 0;
            total_build <= 0; fat_size_build <= 0; root_build <= 0;
        end else begin
            complete <= 0;
            if (valid) begin
                if (index == 0) begin
                    accepted <= 0; invalid <= 0; next_index <= 1;
                    bytes_build <= 0; reserved_build <= 0; root_entries_build <= 0;
                    total16_build <= 0; fat16_build <= 0; version_build <= 0;
                    cluster_size_build <= 0; fat_count_build <= 0;
                    total_build <= 0; fat_size_build <= 0; root_build <= 0;
                end else begin
                    if (index != next_index) invalid <= 1;
                    next_index <= index + 1'b1;
                    case (index)
                        11: bytes_build[7:0] <= data;
                        12: bytes_build[15:8] <= data;
                        13: cluster_size_build <= data;
                        14: reserved_build[7:0] <= data;
                        15: reserved_build[15:8] <= data;
                        16: fat_count_build <= data;
                        17: root_entries_build[7:0] <= data;
                        18: root_entries_build[15:8] <= data;
                        19: total16_build[7:0] <= data;
                        20: total16_build[15:8] <= data;
                        22: fat16_build[7:0] <= data;
                        23: fat16_build[15:8] <= data;
                        32: total_build[7:0] <= data;
                        33: total_build[15:8] <= data;
                        34: total_build[23:16] <= data;
                        35: total_build[31:24] <= data;
                        36: fat_size_build[7:0] <= data;
                        37: fat_size_build[15:8] <= data;
                        38: fat_size_build[23:16] <= data;
                        39: fat_size_build[31:24] <= data;
                        42: version_build[7:0] <= data;
                        43: version_build[15:8] <= data;
                        44: root_build[7:0] <= data;
                        45: root_build[15:8] <= data;
                        46: root_build[23:16] <= data;
                        47: root_build[31:24] <= data;
                        510: if (data != 8'h55) invalid <= 1;
                        511: begin
                            complete <= 1;
                            accepted <= !invalid && index == next_index &&
                                        data == 8'haa && layout_ok;
                            if (!invalid && index == next_index &&
                                data == 8'haa && layout_ok) begin
                                fat_lba <= fat_absolute[31:0];
                                data_lba <= data_absolute[31:0];
                                root_cluster <= root_build;
                                sectors_per_fat <= fat_size_build;
                                sectors_per_cluster <= cluster_size_build;
                                fat_count <= fat_count_build;
                            end
                        end
                        default: ;
                    endcase
                end
            end
        end
    end
endmodule
