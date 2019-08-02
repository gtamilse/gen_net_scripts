#!/usr/bin/python
# -*- coding: latin-1 -*-
# 
# Jason Froehlich
# March 20, 2012
# Revised: 3/20/12

import os, sys


# CHOC12_INTERFACES = ["0/0/0/0"]
# CHOC12_INT_COUNT = 336 # Max: 1008
# T3_PER_CHOC12 = 12 #12
# T1_PER_CHOC12 = 28 #28


CHOC48_INTERFACES = ["0/2/0/0"]
CHOC48_INT_COUNT = 100
T3_PER_CHOC48 = 32 #Max 48, rest will be POS

# GIGABIT_INTERFACES = ["0/6/0/2"]
# GIGABIT_INT_COUNT = 400
# VLAN_START = 3000

VRF_COUNT = 100
VRF_START = 1
VRF_PREFIX = "13979:7:"

IP_PREFIX = "7.7."
AS_START = 64500
QOS_POLICIES = 400 


## Create VRFs
i = VRF_START
while i < VRF_COUNT + VRF_START:
    st = str(i)
    name = VRF_PREFIX + st
    print "vrf " + name
    print "  description VRF " + name + " to Customer " + st
    print " address-family ipv4 unicast"
    print "  import route-target"
    print "   13979:" + st
    print "  !"
    print "  export route-target"
    print "   13979:" + st
    print " !"
    print "!"
    i += 1

## Create QOS Policies
i = 1
while i <= QOS_POLICIES:
    name = "V4_Ex_" + str(i)
    i += 1
    print "policy-map " + name + "_out"
    print " class cos1_class"
    print "  priority"
    print "  police rate percent 40 burst 250 ms peak-burst 250 ms"
    print "  exceed-action drop"
    print " class control_class"
    print "  bandwidth percent 5"
    print "  queue-limit 1740"
    print " class cos2_class"
    print "  bandwidth remaining percent 60"
    print "  random-detect dscp 24 1228 1740"
    print "  random-detect dscp 26 1228 1740"
    print "  random-detect dscp 25 614 870"
    print "  random-detect dscp 27 614 870"
    print "  random-detect dscp 28 614 870"
    print "  random-detect dscp 29 614 870"
    print "  random-detect dscp 30 614 870"
    print "  random-detect dscp 31 614 870"
    print "  queue-limit 1740"
    print " class cos3_class"
    print "  bandwidth remaining percent 30"
    print "  random-detect dscp 16 1228 1740"
    print "  random-detect dscp 18 1228 1740"
    print "  random-detect dscp 17 614 870"
    print "  random-detect dscp 19 614 870"
    print "  random-detect dscp 20 614 870"
    print "  random-detect dscp 21 614 870"
    print "  random-detect dscp 22 614 870"
    print "  random-detect dscp 23 614 870"
    print "  queue-limit 1740"
    print " class class-default"
    print "  bandwidth remaining percent 10"
    print "  queue-limit 1740"
    print "!"

    print "policy-map " + name + "_in"
    print " class customer_control_auto_rp"
    print "  police rate 256000 bps"
    print "  conform-action transmit"
    print "  exceed-action drop"
    print " class control_class"
    print "  set mpls experimental imposition 4"
    print "  set prec tunnel 4"
    print " class cos1_class"
    print "  police rate percent 70  burst 250 ms peak-burst 250 ms"
    print "  conform-action set mpls experimental imposition 5"
    print "  conform-action set prec tunnel 5"
    print "  exceed-action drop"
    print " class cos2_in"
    print "  police rate percent 12 burst 250 ms peak-burst 250 ms"
    print "  conform-action set mpls experimental imposition 4"
    print "  conform-action set prec tunnel 4"
    print "  exceed-action set mpls experimental imposition 3"
    print "  exceed-action set prec tunnel 3"
    print " class cos2_out"
    print "  set mpls experimental imposition 3"
    print "  set prec tunnel 3"
    print " class cos3_in"
    print "  police rate percent 9 burst 250 ms peak-burst 250 ms"
    print "  conform-action set mpls experimental imposition 4"
    print "  conform-action set prec tunnel 4"
    print "  exceed-action set mpls experimental imposition 3"
    print "  exceed-action set prec tunnel 3"
    print " class cos3_out"
    print "  set mpls experimental imposition 3"
    print "  set prec tunnel 3"
    print " class class-default"
    print "  set mpls experimental imposition 3"
    print "  set prec tunnel 3"
    print "!"   

