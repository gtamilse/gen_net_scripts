#!/usr/bin/python

# script is used to extract node IPs from nova list openstack command
#
# command: nova list --all-tenants | grep ACTIVE
#
# Output example below
#
# virl@virl:~/Ansible-Lab-Management$ nova list --all-tenants | grep ACTIVE
# | d9d01bbf-c9ce-400e-9609-bc956188b48a | </guest/endpoint>-<ansible-2r-topo.2019-01-03-5Uuzzl>-<R1-CSR1K>           | 3c6aa34303ed4f02a1eb01bbe8f77740 | ACTIVE | -          | Running     | flat=172.16.101.195; </guest/endpoint>-<ansible-2r-topo.2019-01-03-5Uuzzl>-<R1-CSR1K-to-R2-XRv>=10.255.255.1                                                                                                                                                                                                                                                                                                                                                                  |
# | 74c0ef28-99ac-42ac-bb49-dfa84c327f6f | </guest/endpoint>-<ansible-2r-topo.2019-01-03-5Uuzzl>-<R2-XRv>             | 3c6aa34303ed4f02a1eb01bbe8f77740 | ACTIVE | -          | Running     | flat=172.16.101.196; </guest/endpoint>-<ansible-2r-topo.2019-01-03-5Uuzzl>-<R1-CSR1K-to-R2-XRv>=10.255.255.2                                                                                                                                                                                                                                                                                                                                                                  |
# | 658c960b-f242-4cac-a154-d28bb8942765 | </guest/endpoint>-<ansible-2r-topo.2019-01-03-5Uuzzl>-<ansible-controller> | 3c6aa34303ed4f02a1eb01bbe8f77740 | ACTIVE | -          | Running     | flat=172.16.101.197                                                                                                                                                                                                          
#
# Output of this script will help create ansible inventory files


import subprocess
import time

container = {}
TIMESTAMP = time.strftime("%Y-%m-%d_%H:%M:%S")

novalist = subprocess.Popen("nova list --all-tenants | grep ACTIVE", shell=True, stdout=subprocess.PIPE,)
instancelist = novalist.communicate()[0].split('\n')

counter = 0

for line in instancelist:
    fields = line.split("|")
    if len(fields) > 1:
    #print(fields[2])
        simid = fields[2].split(">-<")[1].split("-")[-1].strip()
        nodeid = fields[2].split(">-<")[2].split(">")[0].strip()
        ipaddr = ""
        if "flat" in fields[7]:
          ipaddr = fields[7].split("lat=")[1].split(";")[0].strip()
          #print(simid + " - " + nodeid + " - "  + ipaddr)
        if simid in container.keys():
            container[simid][nodeid] = ipaddr
        else:
            container[simid] = {nodeid: ipaddr}

#print(container)

simids = container.keys()
simids.sort()

controllers = []
ios_rtr = []
xr_rtr = []
xr_expect = []
pod = 1

#print("{: <10} {: <20} {: <20} {: <20}".format(["Insance", "Ansible-Controller", "R1-CSR1K", "R2-XRv"]))
print("Insance, Ansible-Controller, R1-CSR1K, R2-XRv")
for simid in simids:
    if "ansible-controller" in container[simid].keys():
        print (simid + ", " + container[simid]['ansible-controller'] + ", " + container[simid]['R1-CSR1K'] + ", " + container[simid]['R2-XRv'])
        controllers.append("Pod" + str(pod) + " ansible_host=" + container[simid]['ansible-controller'])
        ios_rtr.append("P" + str(pod) + "R1 ansible_host=" + container[simid]['R1-CSR1K'])
        xr_rtr.append("P" + str(pod) + "R2 ansible_host=" + container[simid]['R2-XRv'])
        xr_expect.append("Pod" + str(pod) + "-XR " + container[simid]['R2-XRv'])
        pod += 1

print("\n\n[controllers]")
for line in controllers:
    print(line)
print("\n\n[IOS-RTR]")
for line in ios_rtr:
    print(line)
print("\n\n[XR-RTR]")
for line in xr_rtr:
    print(line)
print("\n\nExpect file:")
for line in xr_expect:
    print(line)

