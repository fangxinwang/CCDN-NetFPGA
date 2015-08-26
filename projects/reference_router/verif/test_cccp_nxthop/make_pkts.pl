#!/usr/local/bin/perl -w
# make_pkts.pl
#
#
#

use NF::PacketGen;
use NF::PacketLib;
use SimLib;
use RouterLib;

use reg_defines_reference_router;

$delay = 2000;
$batch = 0;	
nf_set_environment( { PORT_MODE => 'PHYSICAL', MAX_PORTS => 4 } );

# use strict AFTER the $delay, $batch and %reg are declared
use strict;
use vars qw($delay $batch %reg);

my $ROUTER_PORT_1_MAC = '00:00:00:00:09:01';
my $ROUTER_PORT_2_MAC = '00:00:00:00:09:02';
my $ROUTER_PORT_3_MAC = '00:00:00:00:09:03';
my $ROUTER_PORT_4_MAC = '00:00:00:00:09:04';

my $ROUTER_PORT_1_IP = '192.168.26.2';
my $ROUTER_PORT_2_IP = '192.168.25.2';
my $ROUTER_PORT_3_IP = '192.168.27.2';
my $ROUTER_PORT_4_IP = '192.168.24.2';
my $OSPF_IP = '224.0.0.5';

# Prepare the DMA and enable interrupts
prepare_DMA('@3.9us');
enable_interrupts(0);

# Write the ip addresses and mac addresses, routing table, filter, ARP entries
$delay = '@4us';
set_router_MAC(1, $ROUTER_PORT_1_MAC);
$delay = 0;
set_router_MAC(2, $ROUTER_PORT_2_MAC);
set_router_MAC(3, $ROUTER_PORT_3_MAC);
set_router_MAC(4, $ROUTER_PORT_4_MAC);

add_dst_ip_filter_entry(0,$ROUTER_PORT_1_IP);
add_dst_ip_filter_entry(1,$ROUTER_PORT_2_IP);
add_dst_ip_filter_entry(2,$ROUTER_PORT_3_IP);
add_dst_ip_filter_entry(3,$ROUTER_PORT_4_IP);
add_dst_ip_filter_entry(4,$OSPF_IP);

add_LPM_table_entry(0,'192.168.27.0', '255.255.255.0', '192.168.27.1', 0x10); #3
add_LPM_table_entry(1,'192.168.26.0', '255.255.255.0', '192.168.26.1', 0x01); #1
add_LPM_table_entry(2,'192.168.25.0', '255.255.255.0', '192.168.25.1', 0x04); #2
add_LPM_table_entry(3,'192.168.24.0', '255.255.255.0', '192.168.24.1', 0x40); #4

# Add the ARP table entries
add_ARP_table_entry(0, '192.168.25.1', '01:50:17:15:56:1c');
add_ARP_table_entry(1, '192.168.26.1', '01:50:17:20:fd:81');
add_ARP_table_entry(2, '192.168.27.1', '01:50:17:20:fe:11');
add_ARP_table_entry(3, '192.168.24.1', '01:50:17:20:36:12');

# --- CCDN  Add the content table entries
add_CCCP_table_entry(0, '127.1.1.1', 0 , '192.168.24.1', 0x40); # �����4�ſڷ�
add_CCCP_table_entry(1, '128.0.0.0', 1 , '192.168.27.1', 0x10); # �����3�ſڷ�

my $length = 98;
my $TTL = 30;
my $DA = 0;
my $SA = 0;
my $dst_ip = 0;
my $ct_type = 0;
my $src_ip = 0;
my $ct_name = 0;
my $ct_vn = 0;
my $pkt;

#
###############################
#

print "\nconstructing 1st packet....\n";
# ����1mac�ڽ��룬��IP�Ļ���mac2�ڷ�����content�Ļ���mac4�ڷ�
# 1st pkt (no VLAN)
for (my $i=0; $i<100; $i++){
	$delay = '@50us';
	$length = 98; # �����費Ҫ��Ҫ�ģ�length����ô���ģ�������㶨��
	$DA = $ROUTER_PORT_1_MAC;
	$SA = '01:55:55:55:55:55';
	$dst_ip = '192.168.25.1';
	$src_ip = '192.168.26.1';
	$ct_type = 0;
	$ct_name = '127.1.1.1';
	$ct_vn = 0;
#	$pkt = make_IP_pkt($length, $DA, $SA, $TTL, $dst_ip, $src_ip); # ������������ģ�make_CCCP_pkt
# --- CCDN ����ĳ�make_CCCP_pkt
	$pkt = make_CCCP_pkt($length, $DA, $SA, $TTL, $dst_ip, $src_ip, $ct_type, $ct_name, $ct_vn); 

	nf_packet_in(1, $length, $delay, $batch,  $pkt);# ������ĳ���ڽ��յİ�

	$DA = '01:50:17:20:36:12';
	$SA = $ROUTER_PORT_4_MAC;

#	$pkt = make_IP_pkt($length, $DA, $SA, $TTL-1, $dst_ip, $src_ip);# ע������DA��SA�Ѿ�����
# --- CCDN ����ĳ�make_CCCP_pkt
	$pkt = make_CCCP_pkt($length, $DA, $SA, $TTL-1, $dst_ip, $src_ip, $ct_type, $ct_name, $ct_vn); 
	nf_expected_packet(4, $length, $pkt); # ������router�����İ���4��ָport 4����˼
}
# nf_packet_in �� nf_expected_packet�ֱ����������У�Ӧ����һ��ʵ������Ķ��н�nf_packet_out��Ȼ�����һ��nf_compare.pl�ļ�ȥ�Ƚ�expected��out�����Ӧ�İ�һ��һ��

# 1st pkt (no VLAN)
#$delay = '20us';  
$length = 98;
$DA = $ROUTER_PORT_1_MAC;
$SA = '01:55:55:55:55:55';
$dst_ip = '192.168.25.1';
$src_ip = '192.168.26.1';
$ct_type = 0;
$ct_name = '128.0.0.0';
$ct_vn = 1;
# --- CCDN
$pkt = make_CCCP_pkt($length, $DA, $SA, $TTL, $dst_ip, $src_ip, $ct_type, $ct_name, $ct_vn);
nf_packet_in(1, $length, $delay, $batch,  $pkt);

$DA = '01:50:17:20:fe:11';
$SA = $ROUTER_PORT_3_MAC;
# --- CCDN
$pkt = make_CCCP_pkt($length, $DA, $SA, $TTL-1, $dst_ip, $src_ip, $ct_type, $ct_name, $ct_vn);
nf_expected_packet(3, $length, $pkt);


# *********** Finishing Up - need this in all scripts ! ****************************
my $t = nf_write_sim_files();
print  "--- make_pkts.pl: Generated all configuration packets.\n";
printf "--- make_pkts.pl: Last packet enters system at approx %0d microseconds.\n",($t/1000);
if (nf_write_expected_files()) {
  die "Unable to write expected files\n";
}

nf_create_hardware_file('LITTLE_ENDIAN');
nf_write_hardware_file('LITTLE_ENDIAN');
