#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to cleanup resources
cleanup() {
    echo -e "\n🧹 ${BLUE}Cleaning up resources...${NC}"
    
    # Set default namespace if manifest doesn't exist
    NAMESPACE="${ORGANIZATION_PREFIX:-default}-${ENVIRONMENT:-dev}"
    
    # Try to get namespace from manifest if it exists and yq is available
    if [ -f "$HOME/.scholar-spark/manifest/manifest.yaml" ] && command -v yq &>/dev/null; then
        TEMP_NAMESPACE=$(yq '.dev-environment.namespace' "$HOME/.scholar-spark/manifest/manifest.yaml" 2>/dev/null)
        if [ ! -z "$TEMP_NAMESPACE" ] && [ "$TEMP_NAMESPACE" != "null" ]; then
            NAMESPACE="$TEMP_NAMESPACE"
        fi
    fi
    
    # Delete namespace if it exists
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        echo -e "🗑️  ${BLUE}Deleting namespace $NAMESPACE...${NC}"
        kubectl delete namespace "$NAMESPACE" --timeout=2m || {
            echo -e "${YELLOW}Force deleting namespace...${NC}"
            kubectl delete namespace "$NAMESPACE" --force --grace-period=0
        }
    fi
    
    # Stop minikube if it's running
    if minikube status &>/dev/null; then
        echo -e "🛑 ${BLUE}Stopping minikube cluster...${NC}"
        minikube stop
    fi
    
    echo -e "✨ ${GREEN}Cleanup completed${NC}"
}

# Function to handle script interruption
handle_interrupt() {
    echo -e "\n\n⚠️  ${YELLOW}Script interrupted. Cleaning up...${NC}"
    cleanup
    exit 1
}

# Register the interrupt handler
trap handle_interrupt SIGINT SIGTERM

# Function to get project name from pyproject.toml
get_project_name() {
    if [[ -f "pyproject.toml" ]]; then
        # Extract name from pyproject.toml using grep and cut
        PROJECT_NAME=$(grep '^name = ' pyproject.toml | cut -d'"' -f2 || echo "")
        if [[ -n "$PROJECT_NAME" ]]; then
            echo "$PROJECT_NAME"
            return 0
        fi
    fi
    
    echo -e "${RED}Error: Could not find project name in pyproject.toml${NC}"
    echo -e "${YELLOW}Please ensure you're in the project root directory with a valid pyproject.toml${NC}"
    exit 1
}

# Get service name from pyproject.toml
SERVICE_NAME=$(get_project_name)
echo -e "${BLUE}Detected service: ${SERVICE_NAME}${NC}"

# Function to detect OS and distribution
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# Function to install dependencies based on OS
install_dependencies() {
    local os=$1
    echo -e "${BLUE}Installing dependencies for $os...${NC}"
    
    case $os in
        "macos")
            if ! command -v brew &> /dev/null; then
                echo -e "${YELLOW}Installing Homebrew...${NC}"
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            brew install yq minikube kubectl skaffold helm
            ;;
            
        "ubuntu"|"debian")
            sudo apt-get update
            sudo apt-get install -y curl wget apt-transport-https
            
            # Install yq
            echo -e "${YELLOW}Installing yq...${NC}"
            sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
            sudo chmod a+x /usr/local/bin/yq
            
            # Install Helm
            curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
            sudo apt-get update
            sudo apt-get install -y helm
            
            # Install minikube
            curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
            sudo install minikube-linux-amd64 /usr/local/bin/minikube
            rm minikube-linux-amd64
            
            # Install kubectl
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            sudo install kubectl /usr/local/bin/kubectl
            rm kubectl
            
            # Install Skaffold
            curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64
            sudo install skaffold /usr/local/bin/
            rm skaffold
            ;;
            
        "fedora"|"rhel"|"centos")
            sudo dnf install -y curl wget
            
            # Install yq
            echo -e "${YELLOW}Installing yq...${NC}"
            sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
            sudo chmod a+x /usr/local/bin/yq
            
            # Install Helm
            curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
            
            # Install minikube
            curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
            sudo install minikube-linux-amd64 /usr/local/bin/minikube
            rm minikube-linux-amd64
            
            # Install kubectl
            curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
            sudo install kubectl /usr/local/bin/kubectl
            rm kubectl
            
            # Install Skaffold
            curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64
            sudo install skaffold /usr/local/bin/
            rm skaffold
            ;;
            
        "arch"|"manjaro")
            sudo pacman -Sy --noconfirm curl wget yq minikube kubectl helm
            ;;

        "nixos")
            # For NixOS, we'll guide users to add these to their configuration
            echo -e "${YELLOW}For NixOS, please add the following to your configuration.nix:${NC}"
            echo -e "
