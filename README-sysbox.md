# 1. Install sysbox
1. `wget https://downloads.nestybox.com/sysbox/releases/v0.6.5/sysbox-ce_0.6.5-0.linux_amd64.deb`
2. `sudo apt-get install ./sysbox-ce_0.6.5-0.linux_amd64.deb -y`

# 2. Stop and remove all containers
`docker rm $(docker ps -a -q) -f`

# 3. Restart Docker so it’s clean
`sudo systemctl restart docker`

# 4. Reconfigure the Sysbox package
`sudo dpkg --configure -a`

# 5. Verify installation
`docker info | grep Runtimes`

You should see: sysbox-runc