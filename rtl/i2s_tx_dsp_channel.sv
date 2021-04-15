
module i2s_tx_dsp_channel (
  input  logic                    sck_i,
  input  logic                    rstn_i,
  output logic                    i2s_ch0_o,
  output logic                    i2s_ch1_o,
  input  logic                    i2s_ws_i,
  input  logic             [31:0] fifo_data_i,
  input  logic                    fifo_data_valid_i,
  output logic                    fifo_data_ready_o,
  output logic                    master_ready_to_send,
  output logic                    fifo_err_o,
  input  logic                    cfg_en_i,
  input  logic                    cfg_2ch_i,
  input  logic              [4:0] cfg_num_bits_i,
  input  logic              [3:0] cfg_num_word_i,
  input  logic                    cfg_lsb_first_i,
  input  logic                    cfg_master_dsp_mode_i,
  input  logic              [8:0] cfg_master_dsp_offset_i
);


  logic [31:0] r_shiftreg_ch0;
  logic [31:0] r_shiftreg_ch1;
  logic [31:0] s_shiftreg_ch0;
  logic [31:0] s_shiftreg_ch1;
  logic [31:0] r_shiftreg_shadow;
  logic [31:0] s_shiftreg_shadow;

  logic        data_ready;
  logic        s_sample_sr0;
  logic        s_sample_sr1;
  logic        s_sample_swd;

  logic        set_offset;
  logic        en_offset;
  logic        clear_offset;
  logic        check_offset;


  logic [4:0]  r_count_bit;
  logic [8:0]  r_count_offset;

  logic        s_word_done;
  logic        s_word_done_pre;


  enum  {ST_START,ST_SAMPLE,ST_WAIT,ST_RUNNING} state,next_state;


  assign s_word_done     = cfg_lsb_first_i?  r_count_bit == cfg_num_bits_i  : r_count_bit == 'h0;
  assign s_word_done_pre = cfg_lsb_first_i?  r_count_bit == cfg_num_bits_i-1 : r_count_bit == 'h1;

  assign fifo_data_ready_o = data_ready;

  assign check_offset = set_offset ^ clear_offset;

  always_comb begin : proc_SM
    s_shiftreg_ch0    = r_shiftreg_ch0;
    s_shiftreg_ch1    = r_shiftreg_ch1;
    s_shiftreg_shadow = r_shiftreg_shadow;

    s_sample_sr0 = 1'b0;
    s_sample_sr1 = 1'b0;
    s_sample_swd = 1'b0;
    data_ready   = 1'b0;

    case(state)

      ST_START:
        begin
          set_offset=1'b0;

          if(cfg_en_i==1'b0)
            next_state= ST_START;
          else begin
            if(fifo_data_valid_i == 1'b1)
              begin
                data_ready    = 1'b1;
                s_sample_sr0   = 1'b1;
                s_shiftreg_ch0 = fifo_data_i;
                next_state = ST_SAMPLE;
              end else begin
              data_ready    = 1'b0;
              s_sample_sr0   = 1'b0;
              next_state = ST_START;
            end
          end
        end

      ST_SAMPLE:
        begin
          if(cfg_en_i==1'b0)
            next_state= ST_START;
          else begin
            if(fifo_data_valid_i== 1'b1)
              begin
                data_ready    = 1'b1;
                s_sample_sr1   = 1'b1;
                s_shiftreg_ch1 = fifo_data_i;
                next_state = ST_WAIT;
              end else begin
              data_ready    = 1'b0;
              s_sample_sr1   = 1'b0;
              next_state = ST_SAMPLE;
            end
          end
        end

      ST_WAIT:
        begin
          if(cfg_en_i==1'b0)
            next_state= ST_START;
          else begin
            if(i2s_ws_i== 1'b1)
              next_state = ST_RUNNING;
            if(cfg_master_dsp_offset_i!=9'b0)
              set_offset=1'b1;
            else
              set_offset=1'b0;
          end
        end

      ST_RUNNING:
        begin
          s_sample_sr0 = 1'b1;
          s_sample_sr1 = cfg_2ch_i;

          if(cfg_en_i==1'b0)
            next_state= ST_START;
          else begin

            //set_offset=1'b1;
            if(check_offset==1'b0)  begin
              //set_offset=1'b0;

              if(s_word_done_pre== 1'b1)
                begin
                  if(cfg_2ch_i== 1'b1)
                    begin
                      data_ready    = 1'b1;
                      if(fifo_data_valid_i == 1'b1)
                        s_shiftreg_shadow = fifo_data_i;
                      s_sample_swd      = 1'b1;
                    end else begin
                    data_ready    = 1'b0;
                    s_sample_swd      = 1'b0;
                  end
                end

              if(s_word_done== 1'b1)
                begin
                  data_ready = 1'b1;
                  if(cfg_2ch_i== 1'b1)
                    s_shiftreg_ch0 = r_shiftreg_shadow;
                  else
                    s_shiftreg_ch0 = r_shiftreg_ch1;
                  s_sample_sr1 = 1'b1;
                  if(fifo_data_valid_i == 1'b1)
                    s_shiftreg_ch1 = fifo_data_i;
                end
            end
          end
        end
    endcase // state
  end

  //DSP_MODE=1
  always_ff  @(posedge sck_i, negedge rstn_i)
    begin
      if (rstn_i == 1'b0 | cfg_en_i== 1'b0) begin
        state <= ST_START;
        master_ready_to_send <= 1'b0;
      end else begin
        if (cfg_master_dsp_mode_i == 1'b1) begin
          if (next_state==ST_WAIT)
            master_ready_to_send <= 1'b1;
          else
            master_ready_to_send <= master_ready_to_send;
          state <= next_state;
        end
      end
    end

  //DSP_MODE=0
  always_ff  @(negedge sck_i, negedge rstn_i)
    begin
      if (cfg_en_i== 1'b0) begin
        state <= ST_START;
        master_ready_to_send <= 1'b0;
      end else begin
        if (cfg_master_dsp_mode_i == 1'b0) begin
          if (next_state==ST_WAIT)
            master_ready_to_send <= 1'b1;
          else
            master_ready_to_send <= master_ready_to_send;
          state <= next_state;
        end
      end
    end

  //DSP_MODE=1
  always_ff  @(posedge sck_i, negedge rstn_i)
    begin
      if (rstn_i == 1'b0)
        begin
          r_shiftreg_ch0  <=  'h0;
          r_shiftreg_ch1  <=  'h0;
          r_shiftreg_shadow <= 'h0;
        end
      else
        begin

          // if (cfg_master_dsp_mode_i == 1'b1) begin
          if(s_sample_sr0==1'b1)
            r_shiftreg_ch0  <= s_shiftreg_ch0;
          else
            r_shiftreg_ch0  <= r_shiftreg_ch0;

          if(s_sample_sr1==1'b1)
            r_shiftreg_ch1  <= s_shiftreg_ch1;
          else
            r_shiftreg_ch1  <= r_shiftreg_ch1;

          if(s_sample_swd==1'b1)
            r_shiftreg_shadow  <= s_shiftreg_shadow;
          else
            r_shiftreg_shadow  <= r_shiftreg_shadow;
          //end
        end
    end

  //DSP_MODE=0
  always_ff  @(negedge sck_i, negedge rstn_i)
    begin
      if (cfg_master_dsp_mode_i == 1'b0) begin
        if(s_sample_sr0==1'b1)
          r_shiftreg_ch0  <= s_shiftreg_ch0;
        else
          r_shiftreg_ch0  <= r_shiftreg_ch0;

        if(s_sample_sr1==1'b1)
          r_shiftreg_ch1  <= s_shiftreg_ch1;
        else
          r_shiftreg_ch1  <= r_shiftreg_ch1;

        if(s_sample_swd==1'b1)
          r_shiftreg_shadow  <= s_shiftreg_shadow;
        else
          r_shiftreg_shadow  <= r_shiftreg_shadow;
      end

    end

  //DSP_MODE=1
  always_ff  @(posedge sck_i, negedge rstn_i)
    begin
      if (rstn_i == 1'b0 | cfg_en_i== 1'b0)
        begin
          r_count_bit <= 'h0;
          r_count_offset <= 'h0;
          clear_offset <= 1'b0;
          en_offset <= 1'b0;

          i2s_ch0_o <= 'h0;
          i2s_ch1_o <= 'h0;
        end
      else
        begin
          if (cfg_master_dsp_mode_i == 1'b1) begin
            if( (next_state== ST_RUNNING & i2s_ws_i== 1'b1 & cfg_master_dsp_offset_i!=9'b0 & check_offset==1'b1) | en_offset==1'b1) begin
              //count offset
              if (r_count_offset+1==cfg_master_dsp_offset_i) begin
                clear_offset <= 1'b1;
                en_offset <= 1'b0;

                if (cfg_lsb_first_i==1'b0) begin
                  r_count_bit <= cfg_num_bits_i;

                  i2s_ch0_o <= r_shiftreg_ch0[cfg_num_bits_i];
                  i2s_ch1_o <= r_shiftreg_ch1[cfg_num_bits_i];

                end else begin
                  r_count_bit <= 'h0;

                  i2s_ch0_o <= r_shiftreg_ch0[0];
                  i2s_ch1_o <= r_shiftreg_ch1[0];
                end
              end else begin
                r_count_offset <= r_count_offset + 1;
                en_offset <= 1'b1;
                clear_offset <= 1'b0;

                i2s_ch0_o <= 'h0;
                i2s_ch1_o <= 'h0;
              end
            end else begin
              //count num bits
              clear_offset <= clear_offset;

              if (next_state== ST_RUNNING & i2s_ws_i== 1'b1 | state == ST_RUNNING) begin

                if (cfg_lsb_first_i==1'b0) begin

                  if (r_count_bit=='h0) begin
                    r_count_bit <= cfg_num_bits_i;

                    i2s_ch0_o <= r_shiftreg_ch0[cfg_num_bits_i];
                    i2s_ch1_o <= r_shiftreg_ch1[cfg_num_bits_i];

                  end else begin
                    r_count_bit <= r_count_bit - 1;

                    i2s_ch0_o <= r_shiftreg_ch0[r_count_bit - 1];
                    i2s_ch1_o <= r_shiftreg_ch1[r_count_bit - 1];
                  end
                end else begin

                  if (r_count_bit==cfg_num_bits_i) begin
                    r_count_bit <= 'h0;
                    i2s_ch0_o <= r_shiftreg_ch0[0];
                    i2s_ch1_o <= r_shiftreg_ch1[0];

                  end else begin
                    r_count_bit <= r_count_bit + 1;

                    i2s_ch0_o <= r_shiftreg_ch0[r_count_bit + 1];
                    i2s_ch1_o <= r_shiftreg_ch1[r_count_bit + 1];

                  end
                end

              end else begin
                //set counter in state != run
                if (cfg_lsb_first_i==1'b0) begin
                  r_count_bit <= cfg_num_bits_i;

                end else begin
                  r_count_bit <= 'h0;

                end

              end
            end
          end
        end
    end

  //DSP_MODE=0
  always_ff  @(negedge sck_i, negedge rstn_i)
    begin
      if (cfg_en_i== 1'b0)
        begin
          r_count_bit <= 'h0;
          r_count_offset <= 'h0;
          clear_offset <= 1'b0;
          en_offset <= 1'b0;

          i2s_ch0_o <= 'h0;
          i2s_ch1_o <= 'h0;
        end
      else
        begin

          if (cfg_master_dsp_mode_i == 1'b0) begin
            if( (next_state== ST_RUNNING & i2s_ws_i== 1'b1 & cfg_master_dsp_offset_i!=9'b0 & check_offset==1'b1) | en_offset==1'b1) begin
              //count offset
              if (r_count_offset+1==cfg_master_dsp_offset_i) begin
                clear_offset <= 1'b1;
                en_offset <= 1'b0;

                if (cfg_lsb_first_i==1'b0) begin
                  r_count_bit <= cfg_num_bits_i;

                  i2s_ch0_o <= r_shiftreg_ch0[cfg_num_bits_i];
                  i2s_ch1_o <= r_shiftreg_ch1[cfg_num_bits_i];

                end else begin
                  r_count_bit <= 'h0;

                  i2s_ch0_o <= r_shiftreg_ch0[0];
                  i2s_ch1_o <= r_shiftreg_ch1[0];
                end
              end else begin
                r_count_offset <= r_count_offset + 1;
                en_offset <= 1'b1;
                clear_offset <= 1'b0;

                i2s_ch0_o <= 'h0;
                i2s_ch1_o <= 'h0;
              end
            end else begin
              //count num bits
              clear_offset <= clear_offset;

              if (next_state== ST_RUNNING & i2s_ws_i== 1'b1 | state == ST_RUNNING) begin

                if (cfg_lsb_first_i==1'b0) begin

                  if (r_count_bit=='h0) begin
                    r_count_bit <= cfg_num_bits_i;

                    i2s_ch0_o <= r_shiftreg_ch0[cfg_num_bits_i];
                    i2s_ch1_o <= r_shiftreg_ch1[cfg_num_bits_i];

                  end else begin
                    r_count_bit <= r_count_bit - 1;

                    i2s_ch0_o <= r_shiftreg_ch0[r_count_bit - 1];
                    i2s_ch1_o <= r_shiftreg_ch1[r_count_bit - 1];
                  end
                end else begin

                  if (r_count_bit==cfg_num_bits_i) begin
                    r_count_bit <= 'h0;
                    i2s_ch0_o <= r_shiftreg_ch0[0];
                    i2s_ch1_o <= r_shiftreg_ch1[0];

                  end else begin
                    r_count_bit <= r_count_bit + 1;

                    i2s_ch0_o <= r_shiftreg_ch0[r_count_bit + 1];
                    i2s_ch1_o <= r_shiftreg_ch1[r_count_bit + 1];

                  end
                end

              end else begin
                //set counter in state != run
                if (cfg_lsb_first_i==1'b0) begin
                  r_count_bit <= cfg_num_bits_i;
                end else begin
                  r_count_bit <= 'h0;
                end

              end
            end
          end
        end
    end
endmodule

