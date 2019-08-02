#!/usr/bin/python
# 
# Jason Froehlich
# March 20, 2012
# Revised: 8/17/12


CHOC12_INTERFACES = ["2/0"]
CHOC12_INT_COUNT = 400 # Max: 1008
T3_PER_CHOC12 = 12 #12
T1_PER_CHOC12 = 28 #28
CHOC12_STARTING_T3 = 6

CHOC48_INTERFACES = ["4/0"]
CHOC48_INT_COUNT = 400
T3_PER_CHOC48 = 48 #Max 48, rest will be POS

GIGABIT_INTERFACES = ["6/2", "14/3"]
GIGABIT_INT_COUNT = 400
VLAN_START = 3000

VRF_COUNT = 240
VRF_START = 1
VRF_PREFIX = "13979:50:"

IP_PREFIX = "20.50."
AS_START = 64500
QOS_POLICIES = 0
CE_INTERFACES = ["6/2","14/3"]

## Create VRFs
i = VRF_START
while i < VRF_COUNT + VRF_START:
    st = str(i)
    name = VRF_PREFIX + st
    print "ip vrf " + name
    print " description VRF " + name + " to Customer " + st
    print " rd 13979:" + str(i+200000)
    print " export map To_NM_VPN"
    print " route-target export 13979:" + str(i+1000)
    print " route-target import 13979:" + str(i+1000)
    print " route-target import 13979:103000"
    print " route-target import 13979:103010"
    print " route-target import 13979:103500"
    print " route-target import 13979:103510"
    print " maximum routes 20000 75"
    print "!"
    i += 1

#### Create QOS Policies
i = 1
while i <= QOS_POLICIES:
    name = "V4_Ex_" + str(i)
    i += 1
    print "policy-map " + name + "_out"
    print "  class rt_class"
    print "    priority"
    print "  police cir percent 20 conform-action transmit  exceed-action drop"
    print "  class class_b_output"
    print "    bandwidth remaining percent 60"
    print "    random-detect dscp-based"
    print "    random-detect dscp 24 400 ms 500 ms 1"
    print "    random-detect dscp 25 200 ms 250 ms 1"
    print "    random-detect dscp 26 400 ms 500 ms 1"
    print "    random-detect dscp 27 200 ms 250 ms 1"
    print "    random-detect dscp 28 200 ms 250 ms 1"
    print "    random-detect dscp 29 200 ms 250 ms 1"
    print "    random-detect dscp 30 200 ms 250 ms 1"
    print "    random-detect dscp 31 200 ms 250 ms 1"
    print "    random-detect dscp 48 400 ms 500 ms 1"
    print "    random-detect dscp 56 400 ms 500 ms 1"
    print "    queue-limit 1000 ms"
    print "  class class_c_output"
    print "    bandwidth remaining percent 30"
    print "    random-detect dscp-based"
    print "    random-detect dscp 16 400 ms 500 ms 1"
    print "    random-detect dscp 17 200 ms 250 ms 1"
    print "    random-detect dscp 18 400 ms 500 ms 1"
    print "    random-detect dscp 19 200 ms 250 ms 1"
    print "    random-detect dscp 20 200 ms 250 ms 1"
    print "    random-detect dscp 21 200 ms 250 ms 1"
    print "    random-detect dscp 23 200 ms 250 ms 1"
    print "    queue-limit 500 ms"
    print "  class class-default"
    print "    bandwidth remaining percent 10"
    print "    queue-limit 500 ms"
    print "!"

    print "policy-map " + name + "_out_par"
    print "  class class-default"
    print "    shape average 1000000"
    print "   service-policy " + name + "_out"

    print "policy-map " + name + "_in"
    print "  class customer_control_auto_rp"
    print "   police 256000 8000 8000 conform-action transmit  exceed-action drop"
    print "  class rt_class"
    print "   police cir percent 20 conform-action set-mpls-exp-imposition-transmit 5 exceed-action drop"
    print "  class class_b_in_contract"
    print "   police cir percent 48 conform-action set-mpls-exp-imposition-transmit 4 exceed-action set-mpls-exp-imposition-transmit 3"
    print "  class class_b_out_of_contract"
    print "   set mpls experimental imposition 3"
    print "  class class_c_in_contract"
    print "   police cir percent 24 conform-action set-mpls-exp-imposition-transmit 4 exceed-action set-mpls-exp-imposition-transmit 3"
    print "  class class_c_out_of_contract"
    print "   set mpls experimental imposition 3"
    print "  class customer_control"
    print "   set mpls experimental imposition 4"
    print "  class class-default"
    print "   set mpls experimental imposition 3"
    print "!"   

