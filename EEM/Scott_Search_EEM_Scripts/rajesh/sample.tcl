::cisco::eem::event_register_syslog pattern "Configuration commit" maxrun 300

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

global FH
set ControllerOutput ""
set output ""
set kont 0

# Open router vty connection:
if [catch {cli_open} result] {
  error $result $errorInfo
} else {
  array set cli $result
}

# Gather configuration change
if [catch {cli_exec $cli(fd) "sh controller pse ingress stat location 0/3/cpu0 | in sanity_check"} result] {
  error $result $errorInfo
}
set ControllerOutput $result

# Close CLI
cli_close $cli(fd) $cli(tty_id)


foreach line [split $ControllerOutput "\n"] {
  if {$kont == 0} {
    # Meant to remove the first timestamp from the output
    set len [llength $line]
    set line [lreplace $line 0 $len]
  }
  # Remove the 'show controller' line:
  if {![regexp "^.*sh controll" $line]} {
    set l [llength $line]
    if {$l > 0 && ![regexp "^RP/" $line]} {
      lappend output $line
    }
  }
  incr kont
}
set ControllerOutput [join $output \n]


# Open the output file (for write):
if [catch {open disk1:/eem/output.log a} result] {
    error $result
}
set FH $result
puts $FH $ControllerOutput

close $FH
