::cisco::eem::event_register_timer cron name bcc_v1_0 cron_entry "0,30 * * * *" maxrun_sec 540

#------------------------------------------------------------------
# Cisco Bundle Consistency Checker (BCC)
#
#
# March 2010 - Scott Search (ssearch@cisco.com)
#
#
# This tool verifies the configured and active/Up bundle interfaces.
# Verifies the Bundle is stable and/or healthy and the hardware
# programming is correct.  If one of the checks fails a syslog trap
# is sent to the configured syslog server(s).
#
#
# This tool is designed to run once or more times per day. Be aware
# that a node with many bundle interfaces you will want to run this
# tool with at least an hour in between runs.  A node with 10 active
# and Up bundle interfaces the tool takes approximately 2 minutes and
# 30 seconds.
#
#
#
# Copyright (c) 2010 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
#
#
#
# The namespace import commands that follow import some cisco TCL extensions
# that are required to run this script
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

#############################################################################################
# Below set the default vars (Eventualy will want to set these via a global EEM var):
#############################################################################################
set storage_location   "harddisk:/eem"
set output_file        "eem_bcc.log"
set wait_time          3  ;#  Default sleep/wait time to verify counters incrementing, etc

 
###########################################
# PROCEDURES
###########################################
proc sleep {wait_time} {
  after [expr {int($wait_time * 1000)}]
}

proc get_xr_version {retval} {
  set version ""

  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line

    if {[regexp "^Cisco IOS XR" $line]} {
      regexp {.* (\d+.\d+.\d+)} $line - version
    }
  }
  return $version
}

proc get_bundles {retval} {
  set bundles ""
  set bundle ""
 
  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line
    # Remove any ending white space:
    regsub -all {[ ]$} $line "" line
 
    if {[regexp {^Bundle-} $line] && ![regexp {Down|Shutdown} $line]} {
      set bundle [lindex [split $line " "] 0]
      if {![regexp {\.} $bundle]} {
        lappend bundles $bundle
      }
    }
  }
  return $bundles
}
 
proc get_bundle_members {bundle retval} {
  global FH flags bundle_int members members2
  set members ""
  set members2 ""
  set members_bw ""
  set kont 0
  set iface ""
  set iface2 ""
  set state ""
  set bw ""
  set bw_totals ""

  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line
  
    if {$line == ""} { set kont 0 }
    if {$kont == 2} { set kont 3 }
    if {[regexp "^Port" $line]} { incr kont }
    if {$kont == 1 && [regexp "^------" $line]} { incr kont }
    if {$kont == 3 && $line != ""} {
      set iface [lindex [split $line " "] 0]
      set state [lindex [split $line " "] 1]
      regsub -all {[a-zA-Z]} $state "" state
      set bw    [lindex [split $line " "] 4]
      if {$bw != ""} { lappend bw_totals $bw }
      # If state is not equal to 4 then flag this:
      if {$state != 4} {
        set msg "FLAG: $bundle_int $bundle|$iface|Member state not equal to 4 ($state)"
        puts $FH $msg
        lappend flags $msg
      }
      set iface2 $iface
      # Change the TenGig member 'Te' to 'ten':
      regsub -all {^(Te)} $iface2 "ten" iface2
      lappend members2 $iface2
      lappend members $iface
      lappend members_bw "$iface|$bw"
  
      puts $FH "iface: $iface"
      puts $FH "state: $state"
      puts $FH "bw: $bw"
    }
  }
  
  # Only need to perform the next section if the bundle type is POS:
  if {[regexp -nocase "pos" $bundle]} {
    puts $FH "POS bundle detected, need to determine egress/ingress entries"
    determine_num_entries $members_bw $bw_totals
  }
}

proc determine_num_entries {members_bw bw_totals} {
  global ingress_total_entries egress_total_entries highest_member FH
  set ingress_total_entries 0
  set egress_total_entries 0
  set highest_bw 0
  set num_high_keys 0
  set num_not_high_keys 0
  set high_key 0
  set highest_member ""
  set sorted_bw ""
  set sorted_bw_num 0

  set sorted_bw [lsort -unique -real $bw_totals]  ;# Unique list of BW totals
  set sorted_bw_num [llength $sorted_bw]    ;# Number of unique BW totals

  if {$sorted_bw_num > 1} {
    # If $sorted_bw_num is greater than 1 then there are mismatched Bandwidth members. This
    # will also change the Ingress HW Asic collection and Ingress HW programming
    # validation. The highest bandwidth member will be the Ingress HW data we collect and
    # verify since all 'sponge_queue' and 'uidb_index' will be based off the highest
    # BW member.
    puts $FH "POS bundle with more than one bandwidth"

    # Find the highest BW value:
    foreach key [split $sorted_bw " "] {
      if {$key > $high_key} { set high_key $key }
    }
    set highest_bw $high_key

    # Get the number of high_keys (number of high BW values):
    foreach val [split $bw_totals " "] {
      if {$val == $high_key} { incr num_high_keys }
    }
    set total_entries [expr $num_high_keys * 4]

    # Next update the total_entries with the number of BW's not equal to $high_key:
    foreach val [split $bw_totals " "] {
      if {$val != $high_key} { incr num_not_high_keys }
    }
    set total_entries [expr $total_entries + $num_not_high_keys]
    set egress_total_entries $total_entries

    foreach val [split $members_bw " "] {
      regexp {(.*)\|(\d+)} $val - mem bw
      if {$bw == $highest_bw} { set highest_member $mem }
    }
  } else {
    # Else no mismatched members.  Next  determine if the members are oc768 and if so set the
    # ingress num_entries multiply by 4 and egress multiply by 2:
    set bw0 [lindex $bw_totals 0]

    if {$bw0 >= 39000000} {
      # Only oc768 members, need to multiply by 4 and 2
      set num [llength $bw_totals]
      set ingress_total_entries [expr $num * 4]
      set egress_total_entries [expr $num * 2]
    }
  }
}

