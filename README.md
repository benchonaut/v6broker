WIREGUARD-USERSPACE Setup (v6broker)

generates a config including /etc/rc.local.real start script
with wireguard-go (userspace )

* for using "cheap" ( e.g.  OVZ with tun but no modprobe / kernel module access )
* should even work in docker containers where the host already has wireguard but you need seperated stuff
* could be used to provide wireguard access to other containers


* uses NAT and private IPv6 if no public net was given
* uses private ipv4



