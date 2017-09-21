# TODO: Verification

- [ ] Check running on an empty cluster
- [ ] Run on a cluster with 1 HANA pair
- [ ] Run on a cluster with 2+ HANA pairs

# TODO: Improvements

- [ ] Refactor the package:
    + the client should consist of a couple of lines: import and execute .main on the class
    + remove the outer Yast module enclosure
- [ ] Distinguish between ncurses and GUI: ncurses renders the `<style>` section (shame!)
- [ ] Don't forget to unmount the share!
- [ ] Update copyrights and file descriptions
- [ ] Rework NodeLogger
- [ ] Check remote node's update plan.



2017-09-19 18:09:45 <2> hana02(10150) [Ruby] hana_update/executor.rb:104 --- Registering local HANA instance for SR ---
2017-09-19 18:09:45 <0> hana02(10150) [Ruby] binary/Yast.cc(ycp_module_call_ycp_function):282 Dynamic Proxy: [UI::BusyCursor] with [4] params
2017-09-19 18:09:45 <0> hana02(10150) [Ruby] binary/Yast.cc(ycp_module_call_ycp_function):291 Namespace created from UI
2017-09-19 18:09:45 <0> hana02(10150) [Ruby] binary/Yast.cc(ycp_module_call_ycp_function):326 Call BusyCursor
2017-09-19 18:09:45 <0> hana02(10150) [Ruby] binary/Yast.cc(ycp_module_call_ycp_function):282 Dynamic Proxy: [UI::OpenDialog] with [6] params
2017-09-19 18:09:45 <0> hana02(10150) [Ruby] binary/Yast.cc(ycp_module_call_ycp_function):291 Namespace created from UI
2017-09-19 18:09:45 <0> hana02(10150) [Ruby] binary/Yast.cc(ycp_module_call_ycp_function):326 Call OpenDialog
2017-09-19 18:09:45 <0> hana02(10150) [Ruby] binary/Yast.cc(ycp_module_call_ycp_function):332 Append parameter `opt (`decorated)
2017-09-19 18:09:45 <0> hana02(10150) [Ruby] binary/Yast.cc(ycp_module_call_ycp_function):332 Append parameter `HBox (`HSpacing (1), `VBox (`VSpacing (0.2), `VBox (`VSpacing (0.4), `VBox (`Left (`Heading ("Please wait")), `VSpacing (0.2), `Left (`Label ("Registering local HANA instance for SR")), `VSpacing (0.2), `Empty ())), `VStretch (), `Empty (), `VStretch (), `VSpacing (0.2)), `HSpacing (1))
2017-09-19 18:09:45 <1> hana02(10150) [Ruby] hana_update/hana.rb:180 --- called HANAUpdater::HanaClass.enable_secondary(PRD, PRAGUE, hana01, 00, sync, delta_datashipping) ---
2017-09-19 18:09:45 <1> hana02(10150) [Ruby] hana_update/hana.rb:89 --- called HANAUpdater::HanaClass.version(PRD) ---
2017-09-19 18:09:45 <1> hana02(10150) [Ruby] hana_update/shell_commands.rb:87 Executing ["HDB", "version"] as user prdadm
2017-09-19 18:09:46 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT: HDB version info:
2017-09-19 18:09:46 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT:   version:             2.00.010.00.1491294693
2017-09-19 18:09:46 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT:   branch:              fa/hana2sp01
2017-09-19 18:09:46 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT:   git hash:            b894936912f4caf63f40c33746bc63102cdb3ff3
2017-09-19 18:09:46 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT:   git merge time:      2017-04-04 10:31:33
2017-09-19 18:09:46 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT:   weekstone:           0000.00.0
2017-09-19 18:09:46 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT:   compile date:        2017-04-04 10:37:36
2017-09-19 18:09:46 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT:   compile host:        ld7270
2017-09-19 18:09:46 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT:   compile type:        rel
2017-09-19 18:09:46 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:90 --- called HANAUpdater::HanaClass.su_exec_outerr_status: command returned 'pid 27672 exit 0' ---
2017-09-19 18:09:46 <1> hana02(10150) [Ruby] hana_update/shell_commands.rb:87 Executing ["hdbnsutil", "-sr_register", "--remoteHost=hana01", "--remoteInstance=00", "--mode=sync", "--name=PRAGUE"] as user prdadm
2017-09-19 18:09:47 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT: adding site ...
2017-09-19 18:09:47 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT: WARNING: Deprecated option --mode. Please use --replicationMode instead.
2017-09-19 18:09:47 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT: --operationMode not set; using default from global.ini/[system_replication]/operation_mode: delta_datashipping
2017-09-19 18:09:47 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT: checking for inactive nameserver ...
2017-09-19 18:09:47 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT: nameserver hana02:30001 not responding.
2017-09-19 18:09:47 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT: collecting information ...
2017-09-19 18:09:47 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT: unable to contact primary site host hana01:40002. internal error,location=hana01:40002. Trying old-style port (port offset +100)...hana01:30102
2017-09-19 18:09:47 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT: updating local ini files ...
2017-09-19 18:09:47 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:89 --- OUT: done.
2017-09-19 18:09:47 <0> hana02(10150) [Ruby] hana_update/shell_commands.rb:90 --- called HANAUpdater::HanaClass.su_exec_outerr_status: command returned 'pid 27763 exit 0' ---
