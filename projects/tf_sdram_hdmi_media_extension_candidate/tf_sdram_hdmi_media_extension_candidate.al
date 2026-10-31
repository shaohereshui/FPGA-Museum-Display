<?xml version='1.0' encoding='utf-8'?>
<Project Version="3" Minor="2" Path=".">
    <Project_Created_Time>
  </Project_Created_Time>
    <TD_Version>6.2.168116</TD_Version>
    <Name>tf_sdram_hdmi_media_extension_candidate</Name>
    <HardWare>
        <Family>EG4</Family>
        <Device>EG4S20BG256</Device>
        <Speed />
    </HardWare>
    <Source_Files>
        <Verilog>
            <File Path="media_input_router.v">
                <FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&amp;R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="60" /></FileInfo>
            </File>
            <File Path="src/sdram/enc_file/global_def.v">
                <FileInfo>
                    <Attr Name="GlobalIncluded" Val="true" />
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="1" />
                </FileInfo>
            </File>
            <File Path="sd_spi_media_reader.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="2" />
                </FileInfo>
            </File>
            <File Path="../anlu_hdmi/fat32_mbr_partition.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="3" />
                </FileInfo>
            </File>
            <File Path="../anlu_hdmi/fat32_boot_sector.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="4" />
                </FileInfo>
            </File>
            <File Path="fat32_media_mount.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="5" />
                </FileInfo>
            </File>
            <File Path="fat32_media_finder.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="6" />
                </FileInfo>
            </File>
            <File Path="../anlu_hdmi/fat32_fat_entry_reader.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="7" />
                </FileInfo>
            </File>
            <File Path="fat32_media_stream.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="8" />
                </FileInfo>
            </File>
            <File Path="fat32_media_locator.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="9" />
                </FileInfo>
            </File>
            <File Path="bmp_stream_scaler.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="10" />
                </FileInfo>
            </File>
            <File Path="../anlu_hdmi/video_async_fifo.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="11" />
                </FileInfo>
            </File>
            <File Path="../anlu_hdmi/apug011_video_prefetch.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="12" />
                </FileInfo>
            </File>
            <File Path="hdmi_timing_media.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="13" />
                </FileInfo>
            </File>
            <File Path="tmds_encoder.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="14" />
                </FileInfo>
            </File>
            <File Path="../anlu_hdmi/tmds_serializer_5x.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="15" />
                </FileInfo>
            </File>
            <File Path="src/sdram/enc_file/sdr_init_ref.enc.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="16" />
                </FileInfo>
            </File>
            <File Path="src/sdram/enc_file/sdr_wrrd.enc.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="17" />
                </FileInfo>
            </File>
            <File Path="src/sdram/enc_file/sdr_as_ram.enc.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="18" />
                </FileInfo>
            </File>
            <File Path="al_ip/sys_pll.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="19" />
                </FileInfo>
            </File>
            <File Path="al_ip/hdmi_video_pll27.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="20" />
                </FileInfo>
            </File>
            <File Path="al_ip/sd_tf_pll.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="21" />
                </FileInfo>
            </File>
            <File Path="tf_sdram_frame_writer.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="22" />
                </FileInfo>
            </File>
            <File Path="key_debounce.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="23" />
                </FileInfo>
            </File>
            <File Path="media_control.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="24" />
                </FileInfo>
            </File>
            <File Path="image_select_control.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="25" />
                </FileInfo>
            </File>
            <File Path="pcm_48khz_tick.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="26" />
                </FileInfo>
            </File>
            <File Path="../hdmi_audio_probe/hdmi_terc4_encoder.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="26" />
                </FileInfo>
            </File>
            <File Path="../hdmi_audio_probe/hdmi_audio_sample_packet.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="27" />
                </FileInfo>
            </File>
            <File Path="../hdmi_audio_probe/hdmi_audio_packet_assembler.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="28" />
                </FileInfo>
            </File>
            <File Path="hdmi_metadata_packets.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="29" />
                </FileInfo>
            </File>
            <File Path="hdmi_data_island_probe.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="30" />
                </FileInfo>
            </File>
            <File Path="hdmi_audio_video_boundary.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="31" />
                </FileInfo>
            </File>
            <File Path="hdmi_osd_5x7.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="32" />
                </FileInfo>
            </File>
            <File Path="audio_visualizer.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="33" />
                </FileInfo>
            </File>
            <File Path="tf_sdram_hdmi_media_core.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="34" />
                </FileInfo>
            </File>
            <File Path="tf_sdram_hdmi_media_top.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="35" />
                </FileInfo>
            </File>
            <File Path="wav_pcm_stream.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="36" />
                </FileInfo>
            </File>
            <File Path="wav_audio_player.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="37" />
                </FileInfo>
            </File>
            <File Path="pcm_volume_control.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="39" />
                </FileInfo>
            </File>
            <File Path="song_lyrics_rom.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="40" />
                </FileInfo>
            </File>
            <File Path="lyrics_overlay.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="41" />
                </FileInfo>
            </File>
            <File Path="audio_visual_link.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="46" />
                </FileInfo>
            </File>
            <File Path="fault_log.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="47" />
                </FileInfo>
            </File>
            <File Path="fade_transition.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="48" />
                </FileInfo>
            </File>
            <File Path="zoom_minimap.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="49" />
                </FileInfo>
            </File>
            <File Path="emergency_picture.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="50" />
                </FileInfo>
            </File>
            <File Path="apug011_transition_prefetch.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="42" />
                </FileInfo>
            </File>
            <File Path="audio_spectrum_fft.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="43" />
                </FileInfo>
            </File>
            <File Path="audio_spectrum_overlay.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="44" />
                </FileInfo>
            </File>
            <File Path="startup_ai_overlay.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="45" />
                </FileInfo>
            </File>
            <File Path="matrix_keypad.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="51" />
                </FileInfo>
            </File>
            <File Path="ir_nec_keys.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="52" />
                </FileInfo>
            </File>
            <File Path="eg4_light_sensor.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="53" />
                </FileInfo>
            </File>
            <File Path="ambient_brightness.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="design_1" />
                    <Attr Name="CompileOrder" Val="54" />
                </FileInfo>
            </File>
        <File Path="emergency_audio_mux.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&amp;R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="64" /></FileInfo></File><File Path="subtitle_uart.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&amp;R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="65" /></FileInfo></File><File Path="museum_subtitle.v"><FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&amp;R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="66" /></FileInfo></File><File Path="board_controls.v">
                <FileInfo><Attr Name="UsedInSyn" Val="true" /><Attr Name="UsedInP&amp;R" Val="true" /><Attr Name="BelongTo" Val="design_1" /><Attr Name="CompileOrder" Val="60" /></FileInfo>
            </File>
            </Verilog>
        <ADC_FILE>
            <File Path="tf_sdram_hdmi_media_extension_candidate.adc">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="constraint_1" />
                    <Attr Name="CompileOrder" Val="1" />
                </FileInfo>
            </File>
        </ADC_FILE>
        <SDC_FILE>
            <File Path="tf_sdram_hdmi_media_extension_candidate.sdc">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true" />
                    <Attr Name="UsedInP&amp;R" Val="true" />
                    <Attr Name="BelongTo" Val="constraint_1" />
                    <Attr Name="CompileOrder" Val="2" />
                </FileInfo>
            </File>
        </SDC_FILE>
    </Source_Files>
    <FileSets>
        <FileSet Name="design_1" Type="DesignFiles">
        </FileSet>
        <FileSet Name="constraint_1" Type="ConstrainFiles">
        </FileSet>
    </FileSets>
    <TOP_MODULE>
        <LABEL>tf_sdram_hdmi_media_top</LABEL>
        <MODULE>tf_sdram_hdmi_media_top</MODULE>
        <CREATEINDEX>user</CREATEINDEX>
    </TOP_MODULE>
    <Property>
    </Property>
    <Device_Settings>
    </Device_Settings>
    <Configurations>
    </Configurations>
    <Runs>
        <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="" Active="true">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
    </Runs>
    <Project_Settings>
    </Project_Settings>
</Project>