proc determine_xr_location {members} {
  global bundle_member_locations FH
  set chassis 0
  set slot 0
  set subslot 0
  set port 0
  set iface ""
  set locale ""

  foreach iface [split $members " "] {
    regexp {.*(\d+)\/(\d+)\/(\d+)\/(\d+)} $iface - chassis slot subslot port
    set locale "$chassis/$slot/cpu0"
    lappend bundle_member_locations $locale
    puts $FH "iface: $iface Location: $locale"
  }
}

proc determine_xr_location2 {members} {
  global FH
  set chassis 0
  set slot 0
  set subslot 0
  set port 0
  set iface ""
  set locale ""

  foreach iface [split $members " "] {
    regexp {.*(\d+)\/(\d+)\/(\d+)\/(\d+)} $iface - chassis slot subslot port
    set locale "$chassis/$slot/cpu0"
    puts $FH "iface: $iface Location: $locale"
  }
  return $locale
}

proc iir_interface_process {members location retval} {
  global FH flags bundle_int num_bundle_members
  set iir_member_id ""
  set kont 0
  set partial ""
  set numerical ""
  set result 0
  set flag ""
  set id ""

  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line
    # Remove any ending white space:
    regsub -all {[ ]$} $line "" line

    foreach member [split $members " "] {
      regexp {^\w+(\d+\/\d+\/\d+\/\d+)} $member - numerical
      set line2 $line
      # Remove the alpha characters at the beginning of the line to match with the member id:
      regsub -all {^\D+} $line2 "" line2
      if {[regexp "^$numerical" $line2]} {
        incr kont
        set flag [lindex [split $line " "] 2]
        set id [lindex [split $line " "] end]
        lappend iir_member_id $id
        # Extract the member location to verify the CL flag exists:
        regexp {^\w+(\d+\/\d+)} $line - partial
        set partial "$partial/cpu0"
        if {$partial == $location} {
          if {![regexp "CL" $flag]} {
            set msg "FLAG: $bundle_int Bundle member $member IIR flag not set to CL ($flag)"
            puts $FH $msg
            lappend flags $msg
            set result 1
          } else { puts $FH "IIR flags good ($flag)" }
        }
      }
    }
  }
  # $kont should equal the number of member ids
  if {$kont != $num_bundle_members} {
    set msg "FLAG: $bundle_int IIR int verify found discrepency in bundle member count ($kont:$num_bundle_members)"
    puts $FH $msg
    lappend flags $msg
    set result 1
  }

  set iir_member_id [lsort -unique $iir_member_id]
  set num_iir_ids [llength $iir_member_id]
  if {$num_iir_ids != $num_bundle_members} {
    set msg "FLAG: $bundle_int IIR int verify found duplicate IDs"
    puts $FH $msg
    lappend flags $msg
    set result 1
  } else { puts $FH "IIR interface IDs good" }
  if {!$result} { puts $FH "IIR interface check passed for location: $location" }
}

proc get_mtu {retval} {
  set mtu 0
  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line
 
    if {[regexp "^MTU" $line]} {
      regexp {^MTU (\d+) .*} $line - mtu
    }
  }
  return $mtu
}

proc verify_iir_bundle_ids {retval} {
  global FH flags bundle_int members num_bundle_members
  set kont 0
  set result 0
  set numerical ""
  set partial ""
  set iir_member_id ""
  set id ""

  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line
    # Remove any ending white space:
    regsub -all {[ ]$} $line "" line

    foreach member [split $members " "] {
      regexp {^\w+(\d+\/\d+\/\d+\/\d+)} $member - numerical
      set line2 $line
      # Remove the alpha characters at the beginning of the line to match with the member id:
      regsub -all {^\D+} $line2 "" line2
      if {[regexp "^$numerical" $line2]} {
        incr kont
        set id [lindex [split $line " "] end]
        lappend iir_member_id $id
      }
    }
  }
  # $kont should equal the number of member ids
  if {$kont != $num_bundle_members} {
    set msg "FLAG: $bundle_int Load balance hw entries found discrepency in bundle member count ($kont:$num_bundle_members)"
    puts $FH $msg
    lappend flags $msg
    set result 1
  }

  set iir_member_id [lsort -unique $iir_member_id]
  set num_iir_ids [llength $iir_member_id]
  if {$num_iir_ids != $num_bundle_members} {
    set msg "FLAG: $bundle_int Load balance hw entries found duplicate IDs"
    puts $FH $msg
    lappend flags $msg
    set result 1
  } else { puts $FH "Load balance hw entries Passed" }
}

proc ingress_hardware_info {location retval} {
  global location_egress_uidb location_egress_fabricq
  global FH flags bundle_int platform_mgr
  set egress_uidb 0 
  set egress_uidb_decimal 0
  set egress_fabq 0
  set egress_fabq_decimal 0
 
  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line
    # Remove any ending white space:
    regsub -all {[ ]$} $line "" line
 
    if {[regexp {^egress_uidb_index} $line]} {
      set egress_uidb [lindex [split $line " "] end]
      puts $FH "egress_uidb: $egress_uidb"
      if {$egress_uidb != 0} {
        # Convert hex to decimal:
        set egress_uidb_decimal [expr $egress_uidb]
        puts $FH "egress_uidb_decimal: $egress_uidb_decimal"
        set location_egress_uidb($location) "$egress_uidb:$egress_uidb_decimal"
      }
    }
    if {$platform_mgr == "hfrpm"} {
      # If xr_version is 3.6.x and below do the following:
      if {[regexp {^sponge queue} $line]} {
        set egress_fabq [lindex [split $line " "] end]
        puts $FH "egress_fabq: $egress_fabq"
        if {$egress_fabq != 0} {
          # Convert hex to decimal:
          set egress_fabq_decimal [expr $egress_fabq]
          puts $FH "egress_fabq_decimal: $egress_fabq_decimal"
          set location_egress_fabricq($location) "$egress_fabq:$egress_fabq_decimal"
        }
      }
    } elseif {$platform_mgr == "pm"} {
      # If xr_version is greater than 3.6.x then do the following:
      if {[regexp {^fabricq queue} $line]} {
        set egress_fabq [lindex [split $line " "] end]
        puts $FH "egress_fabq: $egress_fabq"
        if {$egress_fabq != 0} {
          # Convert hex to decimal:
          set egress_fabq_decimal [expr $egress_fabq]
          puts $FH "egress_fabq_decimal: $egress_fabq_decimal"
          set location_egress_fabricq($location) "$egress_fabq:$egress_fabq_decimal"
        }
      }
    } else {
      # Need to flag this
      set msg "**ERROR: $bundle_int Cannot capture the fabricq_queue or sponge_queue due to xr version is unknown"
      puts $FH $msg
      lappend flags $msg
    }
  }
}

