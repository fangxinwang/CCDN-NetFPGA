///////////////////////////////////////////////////////////////////////////////
// $Id: cccp_lut.v 5089 2009-02-23 02:14:38Z grg $
//
// Module: cccp_lut.v
// Project: NF2.1
// Description: Finds the longest prefix match of the incoming content name
//              gives the ip of the next hop and the output port
// Designed for CCDN
///////////////////////////////////////////////////////////////////////////////

  module cccp_lut
    #(parameter DATA_WIDTH = 64,
      parameter NUM_QUEUES = 8,		//独热码,每一位代表一个转发口,不用管这个5，上层初始化的时候它是8
      parameter LUT_DEPTH = `ROUTER_OP_LUT_CCCP_TABLE_DEPTH,
      parameter LUT_DEPTH_BITS = log2(LUT_DEPTH),
      // --- CCDN
      parameter NAME_LENTH = 32,
      parameter VN_LENTH = 16
      )
   (// --- Interface to the previous stage
    input  [DATA_WIDTH-1:0]            in_data,

    // --- Interface to arp_lut  （即ip_arp.v）
    output reg [31:0]                  cccp_next_hop_ip,
    output reg [NUM_QUEUES-1:0]        cccp_output_port,
    output reg                         cccp_vld,
    output reg                         cccp_hit,
    output reg                         cccp_vn_match,

    // --- Interface to preprocess block
    input                              word_CCCP_NAME_HI,
    input                              word_CCCP_NAME_LO,
    input                              word_CCCP_NAME_VN,

    // --- Interface to registers
    // --- Read port   ，它多是输出信号，它传递信号给cam核说我要读某一个地址，然后路由表返回一系列信息（在本模块里面没有涉及到它主动读）
    // --- CCDN
    input  [LUT_DEPTH_BITS-1:0]        cccp_rd_addr,          // address in table to read
    input                              cccp_rd_req,           // request a read
    output [NAME_LENTH-1:0]            cccp_rd_name,          // name to match in the CAM
    output [VN_LENTH-1:0]              cccp_rd_vn,            // version number to match in lut
    output [NUM_QUEUES-1:0]            cccp_rd_oq,            // output queue
    output [31:0]                      cccp_rd_next_hop_ip,   // ip addr of next hop,有用吗？
    output                             cccp_rd_ack,           // pulses high

    // --- Write port   ，它多是输入信号，应该是其他更高级的控制模块给信号，它收到写信号之后可以往cam里面写内??    // --- CCDN
    input [LUT_DEPTH_BITS-1:0]         cccp_wr_addr,
    input                              cccp_wr_req,
    input [NUM_QUEUES-1:0]             cccp_wr_oq,
    input [31:0]                       cccp_wr_next_hop_ip,   // ip addr of next hop
    input [NAME_LENTH-1:0]             cccp_wr_name,          // data to match in the CAM
    input [VN_LENTH-1:0]               cccp_wr_vn,            // version number to match in lut
    output                             cccp_wr_ack,

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

   //---------------------- Wires and regs----------------------------

   wire                                  cam_busy;
   wire                                  cam_match;
   wire [LUT_DEPTH-1:0]                  cam_match_addr;
   wire [NAME_LENTH-1:0]                 cam_cmp_din;
   wire [NAME_LENTH-1:0]                 cam_din;
   wire                                  cam_we;
   wire [LUT_DEPTH_BITS-1:0]             cam_wr_addr;
   // --- CCDN
   wire [NAME_LENTH-1:0]                 cam_cmp_data_mask, cam_data_mask;
   wire [NUM_QUEUES-1:0]                 cccp_lookup_port_result;
   wire [31:0]                           cccp_next_hop_ip_result;
   wire [VN_LENTH-1:0]                   cccp_version_result;

   // --- CCDN
   reg                                   ct_name_vld;
   reg [NAME_LENTH-1:0]                  ct_name;
   reg                                   ct_vn_vld;
   reg [VN_LENTH-1:0]                    ct_vn;

   //------------------------- Modules-------------------------------

   // 1 cycle read latency, 16 cycles write latency
   // priority encoded for the smallest address.	//这个cam的功能就是给一个cmp地址，然后输出这?鰁ntry的address
   bram_cam_unencoded_32x32 cccp_cam
     (
      // Outputs
      .busy                             (cam_busy),
      .match                            (cam_match),
      .match_addr                       (cam_match_addr),
      // Inputs
      .clk                              (clk),
      .cmp_din                          (cam_cmp_din),//cam_cmp_dim和cam_din有什么区别
      .din                              (cam_din),
      .we                               (cam_we),
      .wr_addr                          (cam_wr_addr));

   // --- CCDN
   unencoded_cccp_cam_lut_sm
     #(.CMP_WIDTH          (NAME_LENTH),        // content_name width
       .DATA_WIDTH         (NAME_LENTH+NUM_QUEUES+VN_LENTH),     // next hop ip and output queue
       .LUT_DEPTH          (LUT_DEPTH),
       .DEFAULT_DATA       (1)
      ) cam_lut_sm
       (// --- Interface for lookups
        .lookup_req          (ct_name_vld),
        .lookup_cmp_data     (ct_name),
        .lookup_cmp_dmask    (32'h0),      //这里能不能这样写??
        .lookup_ack          (cccp_vld_result),		//cccp的查找是否有效
        .lookup_hit          (cccp_hit_result),		//cccp是否命中了
        .lookup_data         ({cccp_lookup_port_result, cccp_next_hop_ip_result,cccp_version_result}),//lookup_port_result返回的就是从哪个口转发，next_hot_ip_result指明下一跳的ip地址

        // --- Interface to registers
        // --- Read port
        .rd_addr             (cccp_rd_addr),                        // address in table to read
        .rd_req              (cccp_rd_req),                         // request a read
        .rd_data             ({cccp_rd_oq, cccp_rd_next_hop_ip, cccp_rd_vn}),   // data found for the entry
        .rd_cmp_data         (cccp_rd_name),                        // matching data for the entry
        .rd_cmp_dmask        (),
        .rd_ack              (cccp_rd_ack),                         // pulses high

        // --- Write port
        .wr_addr             (cccp_wr_addr),
        .wr_req              (cccp_wr_req),
        .wr_data             ({cccp_wr_oq, cccp_wr_next_hop_ip, cccp_wr_vn}),    // data found for the entry
        .wr_cmp_data         (cccp_wr_name),                          // matching data for the entry
        .wr_cmp_dmask        (32'h0),
        .wr_ack              (cccp_wr_ack),

        // --- CAM interface
        .cam_busy            (cam_busy),
        .cam_match           (cam_match),
        .cam_match_addr      (cam_match_addr),
        .cam_cmp_din         (cam_cmp_din),
        .cam_din             (cam_din),
        .cam_we              (cam_we),
        .cam_wr_addr         (cam_wr_addr),
        .cam_cmp_data_mask   (cam_cmp_data_mask),
        .cam_data_mask       (cam_data_mask),

        // --- Misc
        .reset               (reset),
        .clk                 (clk));

   //------------------------- Logic --------------------------------

   /*****************************************************************
    * find the dst IP address and do the lookup
    *****************************************************************/
   always @(posedge clk) begin
      if(reset) begin
         ct_name <= 0;
         ct_name_vld <= 0;
      end
      else begin
         if(word_CCCP_NAME_HI) begin		//把content name的高16位存入ct_name寄存器中
            ct_name[NAME_LENTH-1:NAME_LENTH-16] <= in_data[15:0];
         end
         if(word_CCCP_NAME_LO) begin		//把content name的低16位存入ct_name寄存器中
            ct_name[15:0]  <= in_data[DATA_WIDTH-1:DATA_WIDTH-16];
            ct_name_vld <= 1;
         end
         else begin
            ct_name_vld <= 0;
         end
      end // else begin
   end // always @ (posedge clk)

   always @(posedge clk) begin
      if(reset) begin
         ct_vn <= 0;
	 ct_vn_vld <= 0;
      end
      else begin
         if(word_CCCP_NAME_VN) begin
	    ct_vn <= in_data[DATA_WIDTH-17:DATA_WIDTH-32];
	    ct_vn_vld <= 1;
	 end
	 else begin
	    ct_vn_vld <= 0;
	 end
      end // else begin
   end // always @(posedge clk)

   /*****************************************************************
    * latch the outputs
    *****************************************************************/
   always @(posedge clk) begin
      cccp_output_port <= cccp_lookup_port_result;
      cccp_next_hop_ip <= (cccp_next_hop_ip_result == 0) ? ct_name : cccp_next_hop_ip_result; //这点需要改进吗？
      cccp_hit         <= cccp_hit_result;
      cccp_vn_match    <= (cccp_version_result == ct_vn) ? 1'b1 : 1'b0;

      if(reset) begin
         cccp_vld <= 0;
      end
      else begin
         cccp_vld <= cccp_vld_result;
      end // else: !if(reset)
   end // always @ (posedge clk)
endmodule // cccp_lut