## Create CHOC-12 Channels
for ifid in CHOC12_INTERFACES:
    print "controller SONET " + ifid
    print " description [desc]"
    print " clock source line"
    print " report all"
    print " ais-shut"
    print " framing sonet"
    print " delay triggers path 2500"
    print " !"
    k = 1
    while k <= T3_PER_CHOC12:
        print " sts-1 " + str(k)
        print "  overhead j1 message RP-Slot1/0/1"
        print "  mode ct3"
        print "  t3 framing c-bit"
        l = 1
        t1count = 0
        while l <= T1_PER_CHOC12 and t1count <=30: #35 is max ints per sts
            t1 = str(l)
	    if CHOC12_INT_COUNT <= 336:
                t1count += 1
                print "  t1 " + t1 + " channel-group 0 timeslots 1-24"
	    else:
                t1count += 3
                print "  t1 " + t1 + " channel-group 0 timeslots 1-8"
                print "  t1 " + t1 + " channel-group 1 timeslots 9-16"
                print "  t1 " + t1 + " channel-group 2 timeslots 17-24"
            l += 1
        k += 1
print "!"

## Create CHOC-48 Channels
for ifid in CHOC48_INTERFACES:
    print "controller SONET " + ifid
    print " description [desc]"
    k = 1
    while k <= T3_PER_CHOC48:
        print " sts-1 " + str(k) + " serial t3"
        k += 1


## Interface Counters
current_vlan = VLAN_START
used_vrfs = 0
b3 = 0
b4 = 0
vrf_neighbors = {}
ce_vrf_neighbors = {}


##Create Gigabit Interface and Subinterfaces
for ifid in GIGABIT_INTERFACES:
    print "interface GigabitEthernet " + ifid
    print " description ******"
    print " mtu 9152"
    print " bandwidth 1000000"
    print " no ip address"
    print " no ip directed-broadcast"
    print " no negotiation auto"
    print " no shutdown"
    print "!"
    k = 1
    while k <= GIGABIT_INT_COUNT:
        vrfid = str(VRF_START + used_vrfs % VRF_COUNT)
        ip_addr = IP_PREFIX + str(b3) + "." + str(b4 + 1)
        ip_neighbor = IP_PREFIX + str(b3) + "." + str(b4 + 2)
        print "interface GigabitEthernet " + ifid + "." + str(k)
        print " description ******"
        print " encapsulation dot1q " + str(current_vlan)
        print " ip vrf forwarding " + VRF_PREFIX + vrfid
        print " ip address " + ip_addr + " 255.255.255.252"
        print " no ip redirects"
        print " no ip directed-broadcast"
        print " no ip proxy-arp"
        print " no plim qos input map cos enable"
        print " no cdp enable"
        print " service-policy output cos_ge_4000K_0:40:30:30_output_1G"
        print " service-policy input cos_policy_0:40:30:30_input_4000K"
        print " no shutdown"
        print "!"
        if vrfid in vrf_neighbors:
            vrf_neighbors[vrfid].append(ip_neighbor)
        else:
            vrf_neighbors[vrfid] = [ip_neighbor]
        if ifid in CE_INTERFACES:
            if vrfid in ce_vrf_neighbors:
                ce_vrf_neighbors[vrfid].append(ip_addr)
            else:
                ce_vrf_neighbors[vrfid] = [ip_addr]
        if b4 >= 252:
            b3 += 1
            b4 = 0
        else:
            b4 += 4
        k += 1
        used_vrfs += 1
	current_vlan += 1

