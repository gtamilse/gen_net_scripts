#/usr/bin/python3

###############################################################################
# Diff Cleanup script is integrated with the sdwan_pre_post_diff playbook.
#
# Created by Gowtham Tamilselvan
# Last Updated: Jan 30,2020
# Cisco Systems, Inc./SDWAN SRE TEAM
#
# This python script is used to futher clean up the diff file to make it more user friendly.
#
# There is no need to run this script independently!
#
###############################################################################

from sys import argv
from collections import OrderedDict

def readfile(filename):
    print('Reading file "' + filename + '"')
    try:
        with open(filename, 'r') as filehandler:
            lines = filehandler.readlines()
            #for line in diff_file:
            #    listoflines.append(line.strip())
    except IOError as error:
        print('Unable to open file ' + filename  + 'for reading, exiting.')
        quit()
    return lines

def writefile(filename):
    print('Writing file "' + filename + '"')
    try:
        with open(filename, 'w') as data:
            data.writelines( diff_dup_removed )
            #for line in diff_file:
            #    listoflines.append(line.strip())
    except IOError as error:
        print('Unable to open file ' + filename  + 'for reading, exiting.')
        quit()


##### MAIN #####

script, filename = argv

diffdata = readfile(filename)

newdiff = []

# Loop through the file and remove any lines that only contain the precheck and postcheck command cli without any actual cli output
# Compare first line with thrid line and if they are both prechecks or postcheck command line and not outputs then empty the current line (first line)

for line in diffdata:
    for i in range(len(diffdata)):
        if i + 2 < len(diffdata):
            if (diffdata[i].startswith('< === ') & diffdata[i+2].startswith('< ===')) | (diffdata[i].startswith('> === ') & diffdata[i+2].startswith('> ===')):
                diffdata[i] = ''
            else:
                newdiff.append(diffdata[i])
            
        else:
            break

# Remove duplicate items from newdiff, to reduce size to just the diff items
diff_dup_removed = list(OrderedDict.fromkeys(newdiff))

# Overwrite the initial file with new diff data
writefile(filename)