environment.systemPackages = with pkgs; [
  docker
  kubectl
  minikube
  skaffold
  helm
];

virtualisation.docker.enable = true;
"
            echo -e "${YELLOW}Then run: sudo nixos-rebuild switch${NC}"
            read -p "Press Enter once you've updated your NixOS configuration..."
            
            # Verify installations
            if ! command -v docker &> /dev/null || \
               ! command -v kubectl &> /dev/null || \
               ! command -v minikube &> /dev/null || \
               ! command -v skaffold &> /dev/null || \
               ! command -v helm &> /dev/null; then
                echo -e "${RED}Some required tools are missing. Please ensure they are added to your NixOS configuration.${NC}"
                exit 1
            fi
            ;;
            
        *)
            echo -e "${RED}Unsupported operating system${NC}"
            exit 1
            ;;
    esac
}

# Check if Docker is installed and running
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
        exit 1
    fi

    # Save current Docker context if it exists
    if [ -f ~/.docker/config.json ]; then
        ORIGINAL_DOCKER_CONTEXT=$(docker context inspect -f '{{.Name}}' 2>/dev/null || echo "default")
    else
        ORIGINAL_DOCKER_CONTEXT="default"
    fi

    # Test local Docker daemon
    if ! docker info &> /dev/null; then
        echo -e "${RED}Local Docker daemon is not running. Please start Docker first.${NC}"
        echo -e "${YELLOW}On Linux, you can start it with: sudo systemctl start docker${NC}"
        exit 1
    fi
}

# Function to get service URL
get_service_url() {
    local retries=0
    local max_retries=30
    local service_url=""

    echo -e "${BLUE}Waiting for service URL...${NC}"
    
    while [ $retries -lt $max_retries ]; do
        service_url=$(minikube service ${SERVICE_NAME} -n scholar-spark-dev --url 2>/dev/null)
        if [ -n "$service_url" ]; then
            echo "$service_url"
            return 0
        fi
        retries=$((retries + 1))
        sleep 2
        echo -n "."
    done
    
    echo -e "\n${RED}Could not get service URL. Using localhost:8000 as fallback${NC}"
    echo "http://localhost:8000"
}

# Print developer-friendly information
print_dev_info() {
    clear
    echo -e "🚀 ${GREEN}Scholar Spark Development Environment${NC}\n"
    echo -e "📦 ${BLUE}Service: ${GREEN}${SERVICE_NAME}${NC}\n"
    echo -e "🔗 ${BLUE}API Endpoints:${NC}"
    echo -e "   ${GREEN}→ API:     ${SERVICE_URL}${API_PATH:-/api/v1}"
    echo -e "   → Docs:    ${SERVICE_URL}/docs"
    echo -e "   → Health:  ${SERVICE_URL}/health${NC}\n"
    echo -e "📝 ${BLUE}Development Tips:${NC}"
    echo -e "   ${GREEN}→ Your code changes will automatically reload"
    echo -e "   → API docs are always up-to-date at /docs"
    echo -e "   → Logs will appear below${NC}\n"
    echo -e "🛠️  ${BLUE}Useful Commands:${NC}"
    echo -e "   ${GREEN}→ CTRL+C to stop the service"
    echo -e "   → ./scripts/dev.sh to restart${NC}\n"
    echo -e "📊 ${BLUE}Monitoring:${NC}"
    echo -e "   ${GREEN}→ Traces: ${TRACES_ENDPOINT:-http://localhost:3200}"
    echo -e "   → Logs:   ${LOGS_ENDPOINT:-http://localhost:3100}${NC}\n"
    echo -e "${YELLOW}Starting development server...${NC}\n"
}

