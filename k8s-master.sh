#!/usr/bin/env bash
#
# k8s-master.sh
# -----------------------------------------------------------------------------
# Installs a Kubernetes control-plane on Ubuntu 24.04 ("noble") using Ubuntu’s
# default containerd package and the official Kubernetes repository from pkgs.k8s.io.
#
# If a cluster already exists on this machine, it will skip kubeadm init.
# Otherwise, it initializes a fresh cluster, sets up Weave Net, then creates
# a join command and copies it to the worker nodes for automatic joining.
#
# Adjust "dan@192.168.0.101" and "dan@192.168.0.102" for your worker nodes.
# -----------------------------------------------------------------------------

set -e  # Exit on any command failure

MASTER_IP="192.168.0.100"
WORKER1="dan@192.168.0.101"
WORKER2="dan@192.168.0.102"

# ------------------------------------------------------------------------------
# Step 1: Enable IPv4 Packet Forwarding
# ------------------------------------------------------------------------------
echo "[Master] Step 1: Enabling IPv4 forwarding..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward=1
EOF
sudo sysctl --system

# ------------------------------------------------------------------------------
# Step 2: Disable swap
# ------------------------------------------------------------------------------
echo "[Master] Step 2: Disabling swap..."
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

# ------------------------------------------------------------------------------
# Step 3: Install containerd from Ubuntu repos
# ------------------------------------------------------------------------------
echo "[Master] Step 3: Installing containerd..."
sudo apt-get update
sudo apt-get install -y containerd

echo "Configuring containerd..."
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# ------------------------------------------------------------------------------
# Step 4: Install Kubernetes Components (kubeadm, kubelet, kubectl)
# ------------------------------------------------------------------------------
echo "[Master] Step 4: Installing kubeadm, kubelet, kubectl..."
# Remove or fix old/broken kubernetes.list
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
# Step 5: Initialize Kubernetes Control Plane (only if no existing cluster)
# ------------------------------------------------------------------------------
if [ ! -f /etc/kubernetes/manifests/kube-apiserver.yaml ]; then
  echo "[Master] Step 5: Initializing Kubernetes cluster..."

  cat <<EOF | sudo tee kubeadm-config.yaml
kind: ClusterConfiguration
apiVersion: kubeadm.k8s.io/v1beta4
kubernetesVersion: v1.31.1
networking:
  podSubnet: 10.10.0.0/16
controlPlaneEndpoint: "${MASTER_IP}:6443"
---
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
cgroupDriver: systemd
EOF

  sudo kubeadm init --config kubeadm-config.yaml

  # Copy kubeconfig to regular user
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

  # ----------------------------------------------------------------------------
  # Step 6: Install Weave Net for Pod Networking
  # ----------------------------------------------------------------------------
  echo "[Master] Step 6: Installing Weave Net..."
  curl -fsSL https://reweave.azurewebsites.net/k8s/v1.31/net.yaml \
    -o weave-net.yaml

  # Example: uncomment & set the IPALLOC_RANGE in weave-net
  sed -i 's|# - name: IPALLOC_RANGE|- name: IPALLOC_RANGE|' weave-net.yaml
  sed -i 's|#   value: 10.32.0.0/12|  value: 10.10.0.0/16|' weave-net.yaml

  kubectl apply -f weave-net.yaml

  echo "[Master] Control plane initialized and Weave Net installed."
else
  echo "[Master] A cluster seems to already exist; skipping kubeadm init."
fi

# ------------------------------------------------------------------------------
# Step 7: Create or retrieve Join Command, store it in /tmp/kubeadm_join_cmd.sh
# ------------------------------------------------------------------------------
echo "[Master] Step 7: Creating or retrieving join command..."

# This ensures we have at least one valid token:
sudo kubeadm token create --ttl 1h --print-join-command > /tmp/kubeadm_join_cmd.sh 2>/dev/null || true

# If that fails for any reason, try retrieving an existing token:
if ! grep -q 'kubeadm join' /tmp/kubeadm_join_cmd.sh; then
  sudo kubeadm token create --print-join-command > /tmp/kubeadm_join_cmd.sh
fi

echo "[Master] The join command is stored in /tmp/kubeadm_join_cmd.sh"
echo "Contents:"
cat /tmp/kubeadm_join_cmd.sh
echo "---------------------------------------------------"

# ------------------------------------------------------------------------------
# Step 8 (Optional): Copy the join command to worker nodes
# ------------------------------------------------------------------------------
echo "[Master] Step 8: Copying join command to workers via scp..."
scp -o StrictHostKeyChecking=no /tmp/kubeadm_join_cmd.sh "$WORKER1:/tmp/"
scp -o StrictHostKeyChecking=no /tmp/kubeadm_join_cmd.sh "$WORKER2:/tmp/"

echo "[Master] All done!"
echo "If worker scripts automatically read /tmp/kubeadm_join_cmd.sh,"
echo "they will join without manually entering tokens."
