// Select the first valid FAT32 primary partition (types 0x0b/0x0c) from LBA 0.
module fat32_mbr_partition (
    input wire clk, rst_n, valid,
    input wire [8:0] index,
    input wire [7:0] data,
    output reg complete, found,
    output reg [31:0] volume_lba, volume_sectors
);
    reg invalid, selected;
    reg [8:0] next_index;
    reg [7:0] entry_type;
    reg [31:0] entry_lba, entry_sectors;
    reg [31:0] selected_lba, selected_sectors;
    wire in_table = index >= 9'd446 && index < 9'd510;
    wire [3:0] entry_offset = index[3:0] - 4'd14;
    wire [31:0] entry_size = {data,entry_sectors[23:0]};
    wire [32:0] end_lba = {1'b0,entry_lba} + {1'b0,entry_size};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            complete <= 0; found <= 0; invalid <= 0; selected <= 0;
            next_index <= 0; entry_type <= 0; entry_lba <= 0;
            entry_sectors <= 0; selected_lba <= 0; selected_sectors <= 0;
            volume_lba <= 0; volume_sectors <= 0;
        end else begin
            complete <= 0;
            if (valid) begin
                if (index == 0) begin
                    found <= 0; invalid <= 0; selected <= 0; next_index <= 1;
                    entry_type <= 0; entry_lba <= 0; entry_sectors <= 0;
                end else begin
                    if (index != next_index) invalid <= 1;
                    next_index <= index + 1'b1;
                    if (in_table) begin
                        case (entry_offset)
                            0: begin
                                entry_type <= 0; entry_lba <= 0; entry_sectors <= 0;
                            end
                            4: entry_type <= data;
                            8: entry_lba[7:0] <= data;
                            9: entry_lba[15:8] <= data;
                            10: entry_lba[23:16] <= data;
                            11: entry_lba[31:24] <= data;
                            12: entry_sectors[7:0] <= data;
                            13: entry_sectors[15:8] <= data;
                            14: entry_sectors[23:16] <= data;
                            15: if (!selected && (entry_type == 8'h0b || entry_type == 8'h0c) &&
                                    entry_lba != 0 && entry_size != 0 &&
                                    end_lba <= 33'h100000000) begin
                                selected <= 1;
                                selected_lba <= entry_lba;
                                selected_sectors <= entry_size;
                            end
                            default: ;
                        endcase
                    end else if (index == 510) begin
                        if (data != 8'h55) invalid <= 1;
                    end else if (index == 511) begin
                        complete <= 1;
                        found <= !invalid && index == next_index &&
                                 data == 8'haa && selected;
                        if (!invalid && index == next_index &&
                            data == 8'haa && selected) begin
                            volume_lba <= selected_lba;
                            volume_sectors <= selected_sectors;
                        end
                    end
                end
            end
        end
    end
endmodule