# ## Create CHOC-12 Channels
# for ifid in CHOC12_INTERFACES:
    # print "controller SONET " + ifid
    # print " description [desc]"
    # print " threshold sf-ber 4"
    # print " clock source internal"
    # print " framing sonet"
    # k = 1
    # while k <= T3_PER_CHOC12:
        # print " sts " + str(k)
        # print "  delay trigger 2500"
        # print "  width 1"
        # print "  overhead j1  ****PE-8 TEST****"
        # print "  mode t3"
        # print " !"
        # k += 1
    # print "!"
    # k = 1
    # while k <= T3_PER_CHOC12:
        # t3 = str(k)
        # print "controller T3 " + ifid + "/" + t3
        # print " delay trigger 2500"
        # print " clock source internal"
        # print " mode t1"
        # print " framing c-bit"
        # print "!"
        # l = 1
        # while l <= T1_PER_CHOC12:
            # t1 = str(l)
	    # if CHOC12_INT_COUNT <= 336:
                # print "controller T1 " + ifid + "/" + t3 + "/" + t1
                # print " delay trigger 2500"
                # print " channel-group 0"
                # print "  timeslots 1-24"
                # print " !"
                # print "!"
	    # else:
                # print "controller T1 " + ifid + "/" + t3 + "/" + t1
                # print " delay trigger 2500"
                # print " channel-group 0"
                # print "  timeslots 1-8"
                # print " channel-group 1"
                # print "  timeslots 9-16"
                # print " !"
                # print " channel-group 2"
                # print "  timeslots 17-24"
                # print " !"
                # print "!"
            # l += 1
        # k += 1

## Create CHOC-48 Channels
for ifid in CHOC48_INTERFACES:
    print "controller SONET " + ifid
    print " description [desc]"
    print " threshold sf-ber 4"
    print " clock source internal"
    print " framing sonet"
    k = 1
    while k <= T3_PER_CHOC48:
        print " sts " + str(k)
        print "  delay trigger 2500"
        print "  mode t3"
        print " !"
        k += 1
    while k <= 48:
        print " sts " + str(k)
        print "  delay trigger 2500"
        print "  mode pos scramble"
        print " !"
        k += 1
    print "!"
    k = 1
    while k <= T3_PER_CHOC48:
        t3 = str(k)
        print "controller T3 " + ifid + "/" + t3
        print " delay trigger 2500"
#        print " clock source internal"
        print " mode serial"
        print "!"
        k += 1


## Interface Counters
#current_vlan = VLAN_START
used_vrfs = 0
b3 = 0
b4 = 0
vrf_neighbors = {}


