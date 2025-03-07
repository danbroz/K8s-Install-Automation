#!/usr/bin/env bash
#
# k8s-worker-laptop2.sh
# -----------------------------------------------------------------------------
# Installs containerd + Kubernetes on "laptop2" (192.168.0.102),
# automatically scps the join command from the master node, and
# executes it without manual token entry.
# -----------------------------------------------------------------------------

set -e

MASTER_IP="192.168.0.100"
MASTER_USER="dan"    # SSH user on the master
MASTER_HOST="${MASTER_USER}@${MASTER_IP}"

# ------------------------------------------------------------------------------
# Step 1: Enable IPv4 Packet Forwarding
# ------------------------------------------------------------------------------
echo "[Worker2] Step 1: Enabling IPv4 forwarding..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward=1
EOF
sudo sysctl --system

# ------------------------------------------------------------------------------
# Step 2: Disable swap
# ------------------------------------------------------------------------------
echo "[Worker2] Step 2: Disabling swap..."
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# ------------------------------------------------------------------------------
# Step 3: Install containerd (Ubuntu repos)
# ------------------------------------------------------------------------------
echo "[Worker2] Step 3: Installing containerd..."
sudo apt-get update
sudo apt-get install -y containerd

echo "[Worker2] Configuring containerd..."
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# ------------------------------------------------------------------------------
# Step 4: Install Kubernetes components
# ------------------------------------------------------------------------------
echo "[Worker2] Step 4: Installing kubeadm, kubelet, kubectl..."
sudo rm -f /etc/apt/sources.list.d/kubernetes.list

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /
EOF

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# ------------------------------------------------------------------------------
# Step 5: Automatically retrieve the join command from master, then run it
# ------------------------------------------------------------------------------
echo "[Worker2] Step 5: Retrieving /tmp/kubeadm_join_cmd.sh from master..."
scp -o StrictHostKeyChecking=no "${MASTER_HOST}:/tmp/kubeadm_join_cmd.sh" /tmp/

echo "[Worker2] Running join command..."
sudo bash /tmp/kubeadm_join_cmd.sh

echo "---------------------------------------------------"
echo "[Worker2] Worker joined the cluster successfully!"
echo "---------------------------------------------------"
