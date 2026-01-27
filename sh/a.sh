#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_step() { echo -e "${CYAN}${BOLD}>>> $1${NC}"; }

show_banner() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║${NC}     ${BOLD}${CYAN}Any内网穿透 - frps服务端一键安装脚本${NC}                  ${CYAN}║${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}║${NC}     版本: v1.0.0                                             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     作者: Any                                                ${CYAN}║${NC}"
    echo -e "${CYAN}║                                                              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户或 sudo 运行此脚本"
        exit 1
    fi
    print_success "Root权限检查通过"
}

detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    else
        print_error "无法检测系统类型，仅支持 Debian/Ubuntu/CentOS"
        exit 1
    fi
    print_success "系统检测: $OS $VERSION"
}

install_package() {
    local pkg=$1
    print_info "正在安装 $pkg ..."
    case $OS in
        debian|ubuntu)
            if ! apt-get install -y $pkg >/dev/null 2>&1; then
                print_error "$pkg 安装失败"
                return 1
            fi
            ;;
        centos|rhel)
            if ! yum install -y $pkg >/dev/null 2>&1; then
                print_error "$pkg 安装失败"
                return 1
            fi
            ;;
        *)
            print_error "不支持的系统"
            return 1
            ;;
    esac
    print_success "$pkg 安装成功"
    return 0
}

install_dependencies() {
    print_step "检查并安装依赖"
    
    case $OS in
        debian|ubuntu)
            print_info "更新软件源..."
            if apt-get update -y >/dev/null 2>&1; then
                print_success "软件源更新完成"
            else
                print_warning "软件源更新失败，尝试切换阿里云镜像源..."
                cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true
                if [ "$OS" = "debian" ]; then
                    local codename=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d'=' -f2)
                    codename=${codename:-bookworm}
                    cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/debian ${codename} main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian ${codename}-updates main contrib non-free non-free-firmware
deb http://mirrors.aliyun.com/debian-security ${codename}-security main contrib non-free non-free-firmware
EOF
                else
                    local codename=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d'=' -f2)
                    codename=${codename:-jammy}
                    cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/ubuntu ${codename} main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu ${codename}-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu ${codename}-security main restricted universe multiverse
EOF
                fi
                apt-get clean >/dev/null 2>&1
                if apt-get update -y >/dev/null 2>&1; then
                    print_success "已切换阿里云镜像源"
                else
                    print_warning "软件源仍有问题，继续尝试安装..."
                fi
            fi
            ;;
        centos|rhel)
            print_info "更新软件源..."
            yum makecache -y >/dev/null 2>&1 || true
            ;;
    esac
    
    local required_tools=("wget" "curl" "tar")
    for tool in "${required_tools[@]}"; do
        if command -v $tool &>/dev/null; then
            print_success "$tool 已安装"
        else
            if ! install_package $tool; then
                print_error "必要工具 $tool 安装失败，无法继续"
                exit 1
            fi
        fi
    done
    
    echo ""
    print_success "所有依赖检查完成"
}

select_version() {
    print_step "选择 frps 版本"
    echo ""
    echo -e "  ${GREEN}1)${NC} 0.66.0 ${YELLOW}(推荐)${NC}"
    echo -e "  ${GREEN}2)${NC} 0.65.0"
    echo ""
    
    while true; do
        read -p "请输入选项 [1-2] (默认: 1): " version_choice
        version_choice=${version_choice:-1}
        case $version_choice in
            1) FRPS_VERSION="0.66.0"; DOWNLOAD_URL="https://any001.ipv4.website/frps/frps0.66.0"; break ;;
            2) FRPS_VERSION="0.65.0"; DOWNLOAD_URL="https://any001.ipv4.website/frps/frps0.65.0"; break ;;
            *) print_error "无效选项，请重新输入" ;;
        esac
    done
    print_success "已选择版本: $FRPS_VERSION"
}

get_config() {
    print_step "配置 frps 参数"
    echo ""
    echo -e "${YELLOW}提示: 直接回车使用默认值${NC}"
    echo ""
    
    read -p "服务端端口 (默认: 10002): " BIND_PORT
    BIND_PORT=${BIND_PORT:-10002}
    
    read -p "认证Token (默认: 123456): " AUTH_TOKEN
    AUTH_TOKEN=${AUTH_TOKEN:-123456}
    
    read -p "Web管理端口 (默认: 10001): " WEB_PORT
    WEB_PORT=${WEB_PORT:-10001}
    
    read -p "Web用户名 (默认: any): " WEB_USER
    WEB_USER=${WEB_USER:-any}
    
    read -p "Web密码 (默认: 123456): " WEB_PASSWORD
    WEB_PASSWORD=${WEB_PASSWORD:-123456}
    
    read -p "端口范围-起始 (默认: 10006): " PORT_START
    PORT_START=${PORT_START:-10006}
    
    read -p "端口范围-结束 (默认: 12000): " PORT_END
    PORT_END=${PORT_END:-12000}
    
    echo ""
    print_success "参数配置完成"
}