# ##Create Gigabit Interface and Subinterfaces
# for ifid in GIGABIT_INTERFACES:
    # print "interface GigabitEthernet " + ifid
    # print " description ******"
    # print " no ipv4 address"
    # print " bandwidth 1000000"
    # print " mtu 9122"
    # print " carrier-delay up 2000 down 2000"
    # print " no negotiation auto"
    # print " no shutdown"
    # print "!"
    # k = 1
    # while k <= GIGABIT_INT_COUNT:
        # vrfid = str(VRF_START + used_vrfs % VRF_COUNT)
        # ip_addr = IP_PREFIX + str(b3) + "." + str(b4 + 1)
        # ip_neighbor = IP_PREFIX + str(b3) + "." + str(b4 + 2)
        # print "interface GigabitEthernet " + ifid + "." + str(k)
        # print " description ******"
        # print " ipv4 mtu 4470"
        # print " dot1q vlan " + str(current_vlan)
        # print " vrf " + VRF_PREFIX + vrfid
        # print " ipv4 address " + ip_addr + "/30"
        # print " no ipv4 redirects"
        # print " no proxy-arp"
        # print " service-policy output V4_Ex_" + str(k) + "_out"
        # print " service-policy input V4_Ex_" + str(k) + "_in"
        # print " no shutdown"
        # print "!"
        # if vrfid in vrf_neighbors:
            # vrf_neighbors[vrfid].append(ip_neighbor)
        # else:
            # vrf_neighbors[vrfid] = [ip_neighbor]
        # if b4 >= 252:
            # b3 += 1
            # b4 = 0
        # else:
            # b4 += 4
        # k += 1
        # used_vrfs += 1
	# current_vlan += 1

# #Create CHOC-12 Subinterfaces
# for ifid in CHOC12_INTERFACES:
    # k = 1
    # current_t3 = 1
    # current_t1 = 1
    # while k <= CHOC12_INT_COUNT:
		# if CHOC12_INT_COUNT <= 336:
			# vrfid = str(VRF_START + used_vrfs % VRF_COUNT)
			# ip_addr = IP_PREFIX + str(b3) + "." + str(b4 + 1)
			# ip_neighbor = IP_PREFIX + str(b3) + "." + str(b4 + 2)
			# print "interface Serial " + ifid + "/" + str(current_t3) + "/" + str(current_t1) + ":0"
			# print " description ******"
			# print " bandwidth 1536"
			# print " vrf " + VRF_PREFIX + vrfid
			# print " ipv4 address " + ip_addr + "/30"
			# print " no ipv4 redirects"
			# print " encapsulation ppp"
                        # print " service-policy output V4_Ex_" + str(k) + "_out"
                        # print " service-policy input V4_Ex_" + str(k) + "_in"
			# print " no shutdown"
			# print "!"
			# if vrfid in vrf_neighbors:
				# vrf_neighbors[vrfid].append(ip_neighbor)
			# else:
				# vrf_neighbors[vrfid] = [ip_neighbor]
			# if current_t1 >= T1_PER_CHOC12:
				# current_t1 = 1
				# current_t3 += 1
			# else:
				# current_t1 += 1
			# if b4 >= 252:
				# b3 += 1
				# b4 = 0
			# else:
				# b4 += 4
			# k += 1
			# used_vrfs += 1
		# else:
			# for slot in [0,1,2]:
				# vrfid = str(VRF_START +	 used_vrfs % VRF_COUNT)
				# ip_addr = IP_PREFIX + str(b3) + "." + str(b4 + 1)
				# ip_neighbor = IP_PREFIX + str(b3) + "." + str(b4 + 2)
				# print "interface Serial " + ifid + "/" + str(current_t3) + "/" + str(current_t1) + ":" + str(slot)
				# print " description ******"
				# print " bandwidth 1536"
				# print " vrf " + VRF_PREFIX + vrfid
				# print " ipv4 address " + ip_addr + "/30"
				# print " no ipv4 redirects"
				# print " encapsulation ppp"
                                # print " service-policy output V4_Ex_" + str(k) + "_out"
                                # print " service-policy input V4_Ex_" + str(k) + "_in"
				# print " no shutdown"
				# print "!"
				# if vrfid in vrf_neighbors:
					# vrf_neighbors[vrfid].append(ip_neighbor)
				# else:
					# vrf_neighbors[vrfid] = [ip_neighbor]
				# k += 1
				# used_vrfs += 1
			# if current_t1 >= T1_PER_CHOC12:
				# current_t1 = 1
				# current_t3 += 1
			# else:
				# current_t1 += 1
			# if b4 >= 252:
				# b3 += 1
				# b4 = 0
			# else:
				# b4 += 4

