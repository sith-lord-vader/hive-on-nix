# Apache Hive on Nix

What it says on the tin. 

# WIP.

Current primary reason for existence of this repo is as a testing environment.

# To run tests


```sh
nix build .\#checks.x86_64-linux.<testname>.driverInteractive 
```
or
```
nix-build ./<testname> -A driverInteractive
```
