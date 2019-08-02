::cisco::eem::event_register_syslog occurs 1 pattern $_syslog_pattern maxrun 90

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*
 
set errorInfo ""
 
# 1. query the information of latest triggered fm event
array set arr_einfo [event_reqinfo]
 
if {$_cerrno != 0} {
    set result [format "component=%s; subsys err=%s; posix err=%s;\n%s" \
        $_cerr_sub_num $_cerr_sub_err $_cerr_posix_err $_cerr_str]
    error $result 
}
 
set msg $arr_einfo(msg)
set config_cmds ""
 
# 2. execute the user-defined config commands
if [catch {cli_open} result] {
    error $result $errorInfo
} else {
    array set cli1 $result
} 

if [catch {cli_exec $cli1(fd) "config"} result] {
    error $result $errorInfo
} 
 
if {[info exists _config_cmd1]} {
    if [catch {cli_exec $cli1(fd) $_config_cmd1} result] {
        error $result $errorInfo
    }
 
    append config_cmds $_config_cmd1
}
 
if {[info exists _config_cmd2]} {
    if [catch {cli_exec $cli1(fd) $_config_cmd2} result] {
        error $result $errorInfo
    } 
    append config_cmds "\n"
    append config_cmds $_config_cmd2
}
 
if [catch {cli_exec $cli1(fd) "end"} result] {
    error $result $errorInfo
} 
if [catch {cli_close $cli1(fd) $cli1(tty_id)} result] {
    error $result $errorInfo
} 
 
action_syslog priority info msg "Ran config command $_config_cmd1 $_config_cmd2