proc egress_hardware_info {member location retval} {
  global location_egressq
  global FH flags bundle_int platform_mgr egressqs
  set egressq 0
  set egressq_decimal 0
  set egressqs ""

  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line
    # Remove any ending white space:
    regsub -all {[ ]$} $line "" line

    if {$platform_mgr == "hfrpm"} {
      # If xr_version is 3.6.x and below do the following:
      if {[regexp {^sharq queue} $line]} {
        set egressq [lindex [split $line " "] end]
        puts $FH "egressq: $egressq"
        if {$egressq != ""} {
          # Convert hex to decimal:
          set egressq_decimal [expr $egressq]
          puts $FH "egressq_decimal: $egressq_decimal"
          lappend egressqs $egressq_decimal
        }
      }

    } elseif {$platform_mgr == "pm"} {
      # If xr_version is greater than 3.6.x then do the following:
      if {[regexp {^egressq queue} $line]} {
        set egressq [lindex [split $line " "] end]
        puts $FH "egressq: $egressq"
        if {$egressq != ""} {
          # Convert hex to decimal:
          set egressq_decimal [expr $egressq]
          puts $FH "egressq_decimal: $egressq_decimal"
          lappend egressqs $egressq_decimal
        }
      }
    } else {
      # Need to flag this
      set msg "**ERROR: $bundle_int Cannot capture sharq_queue or egressq_queue due to unknown xr version"
      puts $FH $msg
      lappend flags $msg
    }
  }
  if {$egressqs != 0} {
    set egressqs [lsort -unique -real $egressqs]
  } else {
    set msg "**ERROR: $bundle_int Unable to capture the egress hardware info"
    puts $FH $msg
    lappend flags $msg
  }
  return $egressqs
}

proc validate_ingress_hw {egress_uidb_hex egress_fabq_decimal retval} {
  global FH flags bundle_int ingress_total_entries modified_num_bundle_members
  set msg ""
  set num_entries ""
  set next_ptr ""
  set tlu4 ""
  set next_ptr_cutoff ""
  set length_next_ptr_cutoff ""
  set tlu4_len ""
  set len_diff ""
  set tlu4_cutoff ""
  set in_entries ""
  set sponge_queue ""
  set uidb_index ""
  set prev_step 0
  set validate_count 0
  set ingress_entries 0

  if {$ingress_total_entries != 0} {
    # If the 'ingress_total_entries' exists then set the $ingress_entries to it
    set ingress_entries $ingress_total_entries
  } else {
    set ingress_entries $modified_num_bundle_members
  }

  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line
    # Remove any ending white space:
    regsub -all {[ ]$} $line "" line

    # Get the bundle number of entries:
    if {[regexp {^num. entries} $line]} {
      incr validate_count
      regexp {.* (\d+)} $line - num_entries
      if {$num_entries != 0} {
        if {$num_entries != $ingress_entries} {
          set msg "**ERROR: $bundle_int Validate ingress HW failed num entries: $num_entries Total bundle members: $ingress_entries.**"
          puts $FH $msg
          lappend flags $msg
          set prev_step 1
        } else {
          set msg "Num entries found: $num_entries  Equals expected: $ingress_entries"
          puts $FH $msg
        }
      }
    }
    # Capture the 'next ptr' value:
    if {[regexp {^next ptr :} $line]} {
      incr validate_count
      regexp {next ptr : (.*)} $line - next_ptr
    }
    # Capture the 'TLU4' value:
    if {[regexp {^TLU4 :} $line]} {
      incr validate_count
      regexp {TLU4 : (.*)} $line - tlu4

      # Validate the next_ptr == tlu4:
      if {$next_ptr != "" && $tlu4 != ""} {
        # cut-off the first two characters (0x):
        set next_ptr_cutoff [string trimleft $next_ptr 0x]
        # next determine the string length of $next_ptr_cutoff:
        set length_next_ptr_cutoff [string length $next_ptr_cutoff]
        # get the length of the $tlu4 value:
        set tlu4_len [string length $tlu4]
        # get the string length difference:
        set len_diff [expr $tlu4_len - $length_next_ptr_cutoff]
        # cut-off the string length difference used to validate the next_ptr and tlu4:
        set tlu4_cutoff [string range $tlu4 $len_diff end]
 
        if {$next_ptr_cutoff == $tlu4_cutoff} {
          set msg "Validate ingress HW next_ptr ($next_ptr) and tlu4 ($tlu4) equal - PASSED"
          puts $FH $msg
        } else {
          set msg "**ERROR: $bundle_int Validate ingress HW next_ptr ($next_ptr) and tlu4 ($tlu4) DO NOT EQUAL! **"
          puts $FH $msg
          lappend flags $msg
          set prev_step 1
        }
      }
    }
    # If the line starts with "Entry[4]" reset the $in_entries var:
    if {[regexp {^Entry\[4\]} $line] || [regexp {^RP} $line]} {
      set in_entries 0
    }
    # Process the Entries 2,3:
    if {[regexp {^Entry\[2\]} $line] || $in_entries != 0} {
      incr validate_count
      set in_entries 1
      # Process the 'sponge queue' (3.6.x below) or 'fabricq queue' (3.8.x above) hex to decimal within the "sponge queue":
      if {[regexp {^sponge queue|^fabricq queue} $line]} {
        regexp {.* : (\d+)} $line - sponge_queue
        if {$sponge_queue != 0} {
          if {$sponge_queue != $egress_fabq_decimal} {
            set msg "**ERROR: $bundle_int Ingress HW sponge queue ($sponge_queue) NOT EQUAL to egress_fabq ($egress_fabq_decimal) **"
            puts $FH $msg
            lappend flags $msg
            set prev_step 1
          } else {
            puts $FH "Ingress HW sponge_queue $sponge_queue EQUALS egress_fabq $egress_fabq_decimal - GOOD"
          }
        }
      }
      # Process the "uidb index" and verify it matches the 'egress_uidb_index':
      if {[regexp {^uidb index} $line]} {
        incr validate_count
        regexp {uidb index : (.*)} $line - uidb_index
        if {$uidb_index != 0} {
          if {$uidb_index != $egress_uidb_hex} {
            set msg "**ERROR: $bundle_int Ingress HW uidb_index ($uidb_index) NOT EQUAL to egress_uidb_index ($egress_uidb_hex) **"
            puts $FH $msg
            lappend flags $msg
            set prev_step 1
          } else {
            puts $FH "Ingress HW uidb_index $uidb_index EQUALS egress_uidb_index $egress_uidb_hex - GOOD"
          }
        }
      }
    }
  }

  # The $validate_count should be above 3 at the end of this routine if the command
  # 'show cef mpls adjacency bundle-xxxx hardware ingress detail location x/x/cpu0 | beg local'
  # has the expected output recieved.  If not, then error out:
  if {$validate_count < 5} {
    set msg "**WARN: Ingress hardware programming validation failed, no command output detected! **"
    puts $FH $msg
    set prev_step 1
  }
  return $prev_step
}