install_frps() {
    print_step "下载并安装 frps"
    
    INSTALL_DIR="/root/AnyFRPS"
    mkdir -p $INSTALL_DIR
    cd $INSTALL_DIR
    
    if [ -f "$INSTALL_DIR/frps" ]; then
        print_info "检测到已存在的 frps，正在停止服务..."
        systemctl stop frps >/dev/null 2>&1 || true
        pkill -f "$INSTALL_DIR/frps" >/dev/null 2>&1 || true
        sleep 2
        rm -f "$INSTALL_DIR/frps" >/dev/null 2>&1 || true
    fi
    
    print_info "正在下载 frps $FRPS_VERSION ..."
    print_info "下载地址: $DOWNLOAD_URL"
    
    local retry=3
    local success=false
    local tmp_file="/tmp/frps_download_$$"
    
    for ((i=1; i<=retry; i++)); do
        print_info "下载尝试 $i/$retry ..."
        
        if command -v curl &>/dev/null; then
            if curl -L --connect-timeout 30 --max-time 300 --progress-bar -o "$tmp_file" "$DOWNLOAD_URL"; then
                if [ -s "$tmp_file" ]; then
                    mv "$tmp_file" "$INSTALL_DIR/frps"
                    success=true
                    break
                fi
            fi
        fi
        
        if [ "$success" = false ] && command -v wget &>/dev/null; then
            if wget --timeout=30 --show-progress -O "$tmp_file" "$DOWNLOAD_URL" 2>&1; then
                if [ -s "$tmp_file" ]; then
                    mv "$tmp_file" "$INSTALL_DIR/frps"
                    success=true
                    break
                fi
            fi
        fi
        
        rm -f "$tmp_file" 2>/dev/null
        [ $i -lt $retry ] && sleep 3
    done
    
    rm -f "$tmp_file" 2>/dev/null
    
    if [ "$success" = false ] || [ ! -s "$INSTALL_DIR/frps" ]; then
        print_error "下载失败，请检查网络连接或手动下载"
        print_info "手动下载: $DOWNLOAD_URL"
        print_info "放置到: $INSTALL_DIR/frps"
        exit 1
    fi
    
    chmod +x "$INSTALL_DIR/frps"
    print_success "frps 下载完成"
}

create_config() {
    print_step "创建配置文件"
    
    cat > $INSTALL_DIR/frps.toml << EOF
bindAddr = "0.0.0.0"
bindPort = $BIND_PORT
transport.maxPoolCount = 600
auth.method = "token"
auth.token = "$AUTH_TOKEN"
maxPortsPerClient = 0
webServer.addr = "0.0.0.0"
webServer.port = $WEB_PORT
webServer.user = "$WEB_USER"
webServer.password = "$WEB_PASSWORD"
allowPorts = [
  { start = $PORT_START, end = $PORT_END },
]
EOF
    
    print_success "配置文件: $INSTALL_DIR/frps.toml"
}

create_service() {
    print_step "创建 Systemd 服务"
    
    cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=Any FRPS Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/frps -c $INSTALL_DIR/frps.toml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    print_success "Systemd 服务创建完成"
}

configure_firewall() {
    print_step "配置防火墙"
    
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        ufw allow $BIND_PORT/tcp >/dev/null 2>&1
        ufw allow $WEB_PORT/tcp >/dev/null 2>&1
        ufw allow ${PORT_START}:${PORT_END}/tcp >/dev/null 2>&1
        ufw allow ${PORT_START}:${PORT_END}/udp >/dev/null 2>&1
        print_success "UFW 防火墙已配置"
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=$BIND_PORT/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=$WEB_PORT/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${PORT_START}-${PORT_END}/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${PORT_START}-${PORT_END}/udp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        print_success "Firewalld 已配置"
    else
        print_warning "未检测到防火墙，请手动开放端口: $BIND_PORT, $WEB_PORT, ${PORT_START}-${PORT_END}"
    fi
}

start_service() {
    print_step "启动 frps 服务"
    
    systemctl enable frps >/dev/null 2>&1
    systemctl start frps
    
    sleep 2
    
    if systemctl is-active --quiet frps; then
        print_success "frps 服务启动成功"
    else
        print_error "frps 服务启动失败"
        print_info "请使用以下命令查看日志: journalctl -u frps -f"
        exit 1
    fi
}

show_info() {
    SERVER_IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                  ${GREEN}${BOLD}✓ 安装完成${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}安装信息${NC}                                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    安装目录: /root/AnyFRPS                                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    配置文件: /root/AnyFRPS/frps.toml                        ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}连接信息${NC}                                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    服务端口: ${GREEN}$BIND_PORT${NC}                                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    Token: ${GREEN}$AUTH_TOKEN${NC}                                          ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}Web管理面板${NC}                                                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    地址: ${GREEN}http://$SERVER_IP:$WEB_PORT${NC}                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    用户: ${GREEN}$WEB_USER${NC}  密码: ${GREEN}$WEB_PASSWORD${NC}                           ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}端口范围${NC}: ${GREEN}${PORT_START} - ${PORT_END}${NC}                                   ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}服务管理命令${NC}                                                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    启动: ${YELLOW}systemctl start frps${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    停止: ${YELLOW}systemctl stop frps${NC}                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    重启: ${YELLOW}systemctl restart frps${NC}                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    状态: ${YELLOW}systemctl status frps${NC}                             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    日志: ${YELLOW}journalctl -u frps -f${NC}                             ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

cleanup() {
    rm -f "$0" 2>/dev/null
}

main() {
    clear
    show_banner
    
    check_root
    detect_system
    install_dependencies
    select_version
    get_config
    install_frps
    create_config
    create_service
    configure_firewall
    start_service
    show_info
    cleanup
    
    print_success "感谢使用 Any内网穿透!"
    echo ""
}

main
