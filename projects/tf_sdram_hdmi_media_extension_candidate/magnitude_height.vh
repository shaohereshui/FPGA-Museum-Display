    // Logarithmic display compression makes quieter bands visible. Input
    // is the magnitude of volume-scaled PCM; no automatic gain normalization.
    function [6:0] magnitude_height;
        input [15:0] magnitude;
        integer k;
        reg [6:0] log_eighths;
        begin
            log_eighths=0;
            for(k=3;k<13;k=k+1)
                if(magnitude>=(1<<k))log_eighths=(k-3)*8+((magnitude>>(k-3))&7);
            if(magnitude>=8192)magnitude_height=72;
            else magnitude_height=(log_eighths*9)/10;
        end
    endfunction
