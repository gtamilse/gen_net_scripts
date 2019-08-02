::cisco::eem::event_register_none maxrun_sec 180

# ::cisco::eem::event_register_timer cron name LISP_DefineEID cron_entry "0-59 * * * *" maxrun_sec 180

#------------------------------------------------------------------
# LISP_DefineEID.tcl
#
# 5/27/14 - Scott Search (ssearch@cisco.com)
#
#
# Need to set the following EEM example environment variables:
# -------------------------------------------------------------
# set _LISP_EID_storage_location "disk0:/LISP_EID_Definition"
#
#
# This EEM script runs every 30 minutes.  The script execution time interval can be changed.  Set the execution time
# to 30 minutes for lab testing.  The script runs 6 show commands to gather information and determine if the script
# needs to configure and hardcode a new EID definition/registration.
#
#
# Copyright (c) 2014 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*


# Verify the environment vars:
if {![info exists _LISP_EID_storage_location]} {
  set result "**ERROR: EEM policy error environment var _LISP_EID_storage_location not set"
  action_syslog msg $result
  exit 1
}

####################
# Procedures
####################
proc clean_string {line} {
  # Trim up the line remove extra space/tabs:
  regsub -all {[ \r\t\n]+} $line " " line
  # Remove any leading white space:
  regsub -all {^[ ]} $line "" line
  # Remove any ending white space:
  regsub -all {[ ]$} $line "" line

  return $line
}

proc get_LISP_processes {output} {
  set lisp_processes ""

  foreach line [split $output "\n"] {
    set line [clean_string $line]

    if {[regexp {^router } $line]} {
      lappend lisp_processes [lindex [split $line " "] end]
    }
  }
  set lisp_processes [lsort -unique $lisp_processes]
  return $lisp_processes
}

proc verify_eem_managed {output} {
  set eem_managed 0

  foreach line [split $output "\n"] {
    set line [clean_string $line]

    if {$line != ""} {
      if {[regexp {^Description: } $line]} {
        if {[regexp {EEM-managed} $line]} {
          set eem_managed 1
        }
      }
    }
  }
  return $eem_managed
}

proc get_transport_vrf {output} {
  set transport_vrf ""

  foreach line [split $output "\n"] {
    set line [clean_string $line]
  
    if {$line != ""} {
      if {[regexp {^Locator table: vrf } $line]} {
        set transport_vrf [lindex [split $line " "] end]
      }
    }
  }
  return $transport_vrf
}