#Create CHOC-12 Subinterfaces
for ifid in CHOC12_INTERFACES:
    k = 1
    current_t3 = 1
    current_t1 = 1
    while k <= CHOC12_INT_COUNT and current_t3 <= T3_PER_CHOC12:
		if CHOC12_INT_COUNT <= 336:
			vrfid = str(VRF_START + used_vrfs % VRF_COUNT)
			ip_addr = IP_PREFIX + str(b3) + "." + str(b4 + 1)
			ip_neighbor = IP_PREFIX + str(b3) + "." + str(b4 + 2)
			print "interface Serial " + ifid + "." + str(current_t3) + "/" + str(current_t1) + ":0"
			print " description ******"
			print " bandwidth 1536"
			print " ip vrf forwarding " + VRF_PREFIX + vrfid
			print " ip address " + ip_addr + " 255.255.255.252"
			print " no ip redirects"
			print " no ip directed-broadcast"
			print " encapsulation ppp"
			print " carrier-delay msec 0"
			print " no peer neighbor-route"
			print " no cdp enable"
                        print " service-policy output cos_policy_40:40:30:30_output_12288K"
                        print " service-policy input cos_policy_40:40:30:30_input"
			print " no shutdown"
			print " hold-queue 1000 in"
			print "!"
			if vrfid in vrf_neighbors:
				vrf_neighbors[vrfid].append(ip_neighbor)
			else:
				vrf_neighbors[vrfid] = [ip_neighbor]
                        if ifid in CE_INTERFACES:
                            if vrfid in ce_vrf_neighbors:
                                ce_vrf_neighbors[vrfid].append(ip_addr)
                            else:
                                ce_vrf_neighbors[vrfid] = [ip_addr]
			if current_t1 >= T1_PER_CHOC12:
				current_t1 = 1
				current_t3 += 1
			else:
				current_t1 += 1
			if b4 >= 252:
				b3 += 1
				b4 = 0
			else:
				b4 += 4
			k += 1
			used_vrfs += 1
		else:
			for slot in [0,1,2]:
				vrfid = str(VRF_START +	 used_vrfs % VRF_COUNT)
				ip_addr = IP_PREFIX + str(b3) + "." + str(b4 + 1)
				ip_neighbor = IP_PREFIX + str(b3) + "." + str(b4 + 2)
				print "interface Serial " + ifid + "." + str(current_t3) + "/" + str(current_t1) + ":" + str(slot)
				print " description ******"
				print " bandwidth 512"
				print " ip vrf forwarding " + VRF_PREFIX + vrfid
				print " ip address " + ip_addr + " 255.255.255.252"
				print " no ip redirects"
				print " encapsulation ppp"
				print " carrier-delay msec 0"
				print " no peer neighbor-route"
				print " no cdp enable"
                                print " service-policy output cos_policy_0:60:30:10_output_1024K"
                                print " service-policy input cos_policy_0:60:30:10_input"
				print " hold-queue 1000 in"
				print " no shutdown"
				print "!"
				if vrfid in vrf_neighbors:
					vrf_neighbors[vrfid].append(ip_neighbor)
				else:
					vrf_neighbors[vrfid] = [ip_neighbor]
                                if ifid in CE_INTERFACES:
                                    if vrfid in ce_vrf_neighbors:
                                        ce_vrf_neighbors[vrfid].append(ip_addr)
                                    else:
                                        ce_vrf_neighbors[vrfid] = [ip_addr]
				k += 1
				used_vrfs += 1
                                if b4 >= 252:
                                    b3 += 1
                                    b4 = 0
                                else:
                                    b4 += 4

			if current_t1 >= 11:
				current_t1 = 1
				current_t3 += 1
			else:
				current_t1 += 1