# Function to setup Helm registry authentication
setup_helm_registry() {
    echo -e "${BLUE}Setting up Helm registry authentication...${NC}"
    
    # Check for required tools
    for cmd in gh jq; do
        if ! command -v $cmd &> /dev/null; then
            case $cmd in
                gh)
                    echo -e "${YELLOW}Installing GitHub CLI...${NC}"
                    case $OS in
                        "macos")
                            brew install gh
                            ;;
                        "ubuntu"|"debian")
                            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                            sudo apt update
                            sudo apt install -y gh
                            ;;
                        "fedora"|"rhel"|"centos")
                            sudo dnf install -y gh
                            ;;
                        "arch"|"manjaro")
                            sudo pacman -S --noconfirm github-cli
                            ;;
                    esac
                    ;;
                jq)
                    echo -e "${YELLOW}Installing jq...${NC}"
                    case $OS in
                        "macos")
                            brew install jq
                            ;;
                        "ubuntu"|"debian")
                            sudo apt update && sudo apt install -y jq
                            ;;
                        "fedora"|"rhel"|"centos")
                            sudo dnf install -y jq
                            ;;
                        "arch"|"manjaro")
                            sudo pacman -S --noconfirm jq
                            ;;
                    esac
                    ;;
            esac
        fi
    done

    # Check if already authenticated with correct scopes
    if gh auth status &>/dev/null && gh auth scope | grep -q "read:packages" && gh auth scope | grep -q "write:packages"; then
        echo -e "${GREEN}Already authenticated with GitHub with correct scopes${NC}"
    else
        echo -e "${YELLOW}Please login to GitHub with organization access...${NC}"
        gh auth login --scopes "read:packages,write:packages,repo,admin:org" --git-protocol ssh --web
    fi

    # Get GitHub token
    GITHUB_USER=$(gh api user | jq -r .login)
    echo -e "${GREEN}Authenticated as: ${GITHUB_USER}${NC}"
    
    TOKEN=$(gh auth token)
    if [ -z "$TOKEN" ]; then
        echo -e "${RED}Failed to get GitHub token${NC}"
        exit 1
    fi

    # Login to Helm registry
    echo -e "${BLUE}Logging into Helm registry...${NC}"
    if ! helm registry login ghcr.io -u "$GITHUB_USER" -p "$TOKEN"; then
        echo -e "${RED}Failed to login to Helm registry${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Successfully authenticated with Helm registry${NC}"
}

# Function to clone/update manifest repository
setup_manifest() {
    echo -e "${BLUE}Setting up development manifest...${NC}"
    
    MANIFEST_DIR="$HOME/.scholar-spark/manifest"
    # Use environment variable with fallback
    MANIFEST_REPO="${DEV_MANIFEST_REPO:-https://github.com/scholar-spark/scholarSparkDevManifest.gitt}"
    
    if [ -z "$DEV_MANIFEST_REPO" ]; then
        echo -e "${YELLOW}Warning: DEV_MANIFEST_REPO not set, using default repository${NC}"
    fi
    
    if [ ! -d "$MANIFEST_DIR" ]; then
        echo -e "${BLUE}Cloning manifest repository...${NC}"
        mkdir -p "$MANIFEST_DIR"
        git clone "$MANIFEST_REPO" "$MANIFEST_DIR" || {
            echo -e "${RED}Failed to clone manifest repository${NC}"
            exit 1
        }
    else
        echo -e "${BLUE}Updating manifest repository...${NC}"
        git -C "$MANIFEST_DIR" pull || {
            echo -e "${RED}Failed to update manifest repository${NC}"
            exit 1
        }
    fi
    
    echo -e "${GREEN}Successfully setup manifest${NC}"
}

# Function to verify yq installation
verify_yq() {
    # Find yq location
    YQ_PATH=$(which yq 2>/dev/null)
    
    # Force reinstall yq
    echo -e "${YELLOW}Installing/Updating yq...${NC}"
    case $OS in
        "ubuntu"|"debian")
            sudo rm -f /usr/local/bin/yq
            sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64
            sudo chmod a+x /usr/local/bin/yq
            YQ_PATH="/usr/local/bin/yq"
            ;;
        "macos")
            brew reinstall yq
            YQ_PATH=$(which yq)
            ;;
        "fedora"|"rhel"|"centos")
            sudo rm -f /usr/local/bin/yq
            sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64
            sudo chmod a+x /usr/local/bin/yq
            YQ_PATH="/usr/local/bin/yq"
            ;;
        "arch"|"manjaro")
            sudo pacman -Sy --noconfirm yq
            YQ_PATH=$(which yq)
            ;;
    esac
    
    # Verify installation
    if ! $YQ_PATH --version &>/dev/null; then
        echo -e "${RED}Failed to install yq${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Using yq at: $YQ_PATH${NC}"
    $YQ_PATH --version
    
    # Test yq with a simple YAML parse
    echo "test: value" | $YQ_PATH '.test' > /dev/null || {
        echo -e "${RED}yq installation is not working correctly${NC}"
        exit 1
    }
    
    # Export YQ_PATH for use in other functions
    export YQ_PATH
    
    echo -e "${GREEN}yq test successful${NC}"
}

