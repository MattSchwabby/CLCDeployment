# CLCDeployment

PowerShell script to create multiple CenturyLink Cloud Servers and stagger their creation to batches of 5 servers at a time.

Author: Matt Schwabenbauer

Date: July 19, 2016

Matt.Schwabenbauer@ctl.io

### About this script

This script will monitor the status of VM creation requests and will automatically submit a new request if a server build fails
The operation will also monitor the number of available IP addresses for the specified network. A new network will be claimed if
available IP addresses fall to zero.

### Running the script

To run, execute the .ps1 file by right-clicking and selecting run in PowerShell, or open it in the PowerShell ISE and click the
play button (or, press f8 when the script is open in the ISE).

The user will be prompted to enter an API V1 Key, an API V1 password, as well as their control portal credentials (for API V2).

They will then be prompted for the sub account to create the servers in, as well as data center, desired server template to use,
server group to create the VMs in, which network to use, amount of RAM and CPU to assign to each server, as well as a name to use
for the Virtual Machines.

The operation will commence once all data is collected from the user. Status will be displayed in the PowerShell console, as well as
logged at C:\Users\Public\CLC. A spreadsheet containing information for each of the Virtual Machines will also be exported to the same
file path.

### Support

This script is presented as is and is open to contribution from the community.

Feature requests and enhancements can be suggested to Matt.Schwabenbauer@ctl.io. Any future development is not guaranteed.