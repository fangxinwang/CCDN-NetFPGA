///////////////////////////////////////////////////////////////////////////////
// $Id: ip_arp.v 5240 2009-03-14 01:50:42Z grg $
//
// Module: ip_arp.v
// Project: NF2.1
// Description: returns the next hop MAC address
// Modified for CCDN
///////////////////////////////////////////////////////////////////////////////
`include "registers.v"

  module ip_arp
    #(parameter NUM_QUEUES = 8,
      parameter LUT_DEPTH = `ROUTER_OP_LUT_ARP_TABLE_DEPTH,
      parameter LUT_DEPTH_BITS = log2(LUT_DEPTH),
      // --- CCDN
      parameter NAME_LENTH = 32
      )
   (// --- CCDN , Interface to ip_lpm  ,lpm开头的全部指的是查ip表得到的信息
    input      [31:0]                  lpm_next_hop_ip,
    input      [NUM_QUEUES-1:0]        lpm_output_port,		//这也是独热码吧
    input                              lpm_vld,
    input                              lpm_hit,

    // --- CCDN ， Interface to cccp_lut ，cccp开头的全部指的是查ct_FIB表得到的信息
    input      [31:0]                  cccp_next_hop_ip,
    input      [NUM_QUEUES-1:0]        cccp_output_port,
    input                              cccp_vld,
    input                              cccp_hit,
    input                              cccp_vn_match,

    // shared signal
    output                             arp_mac_vld,
    input                              rd_arp_result,
    // --- lpm interface to process block
    output     [47:0]                  lpm_next_hop_mac,
    output     [NUM_QUEUES-1:0]        lpm_op_port,
    output                             lpm_arp_lookup_hit,
    output                             lpm_lookup_hit,
    // --- CCDN Interface to process block
    output     [47:0]                  cccp_next_hop_mac,
    output     [NUM_QUEUES-1:0]        cccp_op_port,
    output                             cccp_arp_lookup_hit,
    output                             cccp_lookup_hit,
    output                             cccp_version_match,

    // --- Interface to registers
    // --- Read port
    input [LUT_DEPTH_BITS-1:0]         arp_rd_addr,          // address in table to read
    input                              arp_rd_req,           // request a read
    output [47:0]                      arp_rd_mac,           // data read from the LUT at rd_addr
    output [31:0]                      arp_rd_ip,            // ip to match in the CAM
    output                             arp_rd_ack,           // pulses high

    // --- Write port
    input [LUT_DEPTH_BITS-1:0]         arp_wr_addr,
    input                              arp_wr_req,
    input [47:0]                       arp_wr_mac,
    input [31:0]                       arp_wr_ip,            // data to match in the CAM
    output                             arp_wr_ack,

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

   //--------------------- Internal Parameter-------------------------
   // --- CCDN
   //---------------------- Wires and regs----------------------------
   wire                                  cam_busy_1, cam_busy_2;
   wire                                  cam_match_1, cam_match_2;
   wire [LUT_DEPTH-1:0]                  cam_match_addr_1, cam_match_addr_2;
   wire [31:0]                           cam_cmp_din_1, cam_cmp_din_2, cam_cmp_data_mask_1, cam_cmp_data_mask_2;
   wire [31:0]                           cam_din_1, cam_din_2, cam_data_mask_1, cam_data_mask_2;
   wire                                  cam_we_1, cam_we_2;
   wire [LUT_DEPTH_BITS-1:0]             cam_wr_addr_1, cam_wr_addr_2;

   wire [47:0]                           lpm_next_hop_mac_result;
   // --- CCDN
   wire [47:0]                           cccp_next_hop_mac_result;

   wire                                  lpm_empty;
   // --- CCDN
   wire                                  cccp_empty;
   reg                                   lpm_hit_latched;
   reg                                   cccp_hit_latched;
   reg                                   cccp_vn_match_latched;

   // --- CCDN
   reg [NUM_QUEUES-1:0]                  lpm_output_port_latched;
   reg [NUM_QUEUES-1:0]                  cccp_output_port_latched;

   // --- CCDN ,lut开头的用来存输入的有效的信号（lpm或者cccp）


   //------------------------- Modules-------------------------------

   // 1 cycle read latency, 2 cycles write latency
   bram_cam_unencoded_32x32 arp_cam_1
     (
      // Outputs
      .busy                             (cam_busy_1),
      .match                            (cam_match_1),
      .match_addr                       (cam_match_addr_1),
      // Inputs
      .clk                              (clk),
      .cmp_din                          (cam_cmp_din_1),
      .din                              (cam_din_1),
      .we                               (cam_we_1),
      .wr_addr                          (cam_wr_addr_1));

   // --- lpm_arp
   unencoded_cam_lut_sm			//前面加个unendoded是什么意思
     #(.CMP_WIDTH(32),                  // IPv4 addr width
       .DATA_WIDTH(48),			// mac addr width
       .LUT_DEPTH(LUT_DEPTH)
       ) lpm_cam_lut_sm
       (// --- Interface for lookups， 果然是根据ip地址，返回mac地址
        .lookup_req         (lpm_vld),
        .lookup_cmp_data    (lpm_next_hop_ip),		//存放需要比对的ip地址
        .lookup_cmp_dmask   (32'h0),
        .lookup_ack         (lpm_lookup_ack),
        .lookup_hit         (lpm_lookup_hit_latched),		//返回是否找到
        .lookup_data        (lpm_next_hop_mac_result),	//返回下一跳的mac地址

        // --- Interface to registers
        // --- Read port
        .rd_addr            (arp_rd_addr),    // address in table to read
        .rd_req             (arp_rd_req),     // request a read
        .rd_data            (arp_rd_mac),     // data found for the entry
        .rd_cmp_data        (arp_rd_ip),      // matching data for the entry
        .rd_cmp_dmask       (),               // don't cares entry
        .rd_ack             (arp_rd_ack),     // pulses high

        // --- Write port
        .wr_addr            (arp_wr_addr),
        .wr_req             (arp_wr_req),
        .wr_data            (arp_wr_mac),    // data found for the entry
        .wr_cmp_data        (arp_wr_ip),     // matching data for the entry
        .wr_cmp_dmask       (32'h0),         // don't cares for the entry
        .wr_ack             (lpm_arp_wr_ack),

        // --- CAM interface
        .cam_busy           (cam_busy_1),
        .cam_match          (cam_match_1),
        .cam_match_addr     (cam_match_addr_1),
        .cam_cmp_din        (cam_cmp_din_1),
        .cam_din            (cam_din_1),
        .cam_we             (cam_we_1),
        .cam_wr_addr        (cam_wr_addr_1),
        .cam_cmp_data_mask  (cam_cmp_data_mask_1),
        .cam_data_mask      (cam_data_mask_1),

        // --- Misc
        .reset (reset),
        .clk   (clk));

   // --- CCDN
   bram_cam_unencoded_32x32 arp_cam_2
     (
      // Outputs
      .busy                             (cam_busy_2),
      .match                            (cam_match_2),
      .match_addr                       (cam_match_addr_2),
      // Inputs
      .clk                              (clk),
      .cmp_din                          (cam_cmp_din_2),
      .din                              (cam_din_2),
      .we                               (cam_we_2),
      .wr_addr                          (cam_wr_addr_2));

   // --- cccp_arp
   unencoded_cam_lut_sm			//前面加个unendoded是什么意思
     #(.CMP_WIDTH(32),                  // IPv4 addr width
       .DATA_WIDTH(48),			// mac addr width
       .LUT_DEPTH(LUT_DEPTH)
       ) cccp_cam_lut_sm
       (// --- Interface for lookups， 果然是根据ip地址，返回mac地址
        .lookup_req         (cccp_vld),
        .lookup_cmp_data    (cccp_next_hop_ip),		//存放需要比对的ip地址
        .lookup_cmp_dmask   (32'h0),
        .lookup_ack         (cccp_lookup_ack),
        .lookup_hit         (cccp_lookup_hit_latched),		//返回是否找到
        .lookup_data        (cccp_next_hop_mac_result),	//返回下一跳的mac地址

        // --- Interface to registers
        // --- Read port 什么都不接
        .rd_addr            (),    // address in table to read
        .rd_req             (),     // request a read
        .rd_data            (),     // data found for the entry
        .rd_cmp_data        (),      // matching data for the entry
        .rd_cmp_dmask       (),               // don't cares entry
        .rd_ack             (),     // pulses high

        // --- Write port
        .wr_addr            (arp_wr_addr),
        .wr_req             (arp_wr_req),
        .wr_data            (arp_wr_mac),    // data found for the entry
        .wr_cmp_data        (arp_wr_ip),     // matching data for the entry
        .wr_cmp_dmask       (32'h0),         // don't cares for the entry
        .wr_ack             (cccp_arp_wr_ack),

        // --- CAM interface
        .cam_busy           (cam_busy_2),
        .cam_match          (cam_match_2),
        .cam_match_addr     (cam_match_addr_2),
        .cam_cmp_din        (cam_cmp_din_2),
        .cam_din            (cam_din_2),
        .cam_we             (cam_we_2),
        .cam_wr_addr        (cam_wr_addr_2),
        .cam_cmp_data_mask  (cam_cmp_data_mask_2),
        .cam_data_mask      (cam_data_mask_2),

        // --- Misc
        .reset (reset),
        .clk   (clk));

   assign arp_wr_ack = lpm_arp_wr_ack & cccp_arp_wr_ack;

   fallthrough_small_fifo #(.WIDTH(50+NUM_QUEUES), .MAX_DEPTH_BITS  (2))
      lpm_arp_fifo
        (.din           ({lpm_next_hop_mac_result, lpm_output_port_latched, lpm_lookup_hit_latched, lpm_hit_latched}), // Data in
         .wr_en         (lpm_lookup_ack),             // Write enable
         .rd_en         (rd_arp_result),       // Read the next word
         .dout          ({lpm_next_hop_mac, lpm_op_port, lpm_arp_lookup_hit, lpm_lookup_hit}),//fallthrough_fifo的输出有72bit，如果我一个模块实例化了这样一个fifo作为输出，但是dout不到72bit，那么这些输出是从高位排列还是从低位排列
         .full          (),
         .nearly_full   (),
         .prog_full     (),
         .empty         (lpm_empty),
         .reset         (reset),
         .clk           (clk)
         );

   // --- CCDN cccp_arp_fifo
   fallthrough_small_fifo #(.WIDTH(51+NUM_QUEUES), .MAX_DEPTH_BITS  (2))
      cccp_arp_fifo
        (.din           ({cccp_next_hop_mac_result, cccp_output_port_latched, cccp_lookup_hit_latched, cccp_hit_latched, cccp_vn_match_latched}), // Data in
         .wr_en         (cccp_lookup_ack),             // Write enable
         .rd_en         (rd_arp_result),       // Read the next word
         .dout          ({cccp_next_hop_mac, cccp_op_port, cccp_arp_lookup_hit, cccp_lookup_hit, cccp_version_match}),//fallthrough_fifo的输出有72bit，如果我一个模块实例化了这样一个fifo作为输出，但是dout不到72bit，那么这些输出是从高位排列还是从低位排列
         .full          (),
         .nearly_full   (),
         .prog_full     (),
         .empty         (cccp_empty),
         .reset         (reset),
         .clk           (clk)
         );

   // --- CCDN
   //------------------------- Logic --------------------------------
   assign arp_mac_vld = !(lpm_empty | cccp_empty);		//empty表示队列空了，也就是没找到，所以mac_vld置empty的反位

   always @(posedge clk) begin
      if(reset) begin
         lpm_output_port_latched <= 0;
         lpm_hit_latched <= 0;
	 cccp_output_port_latched <= 0;
	 cccp_vn_match_latched <= 0;
	 cccp_hit_latched <= 0;
      end
      else begin
         if(cccp_vld) begin
	 cccp_output_port_latched <= cccp_output_port;
	 cccp_vn_match_latched <= cccp_vn_match;
	 cccp_hit_latched <= cccp_hit;
         end
	 if(lpm_vld) begin
	 lpm_output_port_latched <= lpm_output_port;
         lpm_hit_latched  <= lpm_hit;
	 end
      end
   end

endmodule // ip_arp