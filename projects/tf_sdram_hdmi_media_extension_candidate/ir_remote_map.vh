// Standard 17-key NEC direction/OK remote; command byte, LSB-first on wire.
// Confirm the actual remote on hardware. Change these values if necessary.
localparam [7:0] REMOTE_ADDRESS = 8'h00;
localparam [7:0] CMD_UP = 8'h46, CMD_DOWN = 8'h15;
localparam [7:0] CMD_LEFT = 8'h44, CMD_RIGHT = 8'h43, CMD_OK = 8'h40;
localparam [7:0] CMD_1 = 8'h16, CMD_2 = 8'h19, CMD_3 = 8'h0D;
localparam [7:0] CMD_4 = 8'h0C, CMD_5 = 8'h18, CMD_6 = 8'h5E;
localparam [7:0] CMD_7 = 8'h08, CMD_8 = 8'h1C, CMD_9 = 8'h5A;
localparam [7:0] CMD_STAR = 8'h42, CMD_0 = 8'h52, CMD_HASH = 8'h4A;