#Create CHOC-48 Subinterfaces
for ifid in CHOC48_INTERFACES:
    k = 1
    used_vrfs = 0
    subs_per_int = CHOC48_INT_COUNT/48 + 1
    current_t3 = 1
    ##while k <= CHOC48_INT_COUNT:
    while current_t3 <= T3_PER_CHOC48:
        print "interface Serial " + ifid + "/" + str(current_t3)
        print " description ******"
        print " encapsulation frame-relay IETF"
        print " serial"
        print "  crc 16"
        print " frame-relay lmi-type cisco"
        print " frame-relay intf-type dce"
        print " service-policy output V4_Ex_" + str(k) + "_out"
        print " service-policy input V4_Ex_" + str(k) + "_in"
        print " no shutdown"
        print "!"
        j = 1
        while j <= subs_per_int and k <= CHOC48_INT_COUNT:
            vrfid = str(VRF_START + used_vrfs % VRF_COUNT)
            ip_addr = IP_PREFIX + str(b3) + "." + str(b4 + 1)
            ip_neighbor = IP_PREFIX + str(b3) + "." + str(b4 + 2)
            print "interface Serial " + ifid + "/" + str(current_t3) + "." + str(j) + " point-to-point"
            print " description ******"
            print " vrf " + VRF_PREFIX + vrfid
            print " ipv4 address " + ip_addr + "/30"
            print " bandwidth 1536"
            print " pvc " + str(j+100)
            print "  encap ietf"
            print " !"
            print "!"
            
            if vrfid in vrf_neighbors:
                vrf_neighbors[vrfid].append(ip_neighbor)
            else:
                vrf_neighbors[vrfid] = [ip_neighbor]
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
        print "interface POS" + ifid + "/" + str(current_t3)
        print " description ******"
        print " encapsulation frame-relay IETF"
        print " pos"
        print "  crc 16"
        print " frame-relay lmi-type cisco"
        print " frame-relay intf-type dce"
        print " service-policy output V4_Ex_" + str(k) + "_out"
        print " service-policy input V4_Ex_" + str(k) + "_in"
        print " no shutdown"
        print "!"
        j = 1
        while j <= subs_per_int and k <= CHOC48_INT_COUNT:
            vrfid = str(VRF_START + used_vrfs % VRF_COUNT)
            ip_addr = IP_PREFIX + str(b3) + "." + str(b4 + 1)
            ip_neighbor = IP_PREFIX + str(b3) + "." + str(b4 + 2)
            print "interface POS" + ifid + "/" + str(current_t3) + "." + str(j) + " point-to-point"
            print " description ******"
            print " vrf " + VRF_PREFIX + vrfid
            print " ipv4 address " + ip_addr + "/30"
            print " bandwidth 1536"
            print " pvc " + str(j+100)
            print "  encap ietf"
            print " !"
            print "!"
            
            if vrfid in vrf_neighbors:
                vrf_neighbors[vrfid].append(ip_neighbor)
            else:
                vrf_neighbors[vrfid] = [ip_neighbor]
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
    print " vrf " + name
    print "  rd 13979:" + st
    print "  default-information originate"
    print "  address-family ipv4 unicast"
    print "   redistribute connected"
    print "   redistribute static"
    print "   maximum-paths eibgp 6"
    print "  !"
    for ip in vrf_neighbors[st]:
        print "  neighbor " + ip
        print "   remote-as " + str(AS_START+i)
        print "   description customer " + st
#        print "   use neighbor-group ******"
        print "   address-family ipv4 unicast"
#        print "    route-policy ***** out"
        print "   !"
    print "  !"
    print " !"
    i += 1
    if b4 >= 252:
        b3 += 1
        b4 = 0
    else:
        b4 += 4
print "!"