proc verify_registered_prefixes {output} {
  global FH
  set kont 0

  foreach line [split $output "\n"] {
    set line [clean_string $line]

    if {$line != ""} {
      # Looking for lines that end in a prefix and mask
      if {[regexp {[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$} $line] || [regexp {\:\:\/[0-9]+$} $line] } {
        set fields [split $line " "]
        set site_name     [lindex $fields 0]
        set last_reg      [lindex $fields 1]
        set UP            [lindex $fields 2]
        set who_last_reg  [lindex $fields 3]
        set InstanceID    [lindex $fields 4]
        set EID_prefix    [lindex $fields 5]

        #puts $FH "found EID: $EID_prefix"
        # The lassign is not supported in the TCL version running on the LISP router
        #lassign $fields site_name last_reg UP who_last_reg InstanceID EID_prefix

        if {$EID_prefix == "" && $site_name == "never" || [regexp {[0-9]+\:[0-9]+\:[0-9]+} $site_name]} {
          set fields [split $line " "]
          set last_reg      [lindex $fields 0]
          set UP            [lindex $fields 1]
          set who_last_reg  [lindex $fields 2]
          set InstanceID    [lindex $fields 3]
          set EID_prefix    [lindex $fields 4]

          # The lassign is not supported in the TCL version running on the LISP router
          #lassign $fields last_reg UP who_last_reg InstanceID EID_prefix

          if {[regexp {^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$} $who_last_reg]} {
            puts $FH "last_reg: $last_reg --  UP: $UP"
            puts $FH "who_last_reg: $who_last_reg -- InstanceID: $InstanceID -- EID_prefix: $EID_prefix"

            if {$InstanceID != "" && $EID_prefix != ""} {
              set array1($kont) [list $InstanceID $EID_prefix]
              incr kont
            }
          }
        }
      }
    }
  }
  return [array get array1]
}

proc examine_prefix {output} {
  set RouteTag "NA"
  set ETRaddress "NA"
  set LocatorAddress "NA"
  set locator 0

  foreach line [split $output "\n"] {
    set line [clean_string $line]
  
    if {$line != ""} {
      if {[regexp {^Routing table tag} $line]} {
        set RouteTag [lindex [split $line " "] end]
      }
      if {[regexp {^ETR [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+} $line ]} {
        regexp {([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)} $line ETRaddress
      }
      if {[regexp {^ETR [0-9\]+\:[0-9\:]+} $line]} {
        regexp {([0-9]+\:[0-9\:]+)} $line ETRaddress
      }
      if {[regexp {^Locator Local} $line]} {
        set locator 1
      }
      if {$locator == 1} {
        if {[regexp {^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+} $line]} {
          regexp {^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)} $line LocatorAddress
        }
        if {[regexp {^[0-9]+\:[0-9\:]+} $line]} {
          regexp {^([0-9]+\:[0-9\:]+)} $line LocatorAddress
        }
      }
    }
  }
  return $LocatorAddress
} 

proc get_community {output} {
  set community "NA"
  set BestPath 0

  foreach line [split $output "\n"] {
    set line [clean_string $line]
  
    if {$line != ""} {
      if {[regexp {available} $line] && [regexp {best} $line]} {
        set BestPath 1
      }
      if {$BestPath == 1} {
        if {[regexp {^Community: } $line]} {
          set community [lindex [split $line " "] end]
        }
      }

      if {$community != "NA"} {
        return $community
      }
    }
  }
  return $community
} 


####################
# MAIN/main
####################
global FH
set msg ""
set cmd ""
set lisp_processes ""
set ConfigUpdated 0
set node [info hostname]

set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
set stamp [clock format [clock sec] -format "%T_%b_%d_%Y"]
regsub -all {:} $stamp "." stamp

# Open logging file (this can be removed or commented out once EEM script testing is finalized)
set LogFile "$node.LISP_DefineEID.$stamp"


set _LISP_EID_storage_location [clean_string $_LISP_EID_storage_location]


if [catch {open "$_LISP_EID_storage_location/$LogFile" w} result] {
    error $result
}
set FH $result
puts $FH "\n======================================================================\n"

set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
puts $FH "Start Timestamp: $date"
puts $FH "Cisco LISP Define EID Script"
puts $FH "by: Scott Search (ssearch@cisco.com)\n"


# Open VTY connection to router
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}

if [catch {cli_exec $cli(fd) "enable"} result] {
  error $result $errorInfo
}

#####################################################################################
# Grab routers 'show clock' for testing EEM script execution
set cmd "show clock"
puts $FH "Running CMD: $cmd"
if [catch {cli_exec $cli(fd) $cmd} result] {
  error $result $errorInfo
}
set output $result
puts $FH "\n$output\n"
#####################################################################################


# Step 1: Get the LISP processes
set cmd "show run | inc router lisp"
puts $FH "\nStep 1 - Running CMD: $cmd"
if [catch {cli_exec $cli(fd) $cmd} result] {
  error $result $errorInfo
}
set output $result
puts $FH "\nOutput from 'show run | inc router lisp':\n$output\n"
set lisp_processes [get_LISP_processes $output]

if { [ llength $lisp_processes ] >= 1} {
  puts $FH "Found following LISP processes:\n$lisp_processes"

  # Next for each LISP process need to perform steps 2-7
  foreach process [split $lisp_processes " "] {
    puts $FH "\n**Working on LISP process: $process"

    # Step 2: Verify LISP process is EEM managed
    set cmd "show lisp $process site name 0000"
    puts $FH "\nStep 2 - Running CMD: $cmd"
    if [catch {cli_exec $cli(fd) $cmd} result] {
      error $result $errorInfo
    }
    set output $result
    set eem_managed [verify_eem_managed $output]
    puts $FH "Process $process EEM managed: $eem_managed"
  
    if {$eem_managed == 1} {
      # LISP process is EEM managed

      # Step 3: Record LISP transport VRF
      set cmd "show lisp $process"
      puts $FH "\nStep 3 - Running CMD: $cmd"
      if [catch {cli_exec $cli(fd) $cmd} result] {
        error $result $errorInfo
      }
      set output $result
      set transport_vrf [get_transport_vrf $output]
      puts $FH "Process $process transport VRF: $transport_vrf"

      if { [ llength $transport_vrf ] >= 1} {
        # Step 4: Find registered prefixes that do not have a defined Site Name
        set cmd "show lisp $process site"
        puts $FH "\nStep 4 - Running CMD: $cmd"
        if [catch {cli_exec $cli(fd) $cmd} result] {
          error $result $errorInfo
        }
        set output $result
        array set array1 [verify_registered_prefixes $output]

        if {[array exist array1]} {
          foreach key [array names array1] {
            set InstanceID [lindex $array1($key) 0]
            set EIDprefix  [lindex $array1($key) 1]

            if { [ llength $InstanceID ] >= 1 && [ llength $EIDprefix ] >= 1} {
              puts $FH "Working on process: $process Instance ID: $InstanceID EID prefix: $EIDprefix"

              # Step 5: Get Locator Address
              set cmd "show lisp $process site $EIDprefix instance-id $InstanceID"
              puts $FH "\nStep 5 - Running CMD: $cmd"
              if [catch {cli_exec $cli(fd) $cmd} result] {
                error $result $errorInfo
              }
              set output $result
              set LocatorAddress [examine_prefix $output]
              puts $FH "Process $process Locator Address: $LocatorAddress"

              if { [ llength $LocatorAddress ] >= 1 && $LocatorAddress != 0} {
                set cmd "show ip bgp vpnv4 vrf $transport_vrf $LocatorAddress"

                if {[regexp {^[0-9]+\:[0-9:]+} $LocatorAddress]} {
                  # Locator is IPv6
                  set cmd "show ip bgp vpnv6 unicast vrf $transport_vrf $LocatorAddress"
                }
                # Step 6: Get community value
                puts $FH "\nStep 6 - Running CMD: $cmd"
                if [catch {cli_exec $cli(fd) $cmd} result] {
                  error $result $errorInfo
                }
                set output $result
                set community [get_community $output]
                puts $FH "Process $process Locator Address: $LocatorAddress Community: $community"

                if { [ llength $community ] >= 1 && $community != "NA"} {
                  # Step 7: Configure the new EID prefix definition
                  puts $FH "\nStep 7 - Configuring the new EID prefix definition details below:"
                  puts $FH "router lisp $process"
                  puts $FH "site 0000"
                  set cmd "eid-prefix instance-id $InstanceID $EIDprefix route-tag $community"
                  puts $FH "$cmd\n"

                  if [catch {cli_exec $cli(fd) "config t"} result] {
                    error $result $errorInfo
                  }
                  if [catch {cli_exec $cli(fd) "router lisp $process"} result] {
                    error $result $errorInfo
                  }
                  if [catch {cli_exec $cli(fd) "site 0000"} result] {
                    error $result $errorInfo
                  }
                  if [catch {cli_exec $cli(fd) $cmd} result] {
                    error $result $errorInfo
                  }
                  if [catch {cli_exec $cli(fd) "end"} result] {
                    error $result $errorInfo
                  }
                  if [catch {cli_exec $cli(fd) "wr mem"} result] {
                    error $result $errorInfo
                  }
                  set ConfigUpdated 1
                }
              }
            }
          }
        }
      }
    }
  }
  if {$ConfigUpdated == 1} {
    set msg "Completed the LISP Registration EID EEM Script - Possible Configuration Changes Made" 
  } else {
    set msg "Completed the LISP Registration EID EEM Script - No Configuration Changes Made (0)" 
  }
} else {
  set msg "Completed the LISP Registration EID EEM Script - No Configuration Changes Made (1)" 
  puts $FH "Found NO LISP processes"
}

# Close CLI
cli_close $cli(fd) $cli(tty_id)

puts $FH "\n****************************************"
puts $FH "$msg\n" 
action_syslog msg $msg

close $FH