# Function to apply manifest configuration
apply_manifest() {
    echo -e "\n📦 ${BLUE}Applying manifest configuration...${NC}"
    
    MANIFEST_DIR="$HOME/.scholar-spark/manifest"
    MANIFEST_FILE="$MANIFEST_DIR/manifest.yaml"
    
    # Verify manifest file exists
    if [ ! -f "$MANIFEST_FILE" ]; then
        echo -e "${RED}Manifest file not found at $MANIFEST_FILE${NC}"
        exit 1
    fi
    
    echo -e "🔍 ${BLUE}Reading manifest configuration...${NC}"
    
    # Debug: Print manifest content and yq version
    echo -e "📄 ${BLUE}Manifest content:${NC}"
    cat "$MANIFEST_FILE"
    echo -e "\n🔧 ${BLUE}Using yq version:${NC}"
    $YQ_PATH --version
    
    # Validate manifest structure
    if ! $YQ_PATH -r '.' "$MANIFEST_FILE" > /dev/null 2>&1; then
        echo -e "${RED}Invalid YAML structure in manifest file${NC}"
        exit 1
    fi
    
    # Parse namespace from manifest with v3 syntax
    echo -e "\n🔍 ${BLUE}Parsing namespace...${NC}"
    NAMESPACE=$($YQ_PATH -r '.["dev-environment"].namespace' "$MANIFEST_FILE")
    echo -e "📍 ${BLUE}Using namespace: $NAMESPACE${NC}"
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo -e "🔧 ${BLUE}Creating namespace: $NAMESPACE${NC}"
        kubectl create namespace "$NAMESPACE"
    fi
    
    # Install shared infrastructure charts
    echo -e "🚀 ${BLUE}Installing shared infrastructure...${NC}"
    
    echo -e "🔍 ${BLUE}Parsing chart details...${NC}"
    # Read chart details from manifest with v3 syntax and bracket notation
    CHART_REPO=$($YQ_PATH -r '.["shared-infrastructure"].charts[0].repository' "$MANIFEST_FILE")
    echo "Debug: CHART_REPO = $CHART_REPO"
    
    CHART_VERSION=$($YQ_PATH -r '.["shared-infrastructure"].charts[0].version' "$MANIFEST_FILE")
    echo "Debug: CHART_VERSION = $CHART_VERSION"
    
    CHART_NAME=$($YQ_PATH -r '.["shared-infrastructure"].charts[0].name' "$MANIFEST_FILE")
    echo "Debug: CHART_NAME = $CHART_NAME"
    
    # Debug: Print full YAML structure
    echo -e "\n📄 ${BLUE}Full YAML structure:${NC}"
    $YQ_PATH -r '.' "$MANIFEST_FILE"
    
    # Verify values exist
    if [ -z "$CHART_REPO" ] || [ -z "$CHART_VERSION" ] || [ -z "$CHART_NAME" ]; then
        echo -e "${RED}Failed to parse chart information. Please check the manifest structure:${NC}"
        echo -e "Expected structure:"
        echo -e "shared-infrastructure:"
        echo -e "  charts:"
        echo -e "  - repository: <value>"
        echo -e "    version: <value>"
        echo -e "    name: <value>"
        exit 1
    fi
    
    echo -e "📥 ${BLUE}Pulling chart: $CHART_NAME (version $CHART_VERSION)${NC}"
    echo -e "   ${BLUE}From: $CHART_REPO${NC}"
    
    # Ensure we're using minikube context
    echo -e "🔄 ${BLUE}Switching to minikube context...${NC}"
    kubectl config use-context minikube || {
        echo -e "${RED}Failed to switch to minikube context${NC}"
        exit 1
    }
    
    # Replace variables in repository URL
    CHART_REPO_PARSED=$(echo "$CHART_REPO" | \
        sed "s/\${organisation}/$($YQ_PATH -r '.organisation' "$MANIFEST_FILE")/g" | \
        sed "s/\${environment}/$($YQ_PATH -r '.environment' "$MANIFEST_FILE")/g")

    # Use parsed repository URL
    if ! helm pull "$CHART_REPO_PARSED/$CHART_NAME" --version "$CHART_VERSION" --destination . ; then
        echo -e "${RED}Failed to pull chart from repository${NC}"
        echo -e "Repository: $CHART_REPO_PARSED"
        echo -e "Chart: $CHART_NAME"
        echo -e "Version: $CHART_VERSION"
        exit 1
    fi

    CHART_FILE="${CHART_NAME}-${CHART_VERSION}.tgz"
    
    # Verify chart file exists
    if [ ! -f "$CHART_FILE" ]; then
        echo -e "${RED}Chart file not found: $CHART_FILE${NC}"
        echo -e "Current directory contents:"
        ls -la
        exit 1
    fi
    
    # Extract values from manifest and create temporary values file
    TMP_VALUES=$(mktemp)
    $YQ_PATH -r '.["shared-infrastructure"].charts[0].values' "$MANIFEST_FILE" > "$TMP_VALUES"
    
    echo -e "⚙️  ${BLUE}Installing chart with custom values...${NC}"
    
    # Install/upgrade the chart with explicit chart file path and increased timeout
    helm upgrade --install "$CHART_NAME" "./$CHART_FILE" \
        --namespace "$NAMESPACE" \
        --values "$TMP_VALUES" \
        --timeout 10m \
        --wait \
        --debug || {
        echo -e "${RED}Failed to install chart${NC}"
        
        # Debug Loki deployment specifically
        echo -e "\n${YELLOW}Checking Loki deployment:${NC}"
        kubectl describe deployment loki -n "$NAMESPACE"
        
        # Debug Loki pod status
        echo -e "\n${YELLOW}Checking Loki pod status:${NC}"
        kubectl get pods -n "$NAMESPACE" -l app=${LOGGING_APP:-loki} -o wide
        
        # Get Loki pod events
        echo -e "\n${YELLOW}Checking Loki pod events:${NC}"
        LOKI_POD=$(kubectl get pods -n "$NAMESPACE" -l app=${LOGGING_APP:-loki} -o name | head -n 1)
        if [ ! -z "$LOKI_POD" ]; then
            kubectl describe "$LOKI_POD" -n "$NAMESPACE"
        fi
        
        # Check Loki pod logs
        echo -e "\n${YELLOW}Checking Loki pod logs:${NC}"
        if [ ! -z "$LOKI_POD" ]; then
            kubectl logs "$LOKI_POD" -n "$NAMESPACE" --all-containers=true || true
        fi
        
        # Check storage requirements
        echo -e "\n${YELLOW}Checking storage requirements:${NC}"
        kubectl get pvc -n "$NAMESPACE"
        kubectl get storageclass
        
        # Check resource requirements
        echo -e "\n${YELLOW}Checking resource requirements:${NC}"
        kubectl describe nodes | grep -A 10 "Allocated resources"
        
        rm -f "$TMP_VALUES"
        rm -f "./$CHART_FILE"
        
        echo -e "\n${RED}Loki deployment failed to become ready. Please check the logs above for details.${NC}"
        exit 1
    }
    
    # Wait specifically for Loki to be ready
    echo -e "\n${BLUE}Waiting for Loki to be ready...${NC}"
    local retries=0
    local max_retries=30
    
    while [ $retries -lt $max_retries ]; do
        # Get the Loki pod name
        LOKI_POD=$(kubectl get pods -n "$NAMESPACE" -l app=${LOGGING_APP:-loki} -o name | head -n 1)
        
        if [ ! -z "$LOKI_POD" ]; then
            # Check pod status
            POD_STATUS=$(kubectl get "$LOKI_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
            
            if [ "$POD_STATUS" = "Error" ] || [ "$POD_STATUS" = "CrashLoopBackOff" ]; then
                echo -e "\n${RED}Loki pod is in $POD_STATUS state. Checking logs:${NC}"
                kubectl logs "$LOKI_POD" -n "$NAMESPACE" --previous || true
                echo -e "\n${YELLOW}Pod events:${NC}"
                kubectl describe "$LOKI_POD" -n "$NAMESPACE" | grep -A 10 "Events:"
                exit 1
            fi
            
            # Check if pod is ready
            READY_STATUS=$(kubectl get "$LOKI_POD" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].ready}')
            if [ "$READY_STATUS" = "true" ]; then
                echo -e "\n${GREEN}Loki is ready!${NC}"
                break
            fi
        fi
        
        # Every 5 retries, show status
        if [ $((retries % 5)) -eq 0 ]; then
            echo -e "\n${YELLOW}Current Loki status:${NC}"
            kubectl get pods -n "$NAMESPACE" -l app=${LOGGING_APP:-loki}
            echo -e "\n${YELLOW}Recent events:${NC}"
            kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name=loki --sort-by='.lastTimestamp' | tail -n 5
        fi
        
        echo -n "."
        retries=$((retries + 1))
        sleep 2
    done
    
    if [ $retries -eq $max_retries ]; then
        echo -e "\n${RED}Timeout waiting for Loki to be ready${NC}"
        echo -e "\n${YELLOW}Final pod status:${NC}"
        kubectl get pods -n "$NAMESPACE" -l app=${LOGGING_APP:-loki}
        echo -e "\n${YELLOW}Pod logs:${NC}"
        kubectl logs "$LOKI_POD" -n "$NAMESPACE" --previous || true
        exit 1
    fi
    
    # Cleanup
    rm -f "$TMP_VALUES"
    rm -f "./$CHART_FILE"
    
    echo -e "✅ ${GREEN}Successfully applied manifest configuration${NC}"
}

