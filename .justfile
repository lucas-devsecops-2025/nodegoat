set export
set dotenv-filename := '.env.secrets'
set dotenv-load

KIND_CLUSTER_NAME := 'devsecops'
RED := '\033[0;31m'
GREEN := '\033[0;32m'
YELLOW := '\033[1;33m'
BLUE := '\033[0;34m'
NC := '\033[0m'


@_default:
  just --list


# Build the application
@build:
  docker compose build
# Start app container and DB
@start: build
  docker compose up --build -d
# Stop app container and DB
@stop:
  docker compose stop


# Start nodegoat in k8s
start-nodegoat-k8s:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="nodegoat"
  kubectl create ns ${NAMESPACE} || true
  kubectl apply -n ${NAMESPACE} -f k8s/nodegoat/
# Start nodegoat in k8s
stop-nodegoat-k8s:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="nodegoat"
  kubectl delete -n ${NAMESPACE} -f k8s/nodegoat/


# Start sonarqube
start-sonarqube:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="sonarqube"
  kind get clusters |grep -q ${KIND_CLUSTER_NAME} || just _error "You should configure the kubernetes cluster before. See just 'start-kind-cluster'..."
  helm repo update
  helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
  helm upgrade --install sonarqube sonarqube/sonarqube \
    --namespace "${NAMESPACE}" \
    --create-namespace \
  -f k8s/sonarqube/sonarqube-values.yaml
# Stop sonarqube
stop-sonarqube:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="sonarqube"
  helm uninstall sonarqube -n ${NAMESPACE}


# Start dependency-track
start-dependency-track:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="dependencytrack"
  helm repo add dependency-track https://dependencytrack.github.io/helm-charts
  helm repo update
  helm upgrade --install \
    dependencytrack \
    dependency-track/dependency-track \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set frontend.service.type="NodePort" \
    --set frontend.service.nodePort=30801 \
    --set frontend.apiBaseUrl="http://localhost:4001" \
    --set apiServer.metrics.enabled=true \
    --set apiServer.persistentVolume.enabled="true" \
    --set apiServer.persistentVolume.size="2Gi" \
    --set apiServer.service.nodePort=30101 \
    --set apiServer.service.type="NodePort" \
    --set apiServer.service.nodePort=30101
# Stop dependency-track
stop-dependency-track:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="dependencytrack"
  helm uninstall dependencytrack -n ${NAMESPACE}


# Start faraday
start-faraday:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="faraday"
  helm upgrade --install \
    faraday \
    charts/faraday \
    --namespace "${NAMESPACE}" \
    --create-namespace
# Stop faraday
stop-faraday:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="faraday"
  helm uninstall faraday -n ${NAMESPACE} || true


# Start archerysec
start-archerysec:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="archerysec"
  kubectl create ns ${NAMESPACE} || true
  kubectl apply -n ${NAMESPACE} -f k8s/archery/
# Stop archerysec
stop-archerysec:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="archerysec"
  kubectl delete -n ${NAMESPACE} -f k8s/archery/


# Start Monitoring
start-monitoring:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="monitoring"
  kubectl create ns ${NAMESPACE} || true
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo update
  helm upgrade --install prometheus prometheus-community/prometheus \
    --namespace ${NAMESPACE} \
    --create-namespace \
    -f k8s/prometheus/values.yaml
  helm upgrade --install grafana grafana/grafana \
    --namespace ${NAMESPACE} \
    --create-namespace \
    -f k8s/grafana/values.yaml
# Stop monitoring
stop-monitoring:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="monitoring"
  helm uninstall -n ${NAMESPACE} grafana || true
  helm uninstall -n ${NAMESPACE} prometheus || true


# Start all
@start-all: start start-kind-cluster start-sonarqube start-dependency-track start-archerysec
# Stop all
@stop-all: stop stop-kind-cluster


# Create the kubernetes cluster
@deploy-kind-cluster:
  kind create cluster --name ${KIND_CLUSTER_NAME} --config=kind-config.yaml
  just _info "Waiting for the cluster to be ready..."
  sleep 10
  just _info "Deploying metrics-server..."
  kubectl apply -f k8s/metrics-server/
# Delete the kubernetes cluster
@destroy-kind-cluster:
  kind delete cluster --name ${KIND_CLUSTER_NAME}


