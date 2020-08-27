for dev in $(find /sys/class/net -type l -not -lname '*virtual*' -printf '%f\n'); do
    /sbin/ifconfig "${dev}" mtu 1450
done

sysctl -w net.bridge.bridge-nf-call-iptables=1
