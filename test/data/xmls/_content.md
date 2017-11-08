# Test XML configuration files

Files obtained from a real cluster setup, having configuration errors as described below.

- `*.mon.xml` obtained via `crm_mon -r --as-xml`,
- `*.cib.xml` obtained via `cibadmin -Q -l`

General paramters:
System: PRD/00
Nodes: plain1, plain2

# Description

## test00

- Empty cluster, no resources

## test01

- Both SAPHana and SAPHanaTopology failed
- No vIP resource and no colocation rule

## test02

- Both SAPHana and SAPHanaTopology failed
- vIP is running
- No colocation rule


## test03

- No SAPHanaTopology agent configured


## test04

- No SAPHana M/S resource, no constraints

## test05

- System QAS/11 is configured
- System PRD:
	- No SAPHana resource and no constraints

## test06

- System QAS/11 configured, but is missing the SAPHanaTopology
- System PRD/00 is configured

## test07

- System QAS/11 configured, but is missing the SAPHanaTopology
- System PRD/00 is configured, but is missing the vIP constraint

- EXPECTATION: no systems

## test10

- Healthy system
- PRD/00
- All resources are managed and running

## test11

- Healthy system PRD/00
- SAPHanaTopology is stopped