proc validate_l2_hw_info {location retval} {
  global FH flags egress_total_entries modified_num_bundle_members num_bundle_members
  global bundle_int location_egressq
  set validate_count 0
  set num_entries ""
  set next_ptr ""
  set tlu4 ""
  set next_ptr_cutoff ""
  set length_next_ptr_cutoff ""
  set tlu4_len ""
  set len_diff ""
  set tlu4_cutoff ""
  set default_sharq ""
  set msg ""
  set prev_step 0
  set egress_entries 0
  set sharq ""
  set default_sharq ""   ;# Arrays in perl version
  set egressqs ""        ;# Arrays in perl version

  if {$egress_total_entries != 0} {
    # If the 'egress_total_entries' exists then set the $egress_entries to it
    set egress_entries $egress_total_entries
  } else {
    set egress_entries $modified_num_bundle_members
  }
  if {$location_egressq($location) != ""} {
    set egressqs $location_egressq($location)
  }
  puts $FH "Validate L2 HW Info - Location: $location egressqs: $egressqs"

  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line
    # Remove any ending white space:
    regsub -all {[ ]$} $line "" line

    # Get the bundle number of entries:
    if {[regexp {^num. entries} $line]} {
      regexp {.* (\d+)} $line - num_entries
      incr validate_count
      if {$num_entries != 0} {
        if {$num_entries != $egress_entries} {
          set msg "**ERROR: $bundle_int Egress L2 HW failed entries: $num_entries Total B-members (real:expected): $num_bundle_members:$egress_entries.**"
          puts $FH $msg
          lappend flags $msg
          set prev_step 1
        } else {
          set msg "Validate egress entries found: $num_entries  Expected: $egress_entries"
          puts $FH $msg
        }
      }
    }
  
    # Capture the 'next ptr' value:
    if {[regexp {^next ptr :} $line]} {
      regexp {next ptr : (.*)} $line - next_ptr
      incr validate_count
    }
    # Capture the 'TLU4' value:
    if {[regexp {^TLU4 :} $line]} {
      regexp {TLU4 : (.*)} $line - tlu4
      incr validate_count

      # Validate the next_ptr == tlu4:
      if {$next_ptr != "" && $tlu4 != ""} {
        # cut-off the first two characters (0x):
        set next_ptr_cutoff [string trimleft $next_ptr 0x]
        # next determine the string length of $next_ptr_cutoff:
        set length_next_ptr_cutoff [string length $next_ptr_cutoff]
        # get the length of the $tlu4 value:
        set tlu4_len [string length $tlu4]
        # get the string length difference:
        set len_diff [expr $tlu4_len - $length_next_ptr_cutoff]
        # cut-off the string length difference used to validate the next_ptr and tlu4:
        set tlu4_cutoff [string range $tlu4 $len_diff end]
 
        if {$next_ptr_cutoff == $tlu4_cutoff} {
          puts $FH "Validate egress L2 HW next_ptr ($next_ptr) and tlu4 ($tlu4) equal - PASSED"
        } else {
          set msg "**ERROR: $bundle_int Validate egress L2 HW next_ptr ($next_ptr) and tlu4 ($tlu4) DO NOT EQUAL! **"
          puts $FH $msg
          lappend flags $msg
          set prev_step 1
        }
      }
    }

    # Looking for lines that start with 'default sharq':
    if {[regexp {^default sharq} $line]} {
      regexp {.* : (\d+)} $line - sharq
      lappend default_sharq $sharq
      incr validate_count
    }
  }

  set default_sharq [lsort -unique -real $default_sharq]
  puts $FH "Validate L2 HW Info - default_sharqs found: $default_sharq"
  if {$egressqs == $default_sharq} {
    puts $FH "Validate L2 load balance hw info for default_sharq is GOOD."
  } elseif {$validate_count > 5} {
    set msg "**ERROR: $bundle_int L2 load balance hw info for default_sharq FAILED (location: $location\
             egressqs: $egressqs - Found default_sharq: $default_sharq)! **"
    set prev_step 1
    puts $FH $msg
    lappend flags $msg
  }

  # The $validate_count should be above 3 at the end of this routine if the command
  # 'sh cef ipv4 adjacency bundle-xxxx hardware egress detail location x/x/cpu0 | beg local'
  # has the expected output recieved.  If not, then error out:
  if {$validate_count < 5} {
    set msg "**WARN: Egress L2 hardware programming validation failed, no command output detected! **"
    puts $FH $msg
    set prev_step 1
  }
  return $prev_step
}

