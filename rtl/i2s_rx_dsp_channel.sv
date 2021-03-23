

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
    input  logic              [2:0] cfg_num_word_i, 
    input  logic                    cfg_lsb_first_i,
    input  logic                    cfg_rx_continuous_i,
    
    input  logic              [1:0] cfg_dsp_mode_i
 );

    logic [31:0] r_shiftreg_ch0;
    logic [31:0] r_shiftreg_ch1;    
    
    logic [7:0][31:0] r_fifo_out;
    
    logic [31:0] r_shiftreg_ch0_shadow;
    logic [31:0] r_shiftreg_ch1_shadow;
    
    
    logic [4:0]  r_count_word;

    logic [4:0]  r_count_bit;
    
    logic        start;
    
    logic        set_counter;
    
    logic        r_ch0_valid;
    logic        r_ch1_valid;
    
    enum {IDLE,RUN} state, next_state; 

    

    assign fifo_data_o = r_ch0_valid ? r_shiftreg_ch0_shadow : (r_ch1_valid ? r_shiftreg_ch1_shadow : 'h0);
    
    assign fifo_data_valid_o = r_ch0_valid | r_ch1_valid;
    
    //assign fifo_err_o = (r_ch0_valid | r_ch1_valid) & ~fifo_data_ready_i & s_word_done;

    //it implements the rx udma protocol
    always_ff  @(posedge sck_i, negedge rstn_i)
    begin
       if(rstn_i != 1'b0) begin
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

    // it is used to sample data from sd lines only on posedge
    always_ff  @(posedge sck_i, negedge rstn_i)
    begin
       if (rstn_i == 1'b0 | next_state==IDLE)
        begin
            r_shiftreg_ch0  <=  'h0;
            r_shiftreg_ch1  <=  'h0;
            
            r_shiftreg_ch0_shadow <=  'h0;
            r_shiftreg_ch1_shadow <=  'h0;
            
            state <= IDLE;
            r_count_bit<='h0;

            r_ch0_valid <=1'b0;
	        r_ch1_valid <=1'b0;
                    
        end
        else
        begin

           if(cfg_dsp_mode_i[0]==1'b0) begin
	       case(cfg_dsp_mode_i[1])
	         
	         1'b0:
	         begin
	            /*  DSP FOR ICS-52000 MICROPHONES  DSP_MODE : 00
	
	                This microphones drives the DOUT lines on the first clock change after the WS signal.
	                They receives the WS on falling sck and puts the first data out on next rising edge sck.
	                The master must samples data 1 sck after the microphone.
	                They send 24 bits in 32 bits slots MSB first 2 complement
	            */
	 
	            if (start == 1'b1) begin
	               r_count_bit<='d31;
	                
	               r_shiftreg_ch0_shadow <= r_shiftreg_ch0_shadow;
	               r_shiftreg_ch1_shadow <= r_shiftreg_ch1_shadow;
	                       
	               //reset the shift register before next word read
	               r_shiftreg_ch0  <=  'h0;
	               r_shiftreg_ch1  <=  'h0;
	                    
	            end else begin
	               if (set_counter==1'b1) begin
	                  
			          /* Read the first bit from microphones */ 
			          r_count_bit<='h0;
	                    
	                  r_shiftreg_ch0_shadow <= r_shiftreg_ch0_shadow;
	                  r_shiftreg_ch1_shadow <= r_shiftreg_ch1_shadow;
	                       
	                  if (cfg_lsb_first_i==1'b0) begin
	                          
	                     //Here i'm reading the first bit of MSB	                          
	                     if (cfg_2ch_i==1'b1) 
	                        r_shiftreg_ch1 [31:0] <= {31'b0,i2s_ch1_i};
	                                 
	                     r_shiftreg_ch0 [31:0] <= {31'b0,i2s_ch0_i}; 
	                          
	                 
	                  end else begin
	                    
	                     //Here i'm reading the first bit of LSB	                                                 
	                     if (cfg_2ch_i==1'b1) 
	                        r_shiftreg_ch1 [31:0] <= {i2s_ch1_i,31'b0};
	                                 
	                     r_shiftreg_ch0 [31:0] <= {i2s_ch0_i,31'b0};	                          	                           
	                     
	                  end
	                    
	               end else begin	               
	                    
	                  if (r_count_bit+1 == cfg_num_bits_i) begin
			    
			             //Here i'm reading the last bit from microphones
	                          
	                     if (cfg_lsb_first_i==1'b0) begin
	                             
	                        //Here i'm reading the last MSB bit 
	                             
	                        r_shiftreg_ch0_shadow [31:0] <= {r_shiftreg_ch0[30:0],i2s_ch0_i};
	                        r_ch0_valid <=1'b1;
	                          
	                        if (cfg_2ch_i==1'b1) begin
	                           r_shiftreg_ch1_shadow [31:0] <= {r_shiftreg_ch1[30:0],i2s_ch1_i};
	                           r_ch1_valid <=1'b1;
	                        end	                             	                         	
	                     end else begin
	                       
	                        r_shiftreg_ch0_shadow [31:0] <= {i2s_ch0_i,r_shiftreg_ch0[31:1]};
	                        r_ch0_valid <=1'b1;
	                          
	                        if (cfg_2ch_i==1'b1) begin
	                           r_shiftreg_ch1_shadow [31:0] <= {i2s_ch1_i,r_shiftreg_ch1[31:1]};	                                
	                           r_ch1_valid <=1'b1;
	                        end
	                             
	                     end   
	                  end else begin
	                     r_shiftreg_ch0_shadow <= r_shiftreg_ch0_shadow;
	                     r_shiftreg_ch1_shadow <= r_shiftreg_ch1_shadow;
	                  end
	                  
	                  //Here i'm reading the middle bit from microphones
	                  r_count_bit<=r_count_bit+1; 
	                    
	                  if (cfg_lsb_first_i==1'b0) begin
	                          
	                     //Here i'm reading the middle MSB bit
	                          	                         
	                     if (cfg_2ch_i==1'b1) 
	                        r_shiftreg_ch1 [31:0] <= {r_shiftreg_ch1[30:0],i2s_ch1_i};
	                                 
	                     r_shiftreg_ch0 [31:0] <= {r_shiftreg_ch0[30:0],i2s_ch0_i};   
	                          	                          
	                  end else begin
	                     //Here i'm reading the middle LSB bit	                       	                           
	                     if (cfg_2ch_i==1'b1) 
	                        r_shiftreg_ch1 [31:0] <= {i2s_ch1_i,r_shiftreg_ch1[31:1]};                            
	                                 
	                     r_shiftreg_ch0 [31:0] <= {i2s_ch0_i,r_shiftreg_ch0[31:1]};                       	                       
	                         
	                  end
	  
	               end //close else on set_counter
	                                                           
	            end // close else on start bit
	                             
	         end
	
	         1'b1:
	         begin
	            /*  STANDARD DSP MODE FOR CODEC DSP_MODE : 10 
	
	                The standard DSP communication provide that the external source start to trasmit the data immediately when it receives the WS signal
	                The master samples it on the first sck change.
	                In this mode the WS signal goes to 1 on negedge and we must samples data immediately halF clk late
	            */
	               
	            if (start == 1'b1 | set_counter==1'b1 ) begin
	               
		           // Here i'm reading the first bit from generic dsp peripheral
		           r_count_bit<='h0;
	                    
	               r_shiftreg_ch0_shadow <= r_shiftreg_ch0_shadow;
	               r_shiftreg_ch1_shadow <= r_shiftreg_ch1_shadow;
	                       
	               if (cfg_lsb_first_i==1'b0) begin	                          	                          
	                          
	                  if (cfg_2ch_i==1'b1) 
	                     r_shiftreg_ch1 [31:0] <= {31'b0,i2s_ch1_i};
	                                 
	                     r_shiftreg_ch0 [31:0] <= {31'b0,i2s_ch0_i}; 	                          
	                          
	               end else begin	                     
	                                                 
	                     if (cfg_2ch_i==1'b1) 
	                        r_shiftreg_ch1 [31:0] <= {i2s_ch1_i,31'b0};
	                                 
	                     r_shiftreg_ch0 [31:0] <= {i2s_ch0_i,31'b0};	                          
	                     
	               end	                    
	            end else begin
	                    
	               if (r_count_bit+1 == cfg_num_bits_i) begin
	                  
			          //Here i'm reading the last bit from generic dsp peripheral  
			 
	                  if (cfg_lsb_first_i==1'b0) begin
                             r_shiftreg_ch0_shadow [31:0] <= {r_shiftreg_ch0[30:0],i2s_ch0_i};
	                     r_ch0_valid <=1'b1;
	                          
	                     if (cfg_2ch_i==1'b1) begin
	                        r_shiftreg_ch1_shadow [31:0] <= {r_shiftreg_ch1[30:0],i2s_ch1_i};
	                        r_ch1_valid <=1'b1;
	                     end	                      
	                  end else begin
	                             
	                    case (cfg_num_bits_i)

	                    	5'd7:
	                    	   begin
	                    	      r_shiftreg_ch0_shadow [31:0] <= {24'b0,i2s_ch0_i,r_shiftreg_ch0[31:25]};	                             
	                              r_ch0_valid <=1'b1;
	                          
	                              if (cfg_2ch_i==1'b1) begin
	                                 r_shiftreg_ch1_shadow [31:0] <= {24'b0,i2s_ch1_i,r_shiftreg_ch1[31:25]};	                                
	                                 r_ch1_valid <=1'b1;
	                              end
	                    	   end
                            
                            5'd15:
	                    	   begin
	                    	      r_shiftreg_ch0_shadow [31:0] <= {16'b0,i2s_ch0_i,r_shiftreg_ch0[31:17]};	                             
	                              r_ch0_valid <=1'b1;
	                          
	                              if (cfg_2ch_i==1'b1) begin
	                                 r_shiftreg_ch1_shadow [31:0] <= {16'b0,i2s_ch1_i,r_shiftreg_ch1[31:17]};	                                
	                                 r_ch1_valid <=1'b1;
	                              end
	                    	   end

	                    	5'd23:
	                    	   begin
	                    	      r_shiftreg_ch0_shadow [31:0] <= {8'b0,i2s_ch0_i,r_shiftreg_ch0[31:9]};	                             
	                              r_ch0_valid <=1'b1;
	                          
	                              if (cfg_2ch_i==1'b1) begin
	                                 r_shiftreg_ch1_shadow [31:0] <= {8'b0,i2s_ch1_i,r_shiftreg_ch1[31:9]};	                                
	                                 r_ch1_valid <=1'b1;
	                              end
	                    	   end

	                    	5'd31:
	                    	   begin
	                    	      r_shiftreg_ch0_shadow [31:0] <= {i2s_ch0_i,r_shiftreg_ch0[31:1]};	                             
	                              r_ch0_valid <=1'b1;
	                          
	                              if (cfg_2ch_i==1'b1) begin
	                                 r_shiftreg_ch1_shadow [31:0] <= {i2s_ch1_i,r_shiftreg_ch1[31:1]};	                                
	                                 r_ch1_valid <=1'b1;
	                              end
	                    	   end

	                    	default:
	                    	   begin

	                    	   end

	                    endcase	 

	                  end   
	               end else begin
	                  r_shiftreg_ch0_shadow <= r_shiftreg_ch0_shadow;
	                  r_shiftreg_ch1_shadow <= r_shiftreg_ch1_shadow;
	               end
	               
	               //Here i'm reading the middle bit from generic dsp peripheral
	               r_count_bit<=r_count_bit+1; 
	                    
	               if (cfg_lsb_first_i==1'b0) begin         
	                  
			          //Here i'm reading the middle MSB bit	                          	                          
	                  if (cfg_2ch_i==1'b1) 
	                     r_shiftreg_ch1 [31:0] <= {r_shiftreg_ch1[30:0],i2s_ch1_i};
	                                 
	                  r_shiftreg_ch0 [31:0] <= {r_shiftreg_ch0[30:0],i2s_ch0_i};   
	                          	                          
	               end else begin
	                         
	                  //Here i'm reading the middle LSB bit	
	                  if (cfg_2ch_i==1'b1) 
	                     r_shiftreg_ch1 [31:0] <= {i2s_ch1_i,r_shiftreg_ch1[31:1]};
	                                                             
	                  r_shiftreg_ch0 [31:0] <= {i2s_ch0_i,r_shiftreg_ch0[31:1]};
	               end
	  
	            end  //close start bit else	               
	         end
	
	        endcase
              
                 state <= next_state;
           
           end //close if on cfg_dsp_mode_i[1]==0
                                   	   
        end // close else reset_n
    end


 // it is used to sample data from sd lines only on negedge
    always_ff  @(negedge sck_i)
    begin
      if(cfg_dsp_mode_i[0]==1'b1) begin
	  case(cfg_dsp_mode_i[1])
	   1'b0:
	       begin
	          /*  DSP FOR STANDARD CODEC DSP   
	
	              The standard DSP communication provide that the external source start to trasmit the data immediately when it receives the WS signal
	              The master samples it on the first sck change.
	              In this mode the WS signal goes to 1 on posedge and we must samples data immediately half clk later on negedge
	
	          */
	               
	          if (start == 1'b1 | set_counter==1'b1 ) begin
	             r_count_bit<='h0;
	                    
	             r_shiftreg_ch0_shadow <= r_shiftreg_ch0_shadow;
	             r_shiftreg_ch1_shadow <= r_shiftreg_ch1_shadow;
	                       
	             if (cfg_lsb_first_i==1'b0) begin
	                          
	                //MSB FIRST 
	                          
	                if (cfg_2ch_i==1'b1) 
	                   r_shiftreg_ch1 [31:0] <= {31'b0,i2s_ch1_i};
	                                 
	                r_shiftreg_ch0 [31:0] <= {31'b0,i2s_ch0_i}; 
	                          
	                // MSB FIRST
	             end else begin
	                //LSB FIRST - FIRST BIT
	                                                 
	                if (cfg_2ch_i==1'b1) 
	                   r_shiftreg_ch1 [31:0] <= {i2s_ch1_i,31'b0};
	                                 
	                r_shiftreg_ch0 [31:0] <= {i2s_ch0_i,31'b0};	                          	                           
	                //LSB FIRST 
	             end
	          end else begin
	                    
	             if (r_count_bit+1 == cfg_num_bits_i) begin
	                          
	                if (cfg_lsb_first_i==1'b0) begin
	                             
	                   //MSB FIRST - LAST BIT
	                             
	                   r_shiftreg_ch0_shadow [31:0] <= {r_shiftreg_ch0[30:0],i2s_ch0_i};
	                   r_ch0_valid <=1'b1;
	                          
	                   if (cfg_2ch_i==1'b1) begin
	                      r_shiftreg_ch1_shadow [31:0] <= {r_shiftreg_ch1[30:0],i2s_ch1_i};
	                      r_ch1_valid <=1'b1;
	                   end   
	                   //MSB FIRST
	                end else begin
	                   //LSB FIRST - LAST BIT
	                   
	                   case (cfg_num_bits_i)

	                    	5'd7:
	                    	   begin
	                    	      r_shiftreg_ch0_shadow [31:0] <= {24'b0,i2s_ch0_i,r_shiftreg_ch0[31:25]};	                             
	                              r_ch0_valid <=1'b1;
	                          
	                              if (cfg_2ch_i==1'b1) begin
	                                 r_shiftreg_ch1_shadow [31:0] <= {24'b0,i2s_ch1_i,r_shiftreg_ch1[31:25]};	                                
	                                 r_ch1_valid <=1'b1;
	                              end
	                    	   end
                            
                            5'd15:
	                    	   begin
	                    	      r_shiftreg_ch0_shadow [31:0] <= {16'b0,i2s_ch0_i,r_shiftreg_ch0[31:17]};	                             
	                              r_ch0_valid <=1'b1;
	                          
	                              if (cfg_2ch_i==1'b1) begin
	                                 r_shiftreg_ch1_shadow [31:0] <= {16'b0,i2s_ch1_i,r_shiftreg_ch1[31:17]};	                                
	                                 r_ch1_valid <=1'b1;
	                              end
	                    	   end

	                    	5'd23:
	                    	   begin
	                    	      r_shiftreg_ch0_shadow [31:0] <= {8'b0,i2s_ch0_i,r_shiftreg_ch0[31:9]};	                             
	                              r_ch0_valid <=1'b1;
	                          
	                              if (cfg_2ch_i==1'b1) begin
	                                 r_shiftreg_ch1_shadow [31:0] <= {8'b0,i2s_ch1_i,r_shiftreg_ch1[31:9]};	                                
	                                 r_ch1_valid <=1'b1;
	                              end
	                    	   end

	                    	5'd31:
	                    	   begin
	                    	      r_shiftreg_ch0_shadow [31:0] <= {i2s_ch0_i,r_shiftreg_ch0[31:1]};	                             
	                              r_ch0_valid <=1'b1;
	                          
	                              if (cfg_2ch_i==1'b1) begin
	                                 r_shiftreg_ch1_shadow [31:0] <= {i2s_ch1_i,r_shiftreg_ch1[31:1]};	                                
	                                 r_ch1_valid <=1'b1;
	                              end
	                    	   end

	                    	default:
	                    	   begin
	                    	   
	                    	   end

	                    endcase	    
	                   
	                end   
	             end else begin
	                r_shiftreg_ch0_shadow <= r_shiftreg_ch0_shadow;
	                r_shiftreg_ch1_shadow <= r_shiftreg_ch1_shadow;
	             end
	                    
	             r_count_bit<=r_count_bit+1; 
	                    
	             if (cfg_lsb_first_i==1'b0) begin
	                          
	                //MSB FIRST MIDDLE BITS
	                          	               
	                if (cfg_2ch_i==1'b1) 
	                   r_shiftreg_ch1 [31:0] <= {r_shiftreg_ch1[30:0],i2s_ch1_i};
	                                 
	                r_shiftreg_ch0 [31:0] <= {r_shiftreg_ch0[30:0],i2s_ch0_i};   	                          
	                //MSB FIRST
	             end else begin
	                //LSB FIRST - MIDDLE BITS
	                       
	                           
	                if (cfg_2ch_i==1'b1) 
	                   r_shiftreg_ch1 [31:0] <= {i2s_ch1_i,r_shiftreg_ch1[31:1]};
	                            
	                r_shiftreg_ch0 [31:0] <= {i2s_ch0_i,r_shiftreg_ch0[31:1]};
	                                                
	                //LSB FIRST
	             end	  
	          end 
	          // END DSP FOR STANDARD CODEC WS falling sample pos
	       end

           1'b1:
	          begin
                 //not used
              end
           endcase
              
              state <= next_state;
         end //close if on cfg_dsp_mode_i[1]==0
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
                  //wait WS
                  start=1'b0;
                  if(i2s_ws_i==1'b1) begin
                     next_state=RUN;
                     start=1'b1;
                  end else
                     next_state=IDLE;
               end
             end

         RUN:
             begin
               
               start=1'b0;
               
               if(cfg_en_i==1'b0) 
                  next_state= IDLE;              
               else begin
                  
                  //SAMPLE NUM_BITS
                  
                  next_state= RUN;
                  
                  if( r_count_bit == cfg_num_bits_i)                         
                     set_counter=1'b1;                                     
                  else 
                     set_counter=1'b0;                 
               end
             end

      endcase
    end
    
endmodule