# Start the kubernetes cluster
@start-kind-cluster:
  docker start $(docker ps -a -q --filter "name=${KIND_CLUSTER_NAME}-")
# Stop the kubernetes cluster
@stop-kind-cluster:
  docker stop $(docker ps -q --filter "name=${KIND_CLUSTER_NAME}-")


# Install github runners
setup-github-runners:
  #!/usr/bin/env bash
  set -euo pipefail
  NAMESPACE="arc-systems"
  helm upgrade --install arc \
      --namespace "${NAMESPACE}" \
      --create-namespace \
      oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
  NAMESPACE="arc-runners"
  INSTALLATION_NAME="arc-runner-set"
  helm upgrade --install "${INSTALLATION_NAME}" \
      --namespace "${NAMESPACE}" \
      --create-namespace \
      --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
      --set githubConfigSecret="pre-defined-secret" \
      --set containerMode.type="dind" \
      --set minRunners=0 \
      --set maxRunners=10 \
      oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
  kubectl create secret generic pre-defined-secret \
    --namespace=${NAMESPACE} \
    --from-literal=github_token=${GITHUB_PAT} \
    --dry-run=client -o yaml | kubectl apply -f -

# Open important platforms
@open:
  open http://localhost:9000 http://localhost:8081 http://localhost:8083 http://localhost:8084

# Install project dependencies
setup:
  #!/usr/bin/env bash
  set -euo pipefail
  if [[ "{{os()}}" == "macos" ]]; then
    just _info "Installing kubectl..."
    brew install kubectl
    just _info "Installing pre-commit..."
    brew install pre-commit
    just _info "Setting up pre-commit..."
    pre-commit install
    just _info "Installing kind..."
    brew install kind
    just _info "Installing helm..."
    brew install helm
    just _info "Installing kubectx and kubens..."
    brew install kubectx
    just _info "Installing k9s..."
    brew install k9s
  elif [[ "{{os()}}" == "linux" ]]; then
    just _info "Installing python3-pip, pipx and xclip..."
    sudo apt update && sudo apt install -y python3-pip pipx xclip
    just _info "Ensuring pipx path..."
    pipx ensurepath
    # Add to .bashrc if not already present
    if ! grep -q '$HOME/.local/bin' ~/.bashrc; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
      just _info "Added ~/.local/bin to PATH in ~/.bashrc"
    fi
    # Add to current session
    export PATH="$HOME/.local/bin:$PATH"
    just _info "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl
    just _info "Installing pre-commit..."
    pipx install pre-commit
    just _info "Setting up pre-commit..."
    ~/.local/bin/pre-commit install
    just _info "Installing kind..."
    # For AMD64 / x86_64
    [ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64
    # For ARM64
    [ $(uname -m) = aarch64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-arm64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    just _info "Installing helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    just _info "Installing kubectx and kubens..."
    if [ ! -d "/opt/kubectx" ]; then
      sudo mkdir -p /opt/kubectx
      sudo git clone https://github.com/ahmetb/kubectx /tmp/kubectx
      sudo mv /tmp/kubectx/* /opt/kubectx/
      sudo rm -rf /tmp/kubectx
    fi
    sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
    sudo ln -sf /opt/kubectx/kubens /usr/local/bin/kubens
    just _info "Installing k9s..."
    curl -sS https://webi.sh/k9s | sh
    source ~/.config/envman/PATH.env
    just _info "✅ Setup complete!"
    just _info "Reloading PATH from ~/.bashrc..."
    source ~/.bashrc
    just _info "PATH reloaded! Pre-commit is now available globally."
  else
    just _error "Operating system {{os()}} not supported!"
    exit 1
  fi


_info MESSAGE:
  #!/usr/bin/env bash
  echo -e "${GREEN}[INFO]${NC} {{MESSAGE}}"
_warn MESSAGE:
  #!/usr/bin/env bash
  echo -e "${YELLOW}[WARNING]${NC} {{MESSAGE}}"
_debug MESSAGE:
  #!/usr/bin/env bash
  echo -e "${BLUE}[WARNING]${NC} {{MESSAGE}}"
_error MESSAGE:
  #!/usr/bin/env bash
  echo -e "${RED}[ERROR]${NC} {{MESSAGE}}"
  exit 1