proc extract_interface_details {loop retval} {
  global FH flags int_stats bundle_int
  set kont 0
  set prev_step 0
  set num_members ""
  set is_distributing ""
  set msg ""
  set input_pkts 0
  set output_pkts 0
  set input_drops 0
  set output_drops 0
  set unrecognized_drops 0

  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line
    # Remove any ending white space:
    regsub -all {[ ]$} $line "" line

    # Get the total number of member bundles:
    if {[regexp {^No. of members} $line]} {
      regexp {.*: (\d+)$} $line - num_members
      puts $FH "No. of members found: $num_members"
    }
    # Verify all members of the bundle are in Distributing state:
    if {![regexp {^No. of members} $line]} {
      if {$num_members != "" && $kont < $num_members} {
        set is_distributing [lindex [split $line " "] end]
        if {$is_distributing != "Distributing"} {
          set msg "**ERROR: $bundle_int Bundle member not in Distributing state ($line) **"
          puts $FH $msg
          lappend flags $msg
          set prev_step 1
        }
        incr kont
      }
    }
    # Get the input packets counters:
    if {[regexp {^\d+ packets input,} $line]} {
      regexp {^(\d+) packets input, \d+ bytes, (\d+) .*} $line - input_pkts input_drops
      puts $FH "input_pkts: $input_pkts"
      puts $FH "input_drops: $input_drops"
    }
    # Get the output packets counters:
    if {[regexp {^\d+ packets output,} $line]} {
      regexp {^(\d+) packets output, \d+ bytes, (\d+) .*} $line - output_pkts output_drops
      puts $FH "output_pkts: $output_pkts"
      puts $FH "output_drops: $output_drops"
    }
    # Get the unrecognized drops:
    if {[regexp {^\d+ drops for unrecognized} $line]} {
      regexp {^(\d+) drops for unrecognized} $line - unrecognized_drops
      puts $FH "unrecogized_drops: $unrecognized_drops"
    }
  }
  set int_stats("$bundle_int:$loop") "$input_pkts $input_drops $output_pkts $output_drops $unrecognized_drops"
  return $prev_step
}

proc extract_lacp_details {loop member retval} {
  global FH flags int_stats bundle_int
  set sent_pkts 0
  set received_pkts 0
  set excess1 0
  set excess2 0
  set errors 0 

  foreach line [split $retval "\n"] {
    # Trim up the line remove extra space/tabs etc:
    regsub -all {[ \r\t\n]+} $line " " line
    # Remove any leading white space:
    regsub -all {^[ ]} $line "" line
    # Remove any ending white space:
    regsub -all {[ ]$} $line "" line

    # Capture the LACPUs:
    if {[regexp {^.*\d+\/\d+\/\d+ \d+ \d+ \d+ \d+ \w+} $line]} {
      regexp {^.*\d+\/\d+\/\d+ (\d+) (\d+) \d+ \d+ \w+} $line - sent_pkts received_pkts
    }
    # Capture the Excess and Errors:
    if {[regexp {^.*\d+\/\d+\/\d+ \d+ \d+ \d+$} $line]} {
      regexp {^.*\d+\/\d+\/\d+ (\d+) (\d+) (\d+)$} $line - excess1 excess2 errors
    }
  }
  puts $FH "sent_pkts: $sent_pkts - received_pkts: $received_pkts"
  puts $FH "excess1: $excess1 - excess2: $excess2 - errors: $errors"
  set int_stats("$member:$loop") "$sent_pkts $received_pkts $excess1 $excess2 $errors"
}


   
###########################################
# MAIN/main
###########################################
   
###########################################
# Globals:
global FH flags members members2 ingress_total_entries egress_total_entries highest_member
global num_bundle_members modified_num_bundle_members bundle_member_locations xr_version
global platform_mgr egressqs bundle_member_locations2 bundle_int
# Arrays:
global location_egress_uidb location_egress_fabricq location_egressq
global int_stats
array set location_egress_uidb {}
array set location_egress_fabricq {}
array set location_egressq {}
array set int_stats {}

set flags                    ""
set retval                   ""
set egressqs                 ""
set vers_first               ""
set vers_second              ""
set xr_version               ""
set bundle_int               ""
set members                  ""
set members2                 ""
set highest_member           ""
set bundle_member_locations  ""
set ingress_total_entries    0
set egress_total_entries     0


# Open the output file (for write):
if [catch {open $storage_location/$output_file w} result] {
    error $result
}
set FH $result
set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
puts $FH "*Timestamp = $date"
puts $FH "Cisco Bundle Consistency Checker (BCC)"
puts $FH "Designed for: Embedded Event Manager (EEM)"
puts $FH "by: Scott Search (ssearch@cisco.com)\n"
 
###########################################
# Node Connection
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}

# Get the XR version
if [catch {cli_exec $cli(fd) "show version | i Version"} result] {
  error $result $errorInfo
}
set retval $result
set xr_version [get_xr_version $retval]
puts $FH "XR version detected: $xr_version"
# Determine the hfrpm/pm command to run
if {$xr_version != ""} {
  regexp {(\d+).(\d+)} $xr_version - vers_first vers_second
  if {$vers_first <= 3 && $vers_second <= 6} {
    set platform_mgr "hfrpm"
  } else {
    set platform_mgr "pm"
  }
}
 
# Find all the active Bundle interfaces:
if [catch {cli_exec $cli(fd) "show ipv4 inter brief | inc Bundle"} result] {
  error $result $errorInfo
}
set retval $result

