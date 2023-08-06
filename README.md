# mod-shell
A Modular Shell. ModSh is designed to allow users to build custom Shells of varying sizes and complexities. This is accomplished by taking advantage of the Zig Build System and Zig's Comptime code paradigm.

## Try it out
1. Download
```shell
https://github.com/00JCIV00/mod-shell.git
cd mod-shell
```
2. Build 
```shell
zig build shell -Dshell_builtins=Basic -Dshell_prefix_kind=Text -Dshell_prefix=modsh -freference-trace -Drelease=true
```
3. Run
```shell
./bin/modsh
```

## Options
Run `zig build -h` and look at the "Project-Specific Options" section to see customization options.
