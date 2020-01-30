# **<p align="center">SDWAN CLI CAPTURE SCRIPT</p>**

 **<p align="center">Created by: Gowtham Tamilselvan </p>**
 **<p align="center">Date: June 10 2020</p>**
  **<p align="center">Cisco Systems Inc / SDWAN SRE Team </p>**

 
 # 1. Introduction
 
 This tool was created to assist in cli data collection from sdwan devices (vcontroller or vedges). 
 
 This tool provides 3 main functions:
 - Ad-hoc cli data collection
 - Precheck and postcheck data collection (for Maintainence/change windows) 
 - Diff comparison between the precheck and postcheck data

The entire data collection (adhoc/pre/post) functionality is handled by the sdwan_cli_captures.yml ansible playbook file.

The difference comparison functionality is handled by the sdwan_pre_post_diff.yml ansible playbook file.

 # 2. Data Collection - sdwan_cli_captures.yml

 ```
SDWAN CLI CAPTURE PLAYBOOK

 Created by: Gowtham Tamilselvan
 Revision Number: 1.8
 Last Updated: Jan 30 2019
 Cisco Systems, Inc./Sdwan SRE TEAM

 Cisco Product tested 			: vedge cloud, vmanage, vbond, vsmart
 Cisco IOS XR Software Version tested  : 19.2.099
 
 Playbook Requirements:
   1: Jinja2 template files called 'sdwan_cli_capture_template.j2', 'sdwan_cli_precheck_template.j2', 'sdwan_cli_postcheck_template.j2'
        Example: cat sdwan_cli_capture_template.j2
             {% for n in n %}
             === {{ inventory_hostname }}: {{ clicmds[n] }} ===
             {{ captures.results[n].stdout[0] }}
             {% endfor %}

   2: List of cli commands in txt file (file name does not matter) 
        Recommend to use the "| nomore" option with the CLI commands
        Example: 
             show system status | nomore
             show interface | nomore

   3: Ansible inventory/hosts file defined with hostnames (not just IPs)
        Example: 
             [edges]
             vEdge1 ansible_host=10.10.10.11 ansible_user=admin ansible_ssh_pass=admin ansible_network_os=ios


 Playbook Summary:
   1: Playbook can be used for adhoc data collection, by simiply providing a command file and defining the host
       a: Run script in adhoc mode by specifying the following parameters
             --tags collect
             -e "variable_host=<inventory_host/group_name>"
             -e "cmds_file=<cli_cmds_file.txt>" 
  
          - Example: ansible-playbook sdwan_cli_capture_v4.yml --tags collect -e "variable_host=vEdge1" -e "cmds_file=sdwan_cli_cmds2.txt"

          - All output logs are stored in the /tmp/ansible_logs/ directory on the local host

   2: Playbook can be used for Pre and Post Capture Analysis during Maintenance windows 
       a: Run the precheck option before the window starts by specifying the following parameters
             --tags precheck
             -e "variable_host=<inventory_host/group_name>"
             -e "cmds_file=<cli_cmds_file.txt>" 
  
          - Example: ansible-playbook sdwan_cli_capture_v4.yml --tags precheck -e "variable_host=vEdge1" -e "cmds_file=sdwan_cli_cmds2.txt"

          - All output logs are stored in the /tmp/ansible_logs/ directory on the local host

       b: Then run the postcheck option after the window by specifying the following parameters
             --tags postcheck
             -e "variable_host=<inventory_host/group_name>"
             -e "cmds_file=<cli_cmds_file.txt>" 
  
          - Example: ansible-playbook sdwan_cli_capture_v4.yml --tags postcheck -e "variable_host=vEdge1" -e "cmds_file=sdwan_cli_cmds2.txt"

          - All output logs are stored in the /tmp/ansible_logs/ directory on the local host

       c: Once the postcheck collection has completed, run the sdwan_pre_post_diff.yaml playbook to perform the diff comparison.
 
 ```

 # 3. Data comparison - sdwan_pre_post_diff.yml

 ```
Playbook Requirements:
   1: Requires the precheck captures file and the postcheck captures file. User will be prompted to input the following values:
       a: User needs to provide the full Path where both files are located. Both files need to be in the same location! The final / slash is needed!

             prompt: Provide path the precheck and postcheck files, both need to be in same dir (ex - /home/cisco/): 

          - Example: Provide path the precheck and postcheck files, both need to be in same dir (ex - /home/cisco/): /tmp/ansible_logs/sdwan_captures_2020-01-23/

       b: User needs to provide the exact name of the precheck file.

             prompt: Provide the exact  name of precheck file (ex - /home/cisco/vedge1_Precheck.txt)

          - Example: Provide the exact name of precheck file (ex - /home/cisco/vedge1_Precheck.txt):  vEdge3_Precheck_2020-01-23-15-44.txt

      c: User needs to provide the exact name of the postcheck file.

             prompt: Provide the exact name of postcheck file (ex - /home/cisco/vedge1_Postcheck.txt)

          - Example: Provide the exact name of postcheck file (ex - /home/cisco/vedge1_Postcheck.txt): vEdge3_Postcheck_2020-01-23-15-44.txt

      d: User needs to provide a value or name that can be used as part of the output file name. This is just to make it easy to identify the output file.

             prompt: Provide a value or name that will be used as part of the output file name, no spaces (ex - Full_collection)

          - Example: Provide a value or name that will be used as part of the output file name, no spaces (ex - Full_collection) Full_collection

          - All output logs are stored in the /tmp/ansible_logs/ directory on the local host

   2: Playbook also requires the python script diff_cleanup.py to be located inside the lib dir. 
      a: You do not need to make any changes to this python script or call it manually! This script is integrated into the sdwan_pre_post_diff.yaml playbook.

 ```
