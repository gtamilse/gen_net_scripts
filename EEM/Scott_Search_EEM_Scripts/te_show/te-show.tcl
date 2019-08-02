::cisco::eem::event_register_timer cron name te-show cron_entry "0,5,10,15,20,25,30,35,40,45,50,55 * * * *" maxrun_sec 240
# BEGINNING OF COMMENTS
# MPLS-TE Statistics Cron Job Script - Tom Scholl - 03/05/10 - v1.0
#  - Al Goddard - 10/02/10 - v1.1 - re-certify on 3.8/4.0
#  - Al Goddard - 10/04/10 - v2.0 - removed timestamping, added file append
#  - Al Goddard - 10/05/10 - v2.1 - removed file append for 3.8 compatibility
#  - Al Goddard - 10/06/10 - v2.2 - fix for file not appending newline
#
# Special thanks to Scott Search of Cisco (ssearch@cisco.com) for:
# -Code to check file sizes
# -Commands on how to load env variables and the tcl script into the router
# -Having to deal with me
#
# See the MaxFileSize variable within this script to define maximum TE dump file log size.
# Things to do in order to make this work:
#
# Apply Event Manager Related Commands:
#
#    event manager directory user policy harddisk:/eem
#    event manager policy te-show.tcl username te-script type user
# 
# Set these environment variables:
#
#    event manager environment _show_te_cmd show mpls traffic-eng tunnel detail
#    event manager environment _te_log_file harddisk:/te-log.txt
#    event manager environment _te_log_tmp_file harddisk:/te-log-tmp.txt
#
# AAA / Username commands to be added:
#
#    aaa authorization eventmanager default local
#    username te-script
#     group teamops
#
# How to implement this script:
# 1) Execute "mkdir harddisk:eem" -OR- Create it via the IOS-XR shell
# 2) Copy this script into the directory via shell or copy services (TFTP, FTP, etc)
# 3) Paste the above IOS-XR commands into the configuration and commit.
# 4a) Perform the same operation in the redundant RP.
# 4b) Run "show red" to find out the other RP
# 4c) cd into /net/Redundany-RP-Location/harddisk: and mkdir the eem directory
# 4d) Place the script in that directory.
# 5) Done
#
# END OF COMMENTS

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

array set arr_einfo [event_reqinfo]

set MaxFileSize 10000000
set FileSize 0
set FileName [lindex [split $_te_log_file /] end]

if {![info exists _show_te_cmd]} {
	set result "Policy cannot be run: variable _show_te_cmd has not been set"
	error $result $errorInfo
}

if [catch {cli_open} result] {
	error $result $errorInfo
} else {
	array set cli $result
}

if [catch {cli_exec $cli(fd) "dir $_te_log_file"} result] {
	error $result $errorInfo
}

set dirOutput $result

foreach line [split $dirOutput "\n"] {
	regsub -all {[ \r\t\n]+} $line " " line
	if { [regexp -- {^\d+} $line] && [regexp "$FileName$" $line] } {
		set FileSize [ lindex [split $line " "] 2 ]
	}
}


# save exact execution time for command
set time_now [clock seconds]
set time_now [clock format $time_now -format "%b-%d-%H%M"]

if {$FileSize > $MaxFileSize} {
	if [catch {cli_exec $cli(fd) "run mv /$_te_log_file /${_te_log_file}.$time_now"} result] {
		error $result $errorInfo
	} 
}

# if _te_log_file is defined, then attach it to the file
# if {[info exists _te_log_tmp_file]} {
	# attach output to file
	# if [catch {open $_te_log_tmp_file a+} result] {
		# error $result
	# }
	# set fileD $result
	# set time_now [clock format $time_now -format "%T %Z %a %b %d %Y"]
	# puts $fileD "%%% Timestamp = $time_now"
	# close $fileD
# }


# execute command
if [catch {cli_exec $cli(fd) "$_show_te_cmd | file $_te_log_tmp_file"} result] {
	error $result $errorInfo
} 

if [catch {cli_exec $cli(fd) "run echo >> /$_te_log_file"} result] {
	error $result $errorInfo
} 

if [catch {cli_exec $cli(fd) "run cat /$_te_log_tmp_file >> /$_te_log_file"} result] {
	error $result $errorInfo
} 

if [catch {cli_exec $cli(fd) "run rm /$_te_log_tmp_file"} result] {
	error $result $errorInfo
} 
