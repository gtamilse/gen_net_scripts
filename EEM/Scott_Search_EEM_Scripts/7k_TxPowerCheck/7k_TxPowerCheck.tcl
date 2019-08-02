#!/usr/bin/tclsh

#------------------------------------------------------------------
# 7k_TxPowerCheck EEM Script
#
# June, July 2016 - Scott Search (ssearch@cisco.com)
#
# This EEM script will be triggered off the following syslog message:
#     "%ETHPORT-3-IF_XCVR_ALARM: Interface Ethernet4/3, High Tx Power Alarm"
#
# Description:
#   This EEM script is triggered off the above syslog message.  After the script is triggered the script will
#   check every interface TxPower High Alarm value.  If the value is >= 5.29 the script will generate its own
#   syslog alarm with the interface name that is above this threshold.
#
# Copyright (c) 2016 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------

#set threshold 5.29
set threshold 3.00

proc get_Tx_values {syslogs} {
  global threshold
  set iface ""
  set TxPower ""
  set msg ""

  foreach line [split $syslogs "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp {^\w+.*\d+\/\d+$} $line]} {
      regexp {^(\w+.*\d+\/\d+)} $line - iface
    }

    if {$iface != ""} {
      if {[regexp {^Tx Power .* dBm$} $line]} {
        if {[regexp {\-\-} $line]} {
          if {[regexp {^Tx Power \-} $line]} {
            # If Tx Power current value is a negative we can safely ignore this.
            #regexp {^Tx Power \-(\d+\.\d+) dBm \-\- \d+\.\d+ dBm .* dBm$} $line - TxPower
          } else {
            regexp {^Tx Power (\d+\.\d+) dBm \-\- \d+\.\d+ dBm .* dBm$} $line - TxPower
          }
        } else {
          if {[regexp {^Tx Power \-} $line]} {
            # If Tx Power current value is a negative we can safely ignore this.
            #regexp {^Tx Power \-(\d+\.\d+) dBm \d+\.\d+ dBm .* dBm$} $line - TxPower
          } else {
            regexp {^Tx Power (\d+\.\d+) dBm \d+\.\d+ dBm .* dBm$} $line - TxPower
          }
        }

        if {$TxPower >= $threshold} {
          set msg "7k_TxPowerCheck:  Interface $iface TxPower $TxPower is  >=  to threshold ($threshold)"
          puts $msg

          cli "logit $msg"
        }
        set iface ""
        set TxPower ""
      }
    }
  }
} ;# get_Tx_values

set file [lindex $argv 0]
#puts "file: $file\n"

if {[file exists $file]} {
  set fh [open $file "r"]
  set data [read $fh]
  close $fh

  get_Tx_values $data
} else {
  puts "\n7k_TxPowerCheck: Unable to open input file:  $file\n\n"
}

