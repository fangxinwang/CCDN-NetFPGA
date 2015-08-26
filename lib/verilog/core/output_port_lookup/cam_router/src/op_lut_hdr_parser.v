///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// $Id: op_lut_hdr_parser.v 5240 2009-03-14 01:50:42Z grg $
//
// Module: op_lut_hdr_parser.v
// Project: NF2.1
// Description: Checks if the packet is arriving from the CPU or not
//这个模块的功能是查看module header的src port字段，查看这个包是否来自cpu。然后如果这个包要发向cpu，发到哪个口，
//如果这个包从cpu来的，那么发到哪个mac口
///////////////////////////////////////////////////////////////////////////////

  module op_lut_hdr_parser
    #(parameter DATA_WIDTH = 64,
      parameter CTRL_WIDTH = DATA_WIDTH/8,
      parameter NUM_QUEUES = 8,
      parameter NUM_QUEUES_WIDTH = log2(NUM_QUEUES),
      parameter INPUT_ARBITER_STAGE_NUM = 2,
      parameter IO_QUEUE_STAGE_NUM = `IO_QUEUE_STAGE_NUM
      )
   (// --- Interface to the previous stage
    input  [DATA_WIDTH-1:0]            in_data,
    input  [CTRL_WIDTH-1:0]            in_ctrl,
    input                              in_wr,

    // --- Interface to process block
    output                             is_from_cpu,
    output     [NUM_QUEUES-1:0]        to_cpu_output_port,   // where to send this pkt if it has to go to the CPU
    output     [NUM_QUEUES-1:0]        from_cpu_output_port, // where to send this pkt if it is coming from the CPU
    output     [NUM_QUEUES_WIDTH-1:0]  input_port_num,
    input                              rd_hdr_parser,
    output                             is_from_cpu_vld,

    // --- Misc

    input                              reset,
    input                              clk
   );

   function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
   endfunction // log2

   //------------------ Internal Parameter ---------------------------

   parameter PARSE_HDRS = 0;
   parameter WAIT_EOP   = 1;

   //---------------------- Wires/Regs -------------------------------
   reg                                 state, state_next;
   reg                                 wr_en;
   wire                                empty;

   wire                                is_from_cpu_found;	//就表示从module header里面的src port来看，这个包是否来自CPU
   wire [NUM_QUEUES-1:0]               to_cpu_output_port_result;// where to send this pkt if it has to go to the CPU
   wire [NUM_QUEUES-1:0]               from_cpu_output_port_result;// where to send this pkt if it is coming from the CPU
   wire [NUM_QUEUES-1:0]               in_port_decoded;

   wire [NUM_QUEUES-1:0]               decoded_value[NUM_QUEUES-1:0];

   wire [NUM_QUEUES_WIDTH-1:0]         input_port_num_result;

   //----------------------- Modules ---------------------------------
   fallthrough_small_fifo #(.WIDTH(1 + 2*NUM_QUEUES + NUM_QUEUES_WIDTH), .MAX_DEPTH_BITS(2))
      is_from_cpu_fifo
        (.din ({is_from_cpu_found, to_cpu_output_port_result, from_cpu_output_port_result, input_port_num_result}),     // Data in
         .wr_en (wr_en),             // Write enable
         .rd_en (rd_hdr_parser),       // Read the next word
         .dout ({is_from_cpu, to_cpu_output_port, from_cpu_output_port, input_port_num}),
         .full (),
         .nearly_full (),
         .prog_full (),
         .empty (empty),
         .reset (reset),
         .clk (clk)
         );

   //------------------------ Logic ----------------------------------
   assign is_from_cpu_vld = !empty;		//这句话很常用

   /* decode the source port number */
   generate
      genvar i;
      for(i=0; i<NUM_QUEUES; i=i+1) begin: decoder
         assign decoded_value[i] = 2**i;		//值分别是0、1、2、4、8、16、32、64
      end
   endgenerate
   assign in_port_decoded = decoded_value[input_port_num_result];//转换成独热码

   // Note: you cannot do [`IOQ_SRC_PORT_POS +: NUM_QUEUES_WIDTH] in the
   // statement below as it does not work with ModelSim SE 6.2F
   assign input_port_num_result = in_data[`IOQ_SRC_PORT_POS +: 16]; //表示以`IOQ_SRC_PORT_POS，往上（大的方向）加16位，如果这里宏为16，那么就等价于[31:16]，这个时候数据总线上传的是module header
   assign is_from_cpu_found = |(in_port_decoded & {(NUM_QUEUES/2){2'b10}}) ;//{(NUM_QUEUES/2){2'b10}这个表示10101010，即4个10重复，然后在按位或
   assign to_cpu_output_port_result = {in_port_decoded[NUM_QUEUES-2:0], 1'b0}; // odd numbers are CPU ports， 相当于左移一位，比如说mac口是i，那个就发到响应的i+1的cpu口
   assign from_cpu_output_port_result = {1'b0, in_port_decoded[NUM_QUEUES-1:1]};// even numbers are MAC ports， 相当于右移以为，比如说从cpu i口收到的包，那么发到响应的i-1mac口。

   always@(*) begin
      state_next = state;
      wr_en = 0;
      case(state)
        PARSE_HDRS: begin
           if( in_ctrl==0 && in_wr) begin
              state_next = WAIT_EOP;
           end
           if( in_ctrl==IO_QUEUE_STAGE_NUM && in_wr) begin
              wr_en = 1;
           end
        end

        WAIT_EOP: begin
           if(in_wr && in_ctrl != 0) begin
              state_next = PARSE_HDRS;
           end
        end
      endcase // case(state)
   end // always@ (*)

   always @(posedge clk) begin
      if(reset) begin
         state <= PARSE_HDRS;
      end
      else begin
         state <= state_next;
      end
   end

endmodule // eth_parser


