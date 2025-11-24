#!/bin/bash

# 确保脚本在遇到错误时退出
set -e

# 默认参数
DEFAULT_DOMAIN=""
DEFAULT_EMAIL=""
DEFAULT_CA="letsencrypt"

# 显示使用说明
show_usage() {
    echo "用法: $0 [-d 域名] [-e 邮箱] [-c CA] [-f] [-p 端口]"
    echo "  默认值:"
    echo "    域名: $DEFAULT_DOMAIN"
    echo "    邮箱: $DEFAULT_EMAIL"
    echo "    CA: $DEFAULT_CA"
    echo ""
    echo "选项:"
    echo "  -d, --domain    域名 (例如: example.com)"
    echo "  -e, --email     电子邮件地址"
    echo "  -c, --ca        证书颁发机构 (letsencrypt|buypass|zerossl)"
    echo "  -f, --firewall  关闭防火墙"
    echo "  -p, --port      放行指定端口"
    echo "  -h, --help      显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0  # 使用默认参数运行"
    echo "  $0 -d example.com -e admin@example.com"
    echo "  $0 -d example.com -e admin@example.com -c zerossl -f"
    echo "  $0 -d example.com -e admin@example.com -p 80"
}

# 初始化变量
DOMAIN="$DEFAULT_DOMAIN"
EMAIL="$DEFAULT_EMAIL"
CA_SERVER="$DEFAULT_CA"
FIREWALL_OPTION=2
PORT_OPTION=2
PORT=""

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        -c|--ca)
            case "$2" in
                letsencrypt|buypass|zerossl)
                    CA_SERVER="$2"
                    ;;
                *)
                    echo "错误: 不支持的CA: $2，支持的值: letsencrypt, buypass, zerossl"
                    exit 1
                    ;;
            esac
            shift 2
            ;;
        -f|--firewall)
            FIREWALL_OPTION=1
            shift
            ;;
        -p|--port)
            PORT_OPTION=1
            PORT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "错误: 未知参数: $1"
            show_usage
            exit 1
            ;;
    esac
done

# 检查系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
elif command -v lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
else
    echo "无法确定操作系统类型，请手动安装依赖项。"
    exit 1
fi

# 显示配置信息
echo "=== SSL证书生成配置 ==="
echo "域名: $DOMAIN"
echo "邮箱: $EMAIL"
echo "证书颁发机构: $CA_SERVER"
echo "防火墙操作: $([ "$FIREWALL_OPTION" -eq 1 ] && echo "关闭" || echo "保持开启")"
if [ "$PORT_OPTION" -eq 1 ]; then
    echo "放行端口: $PORT"
fi
echo "========================"

# 安装依赖项并关闭防火墙或放行端口
case $OS in
    ubuntu|debian)
        sudo apt update
        sudo apt upgrade -y
        sudo apt install -y curl socat git
        if [ "$FIREWALL_OPTION" -eq 1 ]; then
            sudo ufw disable
            echo "防火墙已关闭"
        elif [ "$PORT_OPTION" -eq 1 ]; then
            sudo ufw allow "$PORT"
            echo "端口 $PORT 已放行"
        fi
        ;;
    centos|rhel|fedora)
        if command -v dnf >/dev/null 2>&1; then
            sudo dnf update -y
            sudo dnf install -y curl socat git
        else
            sudo yum update -y
            sudo yum install -y curl socat git
        fi
        if [ "$FIREWALL_OPTION" -eq 1 ]; then
            sudo systemctl stop firewalld
            sudo systemctl disable firewalld
            echo "防火墙已关闭"
        elif [ "$PORT_OPTION" -eq 1 ]; then
            sudo firewall-cmd --permanent --add-port="${PORT}"/tcp
            sudo firewall-cmd --reload
            echo "端口 $PORT 已放行"
        fi
        ;;
    *)
        echo "不支持的操作系统：$OS"
        exit 1
        ;;
esac

# 安装 acme.sh
echo "正在安装 acme.sh..."
curl https://get.acme.sh | sh

# 使 acme.sh 脚本可用
export PATH="$HOME/.acme.sh:$PATH"

# 添加执行权限
chmod +x "$HOME/.acme.sh/acme.sh"

# 注册帐户（使用用户提供的电子邮件地址）
echo "正在注册账户..."
"$HOME/.acme.sh/acme.sh" --register-account -m "$EMAIL" --server "$CA_SERVER"

# 申请 SSL 证书（使用用户提供的域名）
echo "正在申请证书..."
"$HOME/.acme.sh/acme.sh" --issue --standalone -d "$DOMAIN" --server "$CA_SERVER" --force

# 安装 SSL 证书
echo "正在安装证书..."
"$HOME/.acme.sh/acme.sh" --installcert -d "$DOMAIN" \
    --key-file       "/root/${DOMAIN}.key" \
    --fullchain-file "/root/${DOMAIN}.crt"

# 提示用户证书已生成
echo "SSL证书和私钥已生成:"
echo "证书: /root/${DOMAIN}.crt"
echo "私钥: /root/${DOMAIN}.key"

# 创建自动续期的脚本
cat << EOF > /root/renew_cert.sh
#!/bin/bash
export PATH="\$HOME/.acme.sh:\$PATH"
"$HOME/.acme.sh/acme.sh" --renew -d "$DOMAIN" --server "$CA_SERVER"
EOF
chmod +x /root/renew_cert.sh

# 创建自动续期的 cron 任务
(crontab -l 2>/dev/null; echo "0 0 * * * /root/renew_cert.sh > /dev/null 2>&1") | crontab -

echo "自动续期任务已设置"
echo "完成!"


mkdir -p ./cert ./config
cp -f /root/${DOMAIN}.crt ./cert/root.crt
cp -f /root/${DOMAIN}.key ./cert/root.key
cp -f x-ui.db ./config/x-ui.db


# 安装docker 
#curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
service docker restart


# 启动x-ui配置
docker compose up -d