#Create CHOC-48 Subinterfaces
for ifid in CHOC48_INTERFACES:
    k = 1
    used_vrfs = 0
    subs_per_int = CHOC48_INT_COUNT/48 + 1
    current_t3 = 1
    ##while k <= CHOC48_INT_COUNT:
    while current_t3 <= T3_PER_CHOC48:
        print "interface Serial " + ifid + ":" + str(current_t3)
        print " description ******"
        print " bandwidth 44736"
        print " no ip address"
        print " no ip redirects"
        print " no ip directed-broadcast"
        print " encapsulation frame-relay IETF"
        print " carrier-delay msec 0"
        print " crc 32"
        print " scramble"
        print " alarm-delay triggers report"
        print " alarm-delay triggers path 2500"
        print " no dsu remote accept"
        print " frame-relay lmi-type cisco"
        print " frame-relay intf-type dce"
        print " service-policy output cos_policy_0:0:0:100_output_44736K"
        print " service-policy input cos_policy_0:0:0:100_input"
        print " hold-queue 1000 in"
        print " no shutdown"
        print "!"
        j = 1
        while j <= subs_per_int and k <= CHOC48_INT_COUNT:
            vrfid = str(VRF_START + used_vrfs % VRF_COUNT)
            ip_addr = IP_PREFIX + str(b3) + "." + str(b4 + 1)
            ip_neighbor = IP_PREFIX + str(b3) + "." + str(b4 + 2)
            print "interface Serial " + ifid + ":" + str(current_t3) + "." + str(j) + " point-to-point"
            print " description ******"
            print " bandwidth 44736"
            print " ip vrf forwarding " + VRF_PREFIX + vrfid
            print " ip address " + ip_addr + " 255.255.255.252"
            print " no ip redirects"
            print " no ip directed-broadcast"
            print " no ip proxy-arp"
            print " snmp trap link-status"
            print " no cdp enable"
            print " frame-relay interface-dlci " + str(j+100) + " IETF"
            print "!"
            
            if vrfid in vrf_neighbors:
                vrf_neighbors[vrfid].append(ip_neighbor)
            else:
                vrf_neighbors[vrfid] = [ip_neighbor]
            if ifid in CE_INTERFACES:
                if vrfid in ce_vrf_neighbors:
                    ce_vrf_neighbors[vrfid].append(ip_addr)
                else:
                    ce_vrf_neighbors[vrfid] = [ip_addr]

            if b4 >= 252:
                b3 += 1
                b4 = 0
            else:
                b4 += 4
            j += 1
            k += 1
            used_vrfs += 1
        current_t3 += 1
    while current_t3 <= 48:
        print "interface POS" + ifid + ":" + str(current_t3)
        print " description ******"
        print " bandwidth"
        print " no ip address"
        print " no ip redirects"
        print " no ip directed-broadcast"
        print " encapsulation frame-relay IETF"
        print " carrier-delay msec 0"
        print " pos scramble-atm"
        print " pos delay triggers report"
        print " pos delay triggers path 2500"
        print " frame-relay lmi-type cisco"
        print " frame-relay intf-type dce"
        print " frame-relay broadcast-queue 256 1024000 300"
        print " service-policy output cos_policy_80:40:30:30_output_156M"
        print " service-policy input cos_policy_80:40:30:30_input_156M"
        print " hold-queue 1000 in"
        print " no shutdown"
        print "!"
        j = 1
        while j <= subs_per_int and k <= CHOC48_INT_COUNT:
            vrfid = str(VRF_START + used_vrfs % VRF_COUNT)
            ip_addr = IP_PREFIX + str(b3) + "." + str(b4 + 1)
            ip_neighbor = IP_PREFIX + str(b3) + "." + str(b4 + 2)
            print "interface POS" + ifid + ":" + str(current_t3) + "." + str(j) + " point-to-point"
            print " description ******"
            print " ip vrf forwarding " + VRF_PREFIX + vrfid
            print " ip address " + ip_addr + " 255.255.255.252"
            print " no ip redirects"
            print " no ip directed-broadcast"
            print " no ip proxy-arp"
            print " snmp trap link-status"
            print " no cdp enable"
            print " frame-relay interface-dlci " + str(j+100) + " IETF"
            print "!"
            
            if vrfid in vrf_neighbors:
                vrf_neighbors[vrfid].append(ip_neighbor)
            else:
                vrf_neighbors[vrfid] = [ip_neighbor]
            if ifid in CE_INTERFACES:
                if vrfid in ce_vrf_neighbors:
                    ce_vrf_neighbors[vrfid].append(ip_addr)
                else:
                    ce_vrf_neighbors[vrfid] = [ip_addr]
            if b4 >= 252:
                b3 += 1
                b4 = 0
            else:
                b4 += 4
            j += 1
            k += 1
            used_vrfs += 1
        current_t3 += 1

## Create BGP VRFs
i = VRF_START
b3 = 0
b4 = 0
print "router bgp 13979"
for st in vrf_neighbors:
    name = VRF_PREFIX + st
    print " address-family ipv4 vrf " + name
    print " redistribute connected"
    print " redistribute static"
    for ip in vrf_neighbors[st]:
        print " neighbor " + ip + " remote-as " + str(AS_START+i)
        print " neighbor " + ip + " description customer " + st
        print " neighbor " + ip + " activate"
        print " neighbor " + ip + " inherit peer-policy AS_OVERRIDE"
        print " neighbor " + ip + " route-map TO_UNMANAGED_CUST out"
    print " maximum-paths eibgp 6 import 2"
    print " default-information originate"
    print " no synchronization"
    print " bgp suppress-inactive"
    print " exit-address-family"
    print " !"
    i += 1
    if b4 >= 252:
        b3 += 1
        b4 = 0
    else:
        b4 += 4
print "!"






print ""
print "---------------------------------------------------------"
print ""


## Create CE BGP VRFs
i = VRF_START
b3 = 0
b4 = 0
print "router bgp 65000"
for st in ce_vrf_neighbors:
    name = VRF_PREFIX + st
    print " address-family ipv4 vrf " + name
    print " redistribute connected"
    print " redistribute static"
    for ip in ce_vrf_neighbors[st]:
        print " neighbor " + ip + " remote-as 13979"
        print " neighbor " + ip + " local-as " + str(AS_START+i)
        print " neighbor " + ip + " description customer " + st
        print " neighbor " + ip + " activate"
        print " neighbor " + ip + " inherit peer-policy AS_OVERRIDE"
        print " neighbor " + ip + " route-map TO_UNMANAGED_CUST out"
    print " maximum-paths eibgp 6 import 2"
    print " default-information originate"
    print " no synchronization"
    print " bgp suppress-inactive"
    print " exit-address-family"
    print " !"
    i += 1
    if b4 >= 252:
        b3 += 1
        b4 = 0
    else:
        b4 += 4
print "!"


