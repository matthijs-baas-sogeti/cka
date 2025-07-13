# prep VM with basics
sudo echo 'matt ALL=(ALL:ALL) ALL' | sudo tee /etc/sudoers.d/matt
sudo usermod -aG sudo matt
sudo chmod 0440 /etc/sudoers.d/matt

# add ssh key
sudo echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCzzTtECT9OHdQr/sYKOomho9152Jan/+PHtghsvlo5bdDi0owK24eTWtj8JbYVfDidQyJ7+gD2LdzaCO9jMegviLZPoevb1tyVcn+itslSTzJJPy6DCokbny8PXuX3B3DCvDgLzgmESrhSYY8D6S+8pMNbNvDusmsPSnHY0608VWyqC5z95ROCWSe3wk7CMkd4MRuPV6eqWXL9PKffExKCTYP2I3A4f62ovHYCzxJdbh9qyuLv9ZmZ68ewIi5pJ4UqP+DBTH1CpL77TVSPpQD5rJYjD/HLRNHfuMnTgeB3I2APjfAZ7C3qznhrIAWEs9M1IC8x0XkTb3ZC3b0PWdVjUtURVOUp/5ayTBLRz0Gd08r1vXGDqaz7Ttg6MaDH4L07kkln/ylvXZMrGkV2zeV/HQjmER1/XAhraVsRHH+DcE6nSIBn75K9KzrR5LV1Eivexnb0t6ufzptni2Ql5NmJsV4ditdHlxfY4/z0IrFU1vt1bUaZZC35U6N7rAZDjv0= mattlpt@mattlpt'  | sudo tee -a /home/matt/.ssh/authorized_keys

# update
sudo apt update && apt upgrade -y
sudo apt autoremove -y

# Run on all the nodes for IPtables to see bridged traffic
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

# For kubeadm to work properly, disable swap ( on root user! as it requires root to turn it off )
# manual: crontab -e > @reboot swapoff -a
sudo swapoff -a
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

# Kuernetes Variable Declaration
KUBERNETES_VERSION=v1.32
CRIO_VERSION=v1.32

# Apply sysctl params without reboot
sudo sysctl --system

## Install CRIO Runtime by first installing packages needed to download and get a gpgkey
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gpg software-properties-common

curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/stable:/$CRIO_VERSION/deb/ /" |
    tee /etc/apt/sources.list.d/cri-o.list

sudo apt-get update -y
sudo apt-get install -y cri-o

sudo systemctl daemon-reload
sudo systemctl enable crio --now
sudo systemctl start crio.service

echo "CRI runtime installed susccessfully"

# download keyring for kubernetes
curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key |
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" |
    tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y

# download kubelet, kubectl and kubeadm
# tip: find current versions, apt-cache madison kubeadm | tac
KUBERNETES_INSTALL_VERSION=1.32.5-1.1

sudo apt-get install -y kubelet="$KUBERNETES_INSTALL_VERSION" kubectl="$KUBERNETES_INSTALL_VERSION" kubeadm="$KUBERNETES_INSTALL_VERSION"


# add node IP to KUBELET_EXTRA_ARGS
sudo apt-get install -y jq

local_ip="$(ip --json addr show eth0 | jq -r '.[0].addr_info[] | select(.family == "inet") | .local')"

cat > /etc/default/kubelet << EOF

KUBELET_EXTRA_ARGS=--node-ip=$local_ip

EOF