# Process the output and extract the Bundle interfaces:
set bundles [get_bundles $retval]
set bundles [lsort -unique $bundles]
 
# Next get the 'show bundle $bundle' data:
if {[string length $bundles]!=0} {
  foreach bundle_int [split $bundles " "] {
    array unset location_egress_uidb
    array unset location_egress_fabricq
    array unset location_egressq
    array unset int_stats

    set bundle_member_locations ""
    set iir_member_id ""
    set bundles ""
    set egressqs ""
    set members ""
    set members2 ""
 
    puts $FH "\n--------------------------------------------"
    puts $FH "Processing Bundle: $bundle_int"
 
    ###############################################################
    # Step 1: Gathering Bundle Info and States
    ###############################################################
    puts $FH "****Step 1: Gathering bundle info and states"
    set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
    puts $FH "*Timestamp = $date"

    if [catch {cli_exec $cli(fd) "show bundle $bundle_int"} result] {
      error $result $errorInfo
    }
    set bundle_data $result

    # Call the get_bundle_members proc to extract the bundle member data:
    get_bundle_members $bundle_int $bundle_data

    # The $members should be set, continue on:
    if {[string length $members]!=0} {
      puts $FH "highest_member: $highest_member"
      puts $FH "ingress_total_entries: $ingress_total_entries"
      puts $FH "egress_total_entries: $egress_total_entries"

      set num_bundle_members [llength $members]
      if {$ingress_total_entries} {
        # If the $ingress_total_entries exists then the modified_num_bundle_members will be updated accordingly:
        set modified_num_bundle_members $egress_total_entries
        puts $FH "total (1) Bundle Members for $bundle_int = $num_bundle_members (entries (i/e):\
                  $ingress_total_entries/$egress_total_entries"
      } elseif {$egress_total_entries} {
        set modified_num_bundle_members $egress_total_entries
        puts $FH "total (2) Bundle Members for $bundle_int = $num_bundle_members (entries: $modified_num_bundle_members)"
      } else {
        set modified_num_bundle_members $num_bundle_members
        puts $FH "total (3) Bundle Members for $bundle_int = $num_bundle_members (entries: $modified_num_bundle_members)"
      }

      ###############################################################
      # Step 2: Gather interface details and lacp counters
      ###############################################################
      puts $FH "\n****Step 2: Gather interface details and lacp counters"
      set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
      puts $FH "*Timestamp = $date"

      # Start the loop where we issue the commands below once, wait per wait_time then issue
      # the commands again.  If the script detects counter problems report them and ERROR out:
      set step2 0
      set msg  ""
      set run  1
      set loop  0
      set errs_found  0

      set input_pkts1 0
      set input_pkts2 0
      set input_drops1 0
      set input_drops2 0
      set output_pkts1 0
      set output_pkts2 0
      set output_drops1 0
      set output_drops2 0
      set unrecognized_drops1 0
      set unrecognized_drops2 0
      set sent_pkts1 0
      set sent_pkts2 0
      set received_pkts1 0
      set received_pkts2 0
      set excess1_1 0
      set excess1_2 0
      set excess2_1 0
      set excess2_2 0
      set errors1 0
      set errors2 0

      while {$run} {
        set cmd "show interf $bundle_int detail"
        puts $FH $cmd
        # Run cmd on node:
        if [catch {cli_exec $cli(fd) $cmd} result] {
          error $result $errorInfo
        }
        set retval $result
        set step2 [extract_interface_details $loop $retval]

        # Loop = 1 then second time through loop, verify counters/errors:
        if {$loop == 1} {
          set input_pkts1          [lindex [split $int_stats("$bundle_int:0") " "] 0]
          set input_pkts2          [lindex [split $int_stats("$bundle_int:1") " "] 0]
          set input_drops1         [lindex [split $int_stats("$bundle_int:0") " "] 1]
          set input_drops2         [lindex [split $int_stats("$bundle_int:1") " "] 1]
          set output_pkts1         [lindex [split $int_stats("$bundle_int:0") " "] 2]
          set output_pkts2         [lindex [split $int_stats("$bundle_int:1") " "] 2]
          set output_drops1        [lindex [split $int_stats("$bundle_int:0") " "] 3]
          set output_drops2        [lindex [split $int_stats("$bundle_int:1") " "] 3]
          set unrecognized_drops1  [lindex [split $int_stats("$bundle_int:0") " "] 4]
          set unrecognized_drops2  [lindex [split $int_stats("$bundle_int:1") " "] 4]
          
          set msg ""
          if {$input_pkts2 < $input_pkts1} { set errs_found 1; set msg "$msg\n**ERROR: Input packets not incrementing **" }
          if {$output_pkts2 < $output_pkts1} { set errs_found 1; set msg "$msg\n**ERROR: Output packets not incrementing **" }
          if {$input_drops2 > $input_drops1} { set errs_found 1; set msg "$msg\n**ERROR: Input drops incrementing **" }
          if {$output_drops2 > $output_drops1} { set errs_found 1; set msg "$msg\n**ERROR: Output drops incrementing **" }
          if {$unrecognized_drops2 > $unrecognized_drops1} {
            set errs_found 1; set msg "$msg\n**ERROR: Unrecognized drops incrementing **" }

          if {$errs_found} {
            set step2 1
            puts $FH $msg
            lappend flags $msg
          } elseif {$loop == 1} {
            # bundle interfaces counters are all good
            puts $FH "$bundle_int Bundle interface counters are good, no problems found."
          }
        }

        # Gather the LACP counter details per bundle member:
        foreach member [split $members " "] {
          set cmd "show lacp counter $bundle_int | include $member"
          puts $FH $cmd
          # Run cmd on node:
          if [catch {cli_exec $cli(fd) $cmd} result] {
            error $result $errorInfo
          }
          set retval $result
          set step2 [extract_lacp_details $loop $member $retval]

          if {$loop == 1} {
            set sent_pkts1      [lindex [split $int_stats("$member:0") " "] 0]
            set sent_pkts2      [lindex [split $int_stats("$member:1") " "] 0]
            set received_pkts1  [lindex [split $int_stats("$member:0") " "] 1]
            set received_pkts2  [lindex [split $int_stats("$member:1") " "] 1]
            set excess1_1       [lindex [split $int_stats("$member:0") " "] 2]
            set excess1_2       [lindex [split $int_stats("$member:1") " "] 2]
            set excess2_1       [lindex [split $int_stats("$member:0") " "] 3]
            set excess2_2       [lindex [split $int_stats("$member:1") " "] 3]
            set errors1         [lindex [split $int_stats("$member:0") " "] 4]
            set errors2         [lindex [split $int_stats("$member:1") " "] 4]

            set msg ""
            if {$sent_pkts1 > $sent_pkts2} {set errs_found 1; set msg "$msg\n**ERROR: LACP sent not incrementing **"}
            if {$received_pkts1 > $received_pkts2} {set errs_found 1; set msg "$msg\n**ERROR: LACP received not incrementing **"}
            if {$excess1_1 > $excess1_2} {set errs_found 1; set msg "$msg\n**ERROR: LACP Excess counter 1 is incrementing **"}
            if {$excess2_1 > $excess2_2} {set errs_found 1; set msg "$msg\n**ERROR: LACP Excess counter 2 is incrementing **"}
            if {$errors2 > $errors1} {set errs_found 1; set msg "$msg\n**ERROR: LACP Pkt Errors increasing **"}

            if {$errs_found} {
              set step2 1
              puts $FH $msg
              lappend $FH $msg
            } elseif {$loop == 1} {
              # LACP counters are all good
              puts $FH "$bundle_int Bundle member: $member LACP counters are good, no problems found."
            }
          }
        }
        if {$loop == 1} {
          # Loop is completed
          set run  0
        } else {
          # The Cisco IOS/IOX OS does not have a sleep or wait function, implementing a delay below:
          #for {set sleep 0} {$sleep <= 4500000} {incr sleep} {}
          # Actually the IOS/IOX builtin OS TCL utilizes the after function:
          sleep $wait_time
          incr loop
        }
      }


      ###############################################################
      # Step 3: Verify iir interface details
      ###############################################################
      puts $FH "\n****Step 3: Verify IIR interface details"
      set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
      puts $FH "*Timestamp = $date"

      # Next need to determine XR LC locations
      determine_xr_location $members
      set bundle_member_locations [lsort -unique $bundle_member_locations]
      set bundle_member_locations2 $bundle_member_locations

      foreach location [split $bundle_member_locations " "] {
        set cmd "show iir interface name $bundle_int location $location"
        puts $FH $cmd
        # Run cmd on node:
        if [catch {cli_exec $cli(fd) $cmd} result] {
          error $result $errorInfo
        }
        set retval $result
        # Process the cmd output:
        iir_interface_process $members $location $retval
      }

      ###############################################################
      # Step 4: Verify bundle and member links MTU is the same
      ###############################################################
      puts $FH "\n****Step 4: Verify bundle and member links MTU is the same"
      set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
      puts $FH "*Timestamp = $date"
      set pass 0

      # Get the bundle interface mtu:
      set cmd "show inter $bundle_int | includ MTU"
      puts $FH $cmd
      if [catch {cli_exec $cli(fd) $cmd} result] {
        error $result $errorInfo
      }
      set retval $result
      set main_mtu [get_mtu $retval]
      puts $FH "Main bundle $bundle_int mtu: $main_mtu"

      # Process each bundle member and verify the MTU's are the same:
      foreach iface [split $members2 " "] {
        set cmd "show inter $iface | includ MTU"
        puts $FH $cmd
        if [catch {cli_exec $cli(fd) $cmd} result] {
          error $result $errorInfo
        }
        set retval $result
        set member_mtu [get_mtu $retval]
        puts $FH "Member $iface mtu: $member_mtu"

        if {$member_mtu != $main_mtu} {
          set msg "FLAG: Bundle $bundle_int ($main_mtu) member $iface ($member_mtu) MTU mismatched"
          puts $FH $msg
          lappend flags $msg
          set pass 1
        }
      }
      if {!$pass} {puts $FH "MTU check Passed"}

      ###############################################################
      # Step 5: Determine order of load balance entries in hardware
      ###############################################################
      puts $FH "\n****Step 5: Determine order of load balance entries in hardware"
      set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
      puts $FH "*Timestamp = $date"

      set cmd "show iir interfaces name $bundle_int"
      puts $FH $cmd
      if [catch {cli_exec $cli(fd) $cmd} result] {
        error $result $errorInfo
      }
      set retval $result

      verify_iir_bundle_ids $retval

      ###############################################################
      # Step 6: Collect Ingress hardware ASIC allocation info
      ###############################################################
      puts $FH "\n****Step 6: Collect Ingress hardware ASIC allocation info"
      set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
      puts $FH "*Timestamp = $date"

      if {$highest_member != ""} {
        # If the $highest_member var exists then grab the location for this one member:
        set bundle_member_locations [determine_xr_location2 $highest_member]
      }

      foreach location [split $bundle_member_locations " "] {
        # Determine which xr command to run due to the XR version:
        set cmd "show controllers $platform_mgr inter $bundle_int loc $location"

        puts $FH $cmd
        if [catch {cli_exec $cli(fd) $cmd} result] {
          error $result $errorInfo
        }
        set retval $result

        ingress_hardware_info $location $retval
      }
      set location_egress_count [array size location_egress_uidb]
 
      if {$location_egress_count > 0} {
        # Array exists and egress_uidb/sponge queue/fabricq queue data collected successfully
        puts $FH "Collection of ingress hardare ASIC allocation information PASSED"
      } else {
        # Array does not exist and no egress_uidb/sponge queue/fabricq queue data collected
        set msg "**ERROR: $bundle_int Collection of ingress hardware ASIC allocation information FAILED. **"
        puts $FH $msg
        lappend flags $msg
      }

      ###############################################################
      # Step 7: Validate the ingress hardware programming information
      ###############################################################
      puts $FH "\n****Step 7: Validate the ingress hardware programming information"
      set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
      puts $FH "*Timestamp = $date"
      set step7 0

      set location_egress_count [array size location_egress_uidb]
      if {$location_egress_count == 1} {
        # Perform the verification on all locations with just one %location_egress_uidb/fabricq:
        foreach index [array names location_egress_uidb] {
          set egress_uidb_hex     [lindex [split $location_egress_uidb($index) :] 0]
          set egress_uidb_decimal [lindex [split $location_egress_uidb($index) :] 1]
          set egress_fabq_hex     [lindex [split $location_egress_fabricq($index) :] 0]
          set egress_fabq_decimal [lindex [split $location_egress_fabricq($index) :] 1]
          foreach location [split $bundle_member_locations2 " "] {
            set cmd "show cef mpls adj $bundle_int hardware ingress detail location $location | beg local"
            puts $FH $cmd
            if [catch {cli_exec $cli(fd) $cmd} result] {
              error $result $errorInfo
            }
            set retval $result
            set step7 [validate_ingress_hw $egress_uidb_hex $egress_fabq_decimal $retval]
          }
        }
      } elseif {$location_egress_count > 1} {
        # Perform the verification on all locations with all separate location_egress data:
        foreach location [array names location_egress_uidb] {
          set egress_uidb_hex     [lindex [split $location_egress_uidb($location) :] 0]
          set egress_uidb_decimal [lindex [split $location_egress_uidb($location) :] 1]
          set egress_fabq_hex     [lindex [split $location_egress_fabricq($location) :] 0]
          set egress_fabq_decimal [lindex [split $location_egress_fabricq($location) :] 1]

          set cmd "show cef mpls adj $bundle_int hardware ingress detail location $location | beg local"
          puts $FH $cmd
          if [catch {cli_exec $cli(fd) $cmd} result] {
            error $result $errorInfo
          }
          set retval $result
          set step7 [validate_ingress_hw $egress_uidb_hex $egress_fabq_decimal $retval]
        }
      } else {
        # Problem exists no location_egress data skipping step
        set msg "**ERROR: $bundle_int One of the egress hardware ASIC collections failed, skipping Step! **"
        puts $FH $msg
        lappend flags $msg
      }
      if {$step7 != 0} {
        # Problem encountered within Step 7
        set msg "**WARN: $bundle_int Validate ingress HW programming FAILED**"
        puts $FH $msg
        #lappend flags $msg
      } else {
        puts $FH "Validate ingress HW programming PASSED"
      }

      ###############################################################
      # Step 8: Collect the Egress hardware ASIC allocation information
      ###############################################################
      puts $FH "\n****Step 8: Collect the Egress hardware ASIC allocation information"
      set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
      puts $FH "*Timestamp = $date"

      foreach member [split $members2 " "] {
        set location [determine_xr_location2 $member]
        set cmd "show controllers $platform_mgr interface $member location $location"
        puts $FH $cmd
        if [catch {cli_exec $cli(fd) $cmd} result] {
          error $result $errorInfo
        }
        set retval $result
 
        lappend location_egressq($location) [egress_hardware_info $member $location $retval]

        if {$location_egressq($location) != ""} {
          set location_egressq($location) [lsort -unique -real $location_egressq($location)]
          set location_egressq_count [llength $location_egressq($location)]
          puts $FH "location_egressq($location): $location_egressq($location)"
        }
      }

      ###############################################################
      # Step 9: Validate L2 load balance hardware info
      ###############################################################
      puts $FH "\n****Step 9: Validate L2 load balance hardware info"
      set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
      puts $FH "*Timestamp = $date"
      set step9 0

      foreach location [split $bundle_member_locations2 " "] {
        set cmd "show cef ipv4 adjacency $bundle_int hardware egress detail location $location | beg local"
        puts $FH $cmd
        if [catch {cli_exec $cli(fd) $cmd} result] {
          error $result $errorInfo
        }
        set retval $result
        set step9 [validate_l2_hw_info $location $retval]

        if {$step9 != 0} {
          set msg "**WARN: $bundle_int Validate Egress L2 hardware info location: $location - FAILED **"
          puts $FH $msg
          #lappend flags $msg
        } else {
          puts $FH "Validate Egress L2 hardware info location: $location - PASSED"
        }
      }


  ###############################################################
  #  All Steps Completed
  ###############################################################
    } else {
      puts $FH "**WARN: Bundle $bundle_int has no members associated with it, skipping Bundle checks.**"
    }  ;# Close curly for checking to make certain the bundle members exist
  }  ;# Close curly for the foreach of bundles
}  ;# Close curly for checking for bundle interfaces exist
 
# Close CLI
cli_close $cli(fd) $cli(tty_id)
# End of Node Connection
###########################################
 
 
###########################################
# Check for flagged events:
puts $FH "\n=============Script Completed, Checking Flagged Events================"
if {[string length $flags]!=0} {
  # Issues/Flags found
  puts $FH "\n*******************************"
  puts $FH "Flagged event(s) found:"
  puts $FH "*******************************"
  set kont 0
  set flags_length [llength $flags]
  while {$kont < $flags_length} {
    set msg [lindex $flags $kont]
    puts $FH "FLAG $kont: $msg"
    incr kont
  }
  set msg "Cisco BCC checker failed for node. Login to node and view the eem_bcc.log for details"
  puts $FH $msg
  puts $msg

  # Send a syslog trap:
  action_syslog msg $msg
} else {
  # No issues/flags found
  puts $FH "Cisco BCC checker: No flags or errors encountered.  Node  **PASSED**"
  puts "Cisco BCC checker: No flags or errors encountered.  Node  **PASSED**"
}
set date [clock format [clock sec] -format "%T %Z %a %b %d %Y"]
puts $FH "*Timestamp = $date"
 
close $FH
################### End of Script ##########################################
