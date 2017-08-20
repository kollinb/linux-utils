#!/bin/bash

#TUN/TAP must be enabled in order for openvpn to work on CentOS6-OpenVZ
tungood="File descriptor in bad state"
if cat /dev/net/tun |& grep -q "$tungood"; then
    echo "TUN/TAP device enabled"
else
    echo "Enable TUN/TAP on your sever before running this script"
    exit 1
fi

#Update yum repository and add epel-repo for openvpn and easy-rsa
yum update
yum install epel-release

#Portforwarding must be enabled in order for routing to work correctly
portforwarding=$(cat /proc/sys/net/ipv4/ip_forward)
if [ "$portforwarding" = "0" ]; then
    echo "Portforwarding not enabled, attemping to enable."
    if [ -e "/etc/sysctl.conf" ]; then
        if sed -i '/net.ipv4.ip_forward = 0/c\net.ipv4.ip_forward = 1' /etc/sysctl.conf; then
            sysctl -p
            echo "Ignore key errors not pertaining to net.ipv4.ip_forward."
            echo "Successfully enabled portforwading."
        else
            echo "Failed to enable portforwading."
            echo "Please change /etc/sysctl.conf net.ipv4.ip_forward to 1"
            echo "and restart this script."
            exit 2
        fi
    else
        echo "Failed to find /etc/sysctl.conf file"
        exit 3
    fi
elif [ "$portforwarding" = "1" ]; then
    echo "Portforwarding enabled"
else
    echo "Unknown value for /etc/sysctl.conf net.ipv4.ip_forward"
    exit 4
fi

#Install openvpn and easy-rsa
yum install openvpn easy-rsa
mkdir /etc/openvpn/easy-rsa
cp -r /usr/share/easy-rsa/2.*/* /etc/openvpn/easy-rsa

#Move all premade config files
rm /etc/openvpn/easy-rsa/vars
mv ./files/vars /etc/openvpn/easy-rsa/vars
mv ./files/server.conf /etc/openvpn/server.conf

#Server key generation and configuration
cd /etc/openvpn/easy-rsa
source vars
./clean-all
echo "Running certificate build script"
sh ./build-ca
echo "Running key server build script"
sh ./build-key-server PokeBotVPN
echo "Running Diffie Hellman build script"
./build-dh
cd keys
cp PokeBotVPN.crt PokeBotVPN.key ca.crt dh2048.pem /etc/openvpn


#Client key generation
cd /etc/openvpn/easy-rsa
source vars
echo "Running client key build script"
./build-key client1


#Firewall (specifically iptables) configuration
echo "**WARNING** : Flushing iptable rules"
iptables -F
iptables -A INPUT -i venet0 -m state --state NEW -p udp --dport 1194 -j ACCEPT
iptables -A INPUT -i tun+ -j ACCEPT
iptables -A FORWARD -i tun+ -j ACCEPT
iptables -A FORWARD -i tun+ -o venet0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i venet0 -o tun+ -m state --state RELATED,ESTABLISHED -j ACCEPT
echo "Please enter the external IP Adress of your server"
read externalip
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to-source $externalip
iptables -A OUTPUT -o tun+ -j ACCEPT

#Save iptables for persistancy and restart services
/sbin/service iptables save
service iptables restart
service network restart

iptables -S
echo "iptable rules should display above this message"

#Start openvpn service
service openvpn start
echo "Openvpn should be up and running"
echo "Download client key files over sftp and connect"
echo "etc/openvpn/easy-rsa/keys client1.key client1.crt ca.crt"
