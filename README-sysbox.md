# 1. Stop and remove all containers
`docker rm $(docker ps -a -q) -f`

# 2. Download and install Sysbox v0.6.6
1. `wget https://downloads.nestybox.com/sysbox/releases/v0.6.6/sysbox-ce_0.6.6-0.linux_amd64.deb`
2. `sudo apt-get install ./sysbox-ce_0.6.6-0.linux_amd64.deb -y`

# 3. Restart Docker
`sudo systemctl restart docker`

# 4. Reconfigure the Sysbox package
`sudo dpkg --configure -a`

# 5. Verify upgrade
`sysbox-runc --version`

You should see: `version: 0.6.6`

`docker info | grep Runtimes`

You should see: `sysbox-runc`