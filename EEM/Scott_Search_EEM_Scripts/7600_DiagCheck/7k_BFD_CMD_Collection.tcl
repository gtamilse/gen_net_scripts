#!/usr/bin/tclsh

#------------------------------------------------------------------
# 7k_BFD_CMD_Collection EEM Script
#
# October 2016 - Scott Search (ssearch@cisco.com)
#
# This EEM script will be triggered off the following syslog message:
#     "  .*BGP-5-ADJCHANGE:.  *
#
# Description:
#
# Copyright (c) 2016 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------

proc GetModules {data} {
  set LC ""

  foreach line [split $data "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {$line == ""} {
      break
    }

    if {![regexp {Supervisor} $line]} {
      set first_column [lindex $line 0]
      if {[string is integer -strict $first_column]} {
        lappend LC $first_column
      }
    }
  }
  return $LC
}


proc GetVQI_IDs {data} {
  set VQI ""
  set VQI_IDs ""

  foreach line [split $data "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp {^\d+\:\d+ \d+ \d+} $line]} {
      regexp {^(\d+)\:\d+ \d+ \d+} $line - VQI
      #puts "VQI: $VQI"
 
      set hex [format %x $VQI]
      lappend VQI_IDs $hex
    }
  }
  return $VQI_IDs
}


proc GetLTLs {VQI data} {
  set update_VQI "0x$VQI"
  set LTL ""
  set LTLs ""

  foreach line [split $data "\n"] {
    regsub -all {[ \r\t\n]+} $line " " line
    regsub -all {^[ ]} $line "" line
    regsub -all {[ ]$} $line "" line

    if {[regexp "VQI\\($update_VQI" $line]} {
      regexp {^LTL\((0x.*?)\)\,} $line - LTL
      lappend LTLs $LTL
    }
  }
  return $LTLs
}



####################
# MAIN
####################
global FH
set LCs ""

# Capture start time:
set time_now [clock seconds]
set date_time [clock format $time_now -format "%m-%d-%Y_%H.%M.%S"]
set date [clock format $time_now -format "%T %Z %a %b %d %Y"]

set filename "BFD_Command_Collections.$date_time"
set output_file "/bootflash/$filename"

# Open the output file (for write):
if [catch {open $output_file w} result] {
    error $result
}
set FH $result

# Timestamp start time to the output log file:
puts $FH "Start Timestamp: $date"

# Collect the 'show module' output to get the LC locations
set result [cli "show module"]
puts $FH "OUTPUT:\n$result"
set LCs [GetModules $result]

set cmd ""
set kont 0
set VQI_IDs ""

# Process each LC module
foreach LC $LCs {
  set kont 0

  #
  # Next run the 'show hardware internal qengine' command to get the VQI ID
  #
  # We need to collect all the VQI ID's.  Then after exiting from the modules then run the following 
  # command below for all the collected VQI ID's:
  #
  # show system internal ethpm info module | grep -i vqi(vqi_hex)
  #
  for {set kont 0} {$kont <= 5} {incr kont} {
    set cmd "slot $LC show hardware internal qengine inst $kont voq-status non-empty"
    puts $FH "Running CMD: $cmd"
    set result [cli "$cmd"]
    puts $FH "OUTPUT:\n$result"

    # Parse the above command output for the VQI ID
    lappend VQI_IDs [GetVQI_IDs $result]
  }

  # Exit from the LC module
  set cmd "exit"
  $cmd
}


# Below get the LTL hex values for each VQI
set LTLs ""
foreach VQI $VQI_IDs {
  set cmd "show system internal ethpm info module | grep -i vqi(0x$VQI)"
  set result [cli "$cmd"]
  puts $FH "OUTPUT $cmd:\n$result"
  lappend LTLs [GetLTLs $VQI $result]
}


# Below get the 'show system internal pixm info ltl' information
foreach LTL $LTLs {
  set cmd "show system internal pixm info ltl $LTL"
  set result [cli "$cmd"]
  puts $FH "OUTPUT $cmd:\n$result"
}
