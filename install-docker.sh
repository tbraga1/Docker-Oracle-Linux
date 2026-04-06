#!/usr/bin/env bash

set -euo pipefail

# ==============================
# CONFIG
# ==============================
DOCKER_CONFIG="/etc/docker/daemon.json"
USER_NAME="${SUDO_USER:-$USER}"

# ==============================
# FUNCTIONS
# ==============================
log() {
    echo -e "\e[32m[INFO]\e[0m $1"
}

warn() {
    echo -e "\e[33m[WARN]\e[0m $1"
}

error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
}

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        error "Execute como root ou com sudo"
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_VERSION="${VERSION_ID%%.*}"
    else
        error "Não foi possível detectar o sistema"
        exit 1
    fi

    log "Oracle Linux versão detectada: $OS_VERSION"
}

install_dependencies() {
    log "Instalando dependências..."

    if [[ "$OS_VERSION" -ge 8 ]]; then
        dnf -y install dnf-plugins-core curl ca-certificates lvm2 device-mapper-persistent-data
    else
        yum -y install yum-utils curl ca-certificates lvm2 device-mapper-persistent-data
    fi
}

add_docker_repo() {
    log "Configurando repositório Docker..."

    if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
        if [[ "$OS_VERSION" -ge 8 ]]; then
            dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        else
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        fi
    else
        warn "Repositório Docker já existe"
    fi
}

install_docker() {
    if command -v docker &>/dev/null; then
        warn "Docker já está instalado"
        docker --version
        return
    fi

    log "Instalando Docker..."

    if [[ "$OS_VERSION" -ge 8 ]]; then
        dnf -y install docker-ce docker-ce-cli containerd.io
    else
        yum -y install docker-ce docker-ce-cli containerd.io
    fi
}

configure_docker() {
    log "Configurando Docker..."

    mkdir -p /etc/docker

    cat > "$DOCKER_CONFIG" <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "exec-opts": ["native.cgroupdriver=systemd"],
  "iptables": true,
  "ip-forward": true,
  "ipv6": false,
  "no-new-privileges": true
}
EOF
}

start_enable_docker() {
    log "Habilitando e iniciando Docker..."

    systemctl daemon-reexec
    systemctl enable docker
    systemctl restart docker
}

configure_user() {
    log "Configurando permissões do usuário ($USER_NAME)..."

    if ! getent group docker >/dev/null; then
        groupadd docker
    fi

    usermod -aG docker "$USER_NAME"

    warn "Necessário logout/login para aplicar grupo docker"
}

validate_installation() {
    log "Validando instalação..."

    if ! systemctl is-active --quiet docker; then
        error "Docker não está rodando"
        exit 1
    fi

    docker info >/dev/null || {
        error "Falha ao acessar Docker"
        exit 1
    }

    log "Executando container de teste..."
    docker run --rm hello-world >/dev/null

    log "Docker instalado e funcional 🚀"
}

# ==============================
# MAIN
# ==============================
main() {
    require_root
    detect_os
    install_dependencies
    add_docker_repo
    install_docker
    configure_docker
    start_enable_docker
    configure_user
    validate_installation

    log "Instalação concluída com sucesso!"
}

main
