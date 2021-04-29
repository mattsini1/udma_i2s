

module i2s_rx_dsp_channel (
	input  logic                    sck_i,
	input  logic                    rstn_i,
	input  logic                    i2s_ch0_i,
	input  logic                    i2s_ch1_i,
	input  logic                    i2s_ws_i,
	output logic             [31:0] fifo_data_o,
	output logic                    fifo_data_valid_o,
	input  logic                    fifo_data_ready_i,
	output logic                    fifo_err_o,
	input  logic                    cfg_en_i,
	input  logic                    cfg_2ch_i,
	input  logic              [4:0] cfg_num_bits_i,
	input  logic              [3:0] cfg_num_word_i,
	input  logic                    cfg_lsb_first_i,
	input  logic                    cfg_rx_continuous_i,
	input  logic                    cfg_slave_dsp_mode_i,
	input  logic              [8:0] cfg_slave_dsp_offset_i
);

	logic [31:0] r_shiftreg_ch0, s_shiftreg_ch0;
	logic [31:0] r_shiftreg_ch1, s_shiftreg_ch1;

	logic [31:0] r_shiftreg_ch0_shadow, s_shiftreg_ch0_shadow;
	logic [31:0] r_shiftreg_ch1_shadow, s_shiftreg_ch1_shadow;

	logic [8:0]  r_count_offset, s_count_offset;

	logic [4:0]  r_count_bit, s_count_bit;
	logic [4:0]  r_count_word, s_count_word;

	logic        start;

	logic        set_counter;

	logic        r_ch0_valid, s_ch0_valid;
	logic        r_ch1_valid, s_ch1_valid;

	enum {IDLE,OFFSET,RUN} state, next_state;


	assign fifo_data_o = r_ch0_valid ? r_shiftreg_ch0_shadow : (r_ch1_valid ? r_shiftreg_ch1_shadow : 'h0);

	assign fifo_data_valid_o = (next_state==IDLE | fifo_data_ready_i==1'b0 | (cfg_rx_continuous_i==1'b0 & r_count_word==(cfg_num_word_i+2))) ?  'h0: r_ch0_valid | r_ch1_valid;

	//assign fifo_err_o = (r_ch0_valid | r_ch1_valid) & ~fifo_data_ready_i & s_word_done;


	always_comb
		begin
			s_shiftreg_ch0  =  r_shiftreg_ch0;
			s_shiftreg_ch1  =  r_shiftreg_ch1;

			if (next_state== IDLE) begin
				s_shiftreg_ch0  =  'h0;
				s_shiftreg_ch1  =  'h0;
			end

			if (next_state== RUN) begin
				if (start == 1'b1 | set_counter==1'b1 ) begin

					if (cfg_lsb_first_i==1'b0) begin
						if (cfg_2ch_i==1'b1)
							s_shiftreg_ch1 [31:0] = {31'b0,i2s_ch1_i};

						s_shiftreg_ch0 [31:0] = {31'b0,i2s_ch0_i};

					end else begin

						if (cfg_2ch_i==1'b1)
							s_shiftreg_ch1 [31:0] = {i2s_ch1_i,31'b0};

						s_shiftreg_ch0 [31:0] = {i2s_ch0_i,31'b0};

					end
				end else begin
					if (cfg_lsb_first_i==1'b0) begin

						//Here i'm reading the middle MSB bit
						if (cfg_2ch_i==1'b1)
							s_shiftreg_ch1 [31:0] = {r_shiftreg_ch1[30:0],i2s_ch1_i};

						s_shiftreg_ch0 [31:0] = {r_shiftreg_ch0[30:0],i2s_ch0_i};

					end else begin

						//Here i'm reading the middle LSB bit
						if (cfg_2ch_i==1'b1)
							s_shiftreg_ch1 [31:0] = {i2s_ch1_i,r_shiftreg_ch1[31:1]};

						s_shiftreg_ch0 [31:0] = {i2s_ch0_i,r_shiftreg_ch0[31:1]};
					end

				end
			end
		end


	always_ff  @(posedge sck_i, negedge rstn_i)
		begin
			if (rstn_i == 1'b0 ) begin

				r_shiftreg_ch0 <=  'h0;
				r_shiftreg_ch1 <=  'h0;

			end else begin
				r_shiftreg_ch0 <=  s_shiftreg_ch0;
				r_shiftreg_ch1 <=  s_shiftreg_ch1;

			end
		end

	always_comb
		begin
			s_shiftreg_ch0_shadow = r_shiftreg_ch0_shadow;
			s_shiftreg_ch1_shadow = r_shiftreg_ch1_shadow;

			s_ch0_valid = r_ch0_valid;
			s_ch1_valid = r_ch1_valid;

			if (next_state== IDLE) begin
				s_shiftreg_ch0_shadow = 'h0;
				s_shiftreg_ch1_shadow = 'h0;
				s_ch0_valid = 1'b0;
				s_ch1_valid =1'b0;
			end

			if (next_state== RUN) begin
				if (r_count_bit+1 == cfg_num_bits_i) begin
					if (cfg_lsb_first_i==1'b0) begin
						s_shiftreg_ch0_shadow [31:0] = {r_shiftreg_ch0[30:0],i2s_ch0_i};
						s_ch0_valid = 1'b1;

						if (cfg_2ch_i==1'b1) begin
							s_shiftreg_ch1_shadow [31:0] = {r_shiftreg_ch1[30:0],i2s_ch1_i};
							s_ch1_valid =1'b1;
						end
					end else begin

						case (cfg_num_bits_i)

							5'd7:
								begin
									s_shiftreg_ch0_shadow [31:0] = {24'b0,i2s_ch0_i,r_shiftreg_ch0[31:25]};
									s_ch0_valid =1'b1;

									if (cfg_2ch_i==1'b1) begin
										s_shiftreg_ch1_shadow [31:0] = {24'b0,i2s_ch1_i,r_shiftreg_ch1[31:25]};
										s_ch1_valid = 1'b1;
									end
								end

							5'd15:
								begin
									s_shiftreg_ch0_shadow [31:0] = {16'b0,i2s_ch0_i,r_shiftreg_ch0[31:17]};
									s_ch0_valid = 1'b1;

									if (cfg_2ch_i==1'b1) begin
										s_shiftreg_ch1_shadow [31:0] = {16'b0,i2s_ch1_i,r_shiftreg_ch1[31:17]};
										s_ch1_valid =1'b1;
									end
								end

							5'd23:
								begin
									s_shiftreg_ch0_shadow [31:0] = {8'b0,i2s_ch0_i,r_shiftreg_ch0[31:9]};
									s_ch0_valid =1'b1;

									if (cfg_2ch_i==1'b1) begin
										s_shiftreg_ch1_shadow [31:0] = {8'b0,i2s_ch1_i,r_shiftreg_ch1[31:9]};
										s_ch1_valid = 1'b1;
									end
								end

							5'd31:
								begin
									s_shiftreg_ch0_shadow [31:0] = {i2s_ch0_i,r_shiftreg_ch0[31:1]};
									s_ch0_valid = 1'b1;

									if (cfg_2ch_i==1'b1) begin
										s_shiftreg_ch1_shadow [31:0] = {i2s_ch1_i,r_shiftreg_ch1[31:1]};
										s_ch1_valid = 1'b1;
									end
								end

							default:
								begin

								end

						endcase

					end
				end
			end
		end

	always_ff  @(posedge sck_i, negedge rstn_i)
		begin
			if (rstn_i == 1'b0 ) begin

				r_shiftreg_ch0_shadow <=  'h0;
				r_shiftreg_ch1_shadow <=  'h0;

				r_ch0_valid <=1'b0;
				r_ch1_valid <=1'b0;

			end else begin
				r_shiftreg_ch0_shadow <=  s_shiftreg_ch0_shadow;
				r_shiftreg_ch1_shadow <=  s_shiftreg_ch1_shadow;

				r_ch0_valid <= s_ch0_valid;
				r_ch1_valid <= s_ch1_valid;

				if( fifo_data_ready_i == 1'b1) begin
					if(r_ch0_valid==1'b1)
						r_ch0_valid <=1'b0;
					else begin
						if(cfg_2ch_i==1'b1 & r_ch1_valid==1'b1)
							r_ch1_valid <=1'b0;
					end
				end
			end
		end


	always_comb
		begin
			s_count_bit = r_count_bit;
			s_count_offset = r_count_offset;
			s_count_word = r_count_word;

			if (next_state== IDLE) begin
				s_count_bit = 'h0;
				s_count_offset ='h0;
				s_count_word = 'h0;
			end

			if (next_state == OFFSET) begin
				//change polarity
				s_count_offset = r_count_offset+1;
			end

			if (next_state== RUN) begin
				if (start == 1'b1 | set_counter==1'b1 )
					s_count_bit ='h0;
				else
					s_count_bit = r_count_bit+1;

				if (cfg_rx_continuous_i==1'b0 & r_count_bit+1 == cfg_num_bits_i & r_count_word<=cfg_num_word_i+1)
					s_count_word = r_count_word+1;
			end
		end

	always_ff  @(posedge sck_i, negedge rstn_i)
		begin
			if (rstn_i == 1'b0 ) begin

				r_count_word <='h0;
				r_count_bit<='h0;
			end else begin

				r_count_word <= s_count_word;
				r_count_bit<= s_count_bit;				
			end
		end

	always_comb
		begin

			start=1'b0;
			set_counter=1'b0;

			case(state)
				IDLE:
					begin
						if(cfg_en_i==1'b0) begin
							next_state= IDLE;
							start=1'b0;
							set_counter=1'b0;
						end
						else begin
							if(i2s_ws_i==1'b1 & cfg_slave_dsp_offset_i==9'd0) begin
								// offset 0
								next_state=RUN;
								start=1'b1;
							end else begin
								if(i2s_ws_i==1'b1 & cfg_slave_dsp_offset_i!=9'd0) begin
									next_state=OFFSET;
									start=1'b0;
								end
							end
						end
					end


				OFFSET:
					begin
						if(cfg_en_i==1'b0) begin
							next_state= IDLE;
							start=1'b0;
							set_counter=1'b0;
						end else begin
							if(r_count_offset==cfg_slave_dsp_offset_i) begin
								next_state=RUN;
								start=1'b1;
							end else begin
								next_state=OFFSET;
								start=1'b0;
							end
						end
					end


				RUN:
					begin

						start=1'b0;

						if(cfg_en_i==1'b0) begin
							next_state= IDLE;
							start=1'b0;
							set_counter=1'b0;
						end else begin
							next_state= RUN;

							if( r_count_bit == cfg_num_bits_i)
								set_counter=1'b1;
							else
								set_counter=1'b0;
						end
					end

				default:
					begin
					end

			endcase
		end

		always_ff  @(posedge sck_i, negedge rstn_i)
		begin
			if (rstn_i == 1'b0 ) begin
				state <=  IDLE;
			end else 			
				if (next_state!=OFFSET)
				state<=next_state;			
		end

		always_ff  @(negedge sck_i, negedge rstn_i)
		begin
			if (rstn_i == 1'b0 ) begin
				r_count_offset<= 'h0;
			end else 			
				if (next_state==OFFSET) begin
					state<=next_state;
					r_count_offset<= s_count_offset;
				end	else
					r_count_offset<= 'h0;	
		end

endmodule

