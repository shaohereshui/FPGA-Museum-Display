// Two-sector MBR/VBR probe on the SDHC SPI reader's 50 MHz clock domain.
module fat32_media_mount #(
    parameter integer INIT_HALF = 125,
    parameter integer READ_HALF = 4,
    parameter integer TIMEOUT = 65535
) (
    input wire clk, rst_n, sd_miso,
    output wire sd_clk, sd_mosi, sd_ncs,
    input wire client_start, client_pause,
    input wire [31:0] client_sector,
    output wire client_ready, client_valid, client_done,
    output wire [8:0] client_index,
    output wire [7:0] client_data,
    output reg mounted,
    output reg [4:0] error_code, // 1-15: SD, 16: MBR, 17: VBR, 18: state
    output wire [7:0] sd_cmd0_r1,
    output wire [31:0] volume_lba, volume_sectors,
    output wire [31:0] fat_lba, data_lba, root_cluster, sectors_per_fat,
    output wire [7:0] sectors_per_cluster, fat_count
);
    localparam WAIT_CARD=0, ISSUE_MBR=1, WAIT_MBR=2,
               ISSUE_BOOT=3, WAIT_BOOT=4, MOUNTED=5, FAILED=6, CLIENT_READ=7;
    reg [2:0] state;
    reg sd_start;
    reg [31:0] sd_sector;
    wire sd_ready, sd_busy, sd_idle, sd_valid, sd_done;
    wire [8:0] sd_index;
    wire [7:0] sd_data;
    wire [3:0] sd_error;
    wire mbr_found, boot_accepted;
    assign client_ready = state == MOUNTED && sd_ready && sd_idle &&
                          !sd_busy && sd_error == 0;
    assign client_valid = state == CLIENT_READ && sd_valid;
    assign client_done = state == CLIENT_READ && sd_done;
    assign client_index = sd_index;
    assign client_data = sd_data;

    sd_spi_media_reader #(
        .INIT_HALF(INIT_HALF), .READ_HALF(READ_HALF), .TIMEOUT(TIMEOUT)
    ) sd_reader (
        .clk(clk), .rst_n(rst_n), .start(sd_start), .sector(sd_sector),
        .pause(state==CLIENT_READ && client_pause),
        .sd_miso(sd_miso), .sd_clk(sd_clk), .sd_mosi(sd_mosi),
        .sd_ncs(sd_ncs), .ready(sd_ready), .busy(sd_busy), .idle(sd_idle),
        .valid(sd_valid), .done(sd_done), .index(sd_index),
        .data(sd_data), .error(sd_error),
        .cmd0_r1(sd_cmd0_r1), .cmd8_r1(), .cmd8_r7(), .cmd17_r1(),
        .start_ack(), .debug_phase()
    );
    fat32_mbr_partition mbr (
        .clk(clk), .rst_n(rst_n),
        .valid(sd_valid && state == WAIT_MBR),
        .index(sd_index), .data(sd_data),
        .complete(), .found(mbr_found),
        .volume_lba(volume_lba), .volume_sectors(volume_sectors)
    );
    fat32_boot_sector boot (
        .clk(clk), .rst_n(rst_n),
        .valid(sd_valid && state == WAIT_BOOT),
        .index(sd_index), .data(sd_data),
        .volume_lba(volume_lba), .volume_sectors(volume_sectors),
        .complete(), .accepted(boot_accepted),
        .fat_lba(fat_lba), .data_lba(data_lba),
        .root_cluster(root_cluster), .sectors_per_fat(sectors_per_fat),
        .sectors_per_cluster(sectors_per_cluster), .fat_count(fat_count)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= WAIT_CARD; sd_start <= 0; sd_sector <= 0;
            mounted <= 0; error_code <= 0;
        end else begin
            sd_start <= 0;
            if (sd_error != 0 && state != FAILED) begin
                error_code <= {1'b0,sd_error};
                mounted <= 0;
                state <= FAILED;
            end else case (state)
                WAIT_CARD: if (sd_ready && sd_idle) state <= ISSUE_MBR;
                ISSUE_MBR: if (sd_idle) begin
                    sd_sector <= 0; sd_start <= 1; state <= WAIT_MBR;
                end
                WAIT_MBR: if (sd_done) begin
                    if (mbr_found) state <= ISSUE_BOOT;
                    else begin error_code <= 16; state <= FAILED; end
                end
                ISSUE_BOOT: if (sd_idle) begin
                    sd_sector <= volume_lba; sd_start <= 1; state <= WAIT_BOOT;
                end
                WAIT_BOOT: if (sd_done) begin
                    if (boot_accepted) begin mounted <= 1; state <= MOUNTED; end
                    else begin error_code <= 17; state <= FAILED; end
                end
                MOUNTED: if (client_start && client_ready) begin
                    sd_sector <= client_sector;
                    sd_start <= 1;
                    state <= CLIENT_READ;
                end
                CLIENT_READ: if (sd_done) state <= MOUNTED;
                FAILED: ;
                default: begin error_code <= 18; state <= FAILED; end
            endcase
        end
    end
endmodule