# Main setup process
main() {
    # Load environment variables from .env file
    if [ -f .env ]; then
        echo -e "${BLUE}Loading environment variables from .env file...${NC}"
        export $(cat .env | grep -v '^#' | xargs)
    else
        echo -e "${RED}Error: No .env file found. Please create one based on .env.example${NC}"
        exit 1
    fi

    # Perform initial cleanup
    echo -e "\n🧹 ${BLUE}Performing initial cleanup...${NC}"
    cleanup

    echo -e "${BLUE}Setting up development environment...${NC}"
    
    # Check Docker first
    check_docker
    
    # Detect OS and verify yq installation first
    OS=$(detect_os)
    echo -e "${BLUE}Detected OS: $OS${NC}"
    verify_yq
    
    # Install dependencies if needed
    if [[ ! -x "$(command -v minikube)" ]] || \
       [[ ! -x "$(command -v kubectl)" ]] || \
       [[ ! -x "$(command -v skaffold)" ]] || \
       [[ ! -x "$(command -v helm)" ]] || \
       [[ ! -x "$(command -v yq)" ]]; then
        install_dependencies "$OS"
    fi
    
    # Start minikube if not running
    if ! minikube status &> /dev/null; then
        echo -e "${BLUE}Starting Minikube...${NC}"
        minikube start --driver=docker \
            --docker-opt dns=8.8.8.8 \
            --docker-opt dns=8.8.4.4 \
            --insecure-registry "10.0.0.0/24" \
            --registry-mirror=https://mirror.gcr.io \
            --registry-mirror=https://registry-1.docker.io
    fi
    
    # Save the local Docker context before switching
    echo -e "${BLUE}Switching to Minikube's Docker daemon...${NC}"
    echo -e "${YELLOW}Note: Your local Docker daemon will be temporarily unavailable${NC}"
    eval $(minikube docker-env)
    
    # Setup Helm registry authentication
    setup_helm_registry
    
    # Setup and apply manifest
    setup_manifest
    apply_manifest
    
    # Get service URL once and store it
    SERVICE_URL=$(get_service_url)
    
    # Print developer-friendly information
    print_dev_info

    # Start skaffold
    echo -e "${BLUE}Starting Skaffold...${NC}"
    skaffold dev --port-forward

    # Restore original Docker context when script exits
    trap 'echo -e "${BLUE}Restoring local Docker context...${NC}" && docker context use "$ORIGINAL_DOCKER_CONTEXT" &>/dev/null' EXIT
}

# Run main function
main
