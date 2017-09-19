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