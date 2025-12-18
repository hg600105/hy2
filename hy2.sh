#!/bin/bash
# 等待1秒, 避免curl下载脚本的打印与脚本本身的显示冲突, 吃掉了提示用户按回车继续的信息
sleep 1

echo -e "                     _ ___                   \n ___ ___ __ __ ___ _| |  _|___ __ __   _ ___ \n|-_ |_  |  |  |-_ | _ |   |- _|  |  |_| |_  |\n|___|___|  _  |___|___|_|_|___|  _  |___|___|\n        |_____|               |_____|        "
red='\e[91m'
green='\e[92m'
yellow='\e[93m'
magenta='\e[95m'
cyan='\e[96m'
none='\e[0m'

error() {
    echo -e "\n${red} 输入错误! ${none}\n"
}

warn() {
    echo -e "\n$yellow $1 $none\n"
}

pause() {
    read -rsp "$(echo -e "按 ${green} Enter 回车键 ${none} 继续....或按 ${red} Ctrl + C ${none} 取消.")" -d $'\n'
    echo
}

# 卸载函数
uninstall_hysteria() {
    echo
    echo -e "${yellow}正在卸载 Hysteria 2...${none}"
    echo "----------------------------------------------------------------"
    
    # 停止并禁用服务
    if systemctl is-active --quiet hysteria-server.service; then
        echo -e "${yellow}停止 Hysteria 2 服务...${none}"
        systemctl stop hysteria-server.service
    fi
    
    if systemctl is-enabled --quiet hysteria-server.service 2>/dev/null; then
        echo -e "${yellow}禁用 Hysteria 2 服务...${none}"
        systemctl disable hysteria-server.service
    fi
    
    # 删除服务文件
    if [ -f /etc/systemd/system/hysteria-server.service ]; then
        echo -e "${yellow}删除服务文件...${none}"
        rm -f /etc/systemd/system/hysteria-server.service
    fi
    
    # 删除配置文件
    if [ -d /etc/hysteria ]; then
        echo -e "${yellow}删除配置文件目录...${none}"
        rm -rf /etc/hysteria
    fi
    
    # 删除证书文件
    cert_dir="/etc/ssl/private"
    if [ -f "${cert_dir}/learn.microsoft.com.key" ] || [ -f "${cert_dir}/learn.microsoft.com.crt" ]; then
        echo -e "${yellow}删除证书文件...${none}"
        rm -f ${cert_dir}/learn.microsoft.com.*
        
        # 如果证书目录为空，删除目录
        if [ -d "${cert_dir}" ] && [ -z "$(ls -A ${cert_dir})" ]; then
            rmdir ${cert_dir}
        fi
    fi
    
    # 检查并删除其他可能存在的证书文件
    if ls ${cert_dir}/*.key 1>/dev/null 2>&1 || ls ${cert_dir}/*.crt 1>/dev/null 2>&1; then
        echo -e "${yellow}删除其他证书文件...${none}"
        rm -f ${cert_dir}/*.key ${cert_dir}/*.crt
    fi
    
    # 删除日志文件
    if [ -f /var/log/hysteria.log ]; then
        echo -e "${yellow}删除日志文件...${none}"
        rm -f /var/log/hysteria.log
    fi
    
    # 删除二进制文件
    if [ -f /usr/local/bin/hysteria ]; then
        echo -e "${yellow}删除 Hysteria 二进制文件...${none}"
        rm -f /usr/local/bin/hysteria
    fi
    
    # 删除 URL 文件
    if [ -f ~/_hy2_url_ ]; then
        echo -e "${yellow}删除节点信息文件...${none}"
        rm -f ~/_hy2_url_
    fi
    
    # 重新加载 systemd
    echo -e "${yellow}重新加载 systemd 守护进程...${none}"
    systemctl daemon-reload
    
    # 检查是否完全卸载
    echo
    echo -e "${green}Hysteria 2 卸载完成！${none}"
    echo "已删除的文件和目录："
    echo "1. 服务文件: /etc/systemd/system/hysteria-server.service"
    echo "2. 配置目录: /etc/hysteria/"
    echo "3. 证书文件: /etc/ssl/private/learn.microsoft.com.*"
    echo "4. 二进制文件: /usr/local/bin/hysteria"
    echo "5. 日志文件: /var/log/hysteria.log"
    echo "6. 节点信息: ~/_hy2_url_"
    echo
    echo -e "${yellow}注意：此卸载过程不会删除通过 apt 安装的依赖包（如curl、wget、openssl等）${none}"
    echo -e "${yellow}如需完全清理，请手动运行: apt autoremove -y${none}"
}

# 自动安装函数
auto_install() {
    echo
    echo -e "${yellow}开始自动安装 Hysteria 2...${none}"
    echo "----------------------------------------------------------------"
    
    # 准备工作
    apt update
    apt install -y curl wget openssl qrencode net-tools lsof -qq
    
    # 获取本机IP
    InFaces=($(ls /sys/class/net/ | grep -E '^(eth|ens|eno|esp|enp|venet|vif)'))
    
    ip=""
    for i in "${InFaces[@]}"; do
        Public_IPv4=$(curl -4s --interface "$i" -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
        if [[ -n "$Public_IPv4" ]]; then
            ip=${Public_IPv4}
            netstack=4
            break
        fi
    done
    
    if [[ -z "$ip" ]]; then
        for i in "${InFaces[@]}"; do
            Public_IPv6=$(curl -6s --interface "$i" -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
            if [[ -n "$Public_IPv6" ]]; then
                ip=${Public_IPv6}
                netstack=6
                break
            fi
        done
    fi
    
    if [[ -z "$ip" ]]; then
        echo -e "${red}无法获取本机IP地址，请检查网络连接${none}"
        exit 1
    fi
    
    # 固定参数
    port=3777
    domain="learn.microsoft.com"
    pwd="6798d376-e9d4-90c8-123c-437b6856e8bf"  # 固定UUID
    alias_name="hy2"   # 固定别名
    
    echo -e "${yellow}自动配置参数：${none}"
    echo -e "  IP: ${cyan}${ip}${none}"
    echo -e "  端口: ${cyan}${port}${none}"
    echo -e "  密码(UUID): ${cyan}${pwd}${none}"
    echo -e "  别名: ${cyan}${alias_name}${none}"
    echo -e "  证书域名: ${cyan}${domain}${none}"
    echo "----------------------------------------------------------------"
    
    # Hy2官方脚本 安装最新版本
    echo
    echo -e "${yellow}安装 Hysteria 2...${none}"
    echo "----------------------------------------------------------------"
    bash <(curl -fsSL https://get.hy2.sh/) > /dev/null 2>&1
    
    systemctl start hysteria-server.service
    systemctl enable hysteria-server.service
    
    # 生成证书
    echo -e "${yellow}生成证书...${none}"
    cert_dir="/etc/ssl/private"
    mkdir -p ${cert_dir}
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "${cert_dir}/${domain}.key" -out "${cert_dir}/${domain}.crt" -subj "/CN=${domain}" -days 36500 > /dev/null 2>&1
    chmod -R 777 ${cert_dir}
    
    # 生成 pinSHA256
    pinsha256_cert=$(openssl x509 -in "${cert_dir}/${domain}.crt" -outform DER | sha256sum | awk '{print $1}')
    
    # 配置 /etc/hysteria/config.yaml
    echo -e "${yellow}配置 Hysteria 2...${none}"
    cat >/etc/hysteria/config.yaml <<-EOF
listen: :${port}     # 工作端口

tls:
  cert: ${cert_dir}/${domain}.crt    # 证书路径
  key: ${cert_dir}/${domain}.key     # 证书路径
auth:
  type: password
  password: ${pwd}    # 密码

ignoreClientBandwidth: true

acl:
  inline:
    # 如果你想利用 *ray 的分流规则, 那么在hy2自己的分流规则里面设置全部走socks5出去, 将下面一行的注释取消
    # - s5_outbound(all)

outbounds:
  # 没有分流规则, 默认生效第一个出站 直接出站
  - name: direct_outbound
    type: direct
  # 如果你想利用 *ray 的分流规则, 那么在hy2自己的分流规则里面设置全部走socks5出去
  - name: s5_outbound
    type: socks5
    socks5:
      addr: 127.0.0.1:1080

EOF
    
    # 重启 Hy2
    echo -e "${yellow}重启 Hysteria 2 服务...${none}"
    service hysteria-server restart > /dev/null 2>&1
    
    # 生成链接
    if [[ $netstack == "6" ]]; then
        ip="[${ip}]"
    fi
    hy2_url="hysteria2://${pwd}@${ip}:${port}?alpn=h3&insecure=1&pinSHA256=${pinsha256_cert}#${alias_name}"
    
    echo
    echo "---------- Hysteria 2 客户端配置信息 ----------"
    echo -e "$yellow 地址 (Address) = $cyan${ip}$none"
    echo -e "$yellow 端口 (Port) = ${cyan}${port}${none}"
    echo -e "$yellow 密码 (Password) = ${cyan}${pwd}${none}"
    echo -e "$yellow 传输层安全 (TLS) = ${cyan}tls${none}"
    echo -e "$yellow 应用层协议协商 (Alpn) = ${cyan}h3${none}"
    echo -e "$yellow 跳过证书验证 (allowInsecure) = ${cyan}true${none}"
    echo
    echo "---------- 链接 URL ----------"
    echo -e "${cyan}${hy2_url}${none}"
    echo
    echo "---------- END -------------"
    echo "以上节点信息保存在 ~/_hy2_url_ 中"
    
    # 节点信息保存到文件中
    echo $hy2_url > ~/_hy2_url_
    
    echo
    echo -e "${green}自动安装完成！${none}"
}

# 交互式安装函数
interactive_install() {
    echo
    echo -e "${yellow}开始交互式安装 Hysteria 2...${none}"
    echo "----------------------------------------------------------------"
    
    # 准备工作
    apt update
    apt install -y curl wget openssl qrencode net-tools lsof
    
    # 获取本机IP
    InFaces=($(ls /sys/class/net/ | grep -E '^(eth|ens|eno|esp|enp|venet|vif)'))
    
    IPv4=""
    IPv6=""
    for i in "${InFaces[@]}"; do
        Public_IPv4=$(curl -4s --interface "$i" -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")
        Public_IPv6=$(curl -6s --interface "$i" -m 2 https://www.cloudflare.com/cdn-cgi/trace | grep -oP "ip=\K.*$")

        if [[ -n "$Public_IPv4" ]]; then
            IPv4="$Public_IPv4"
        fi
        if [[ -n "$Public_IPv6" ]]; then
            IPv6="$Public_IPv6"
        fi
    done
    
    # 询问网络栈
    echo
    if [[ -n "$IPv4" ]] && [[ -n "$IPv6" ]]; then
        echo -e "检测到双栈服务器 (IPv4: ${cyan}${IPv4}${none}, IPv6: ${cyan}${IPv6}${none})"
        echo -e "请选择 Hysteria 2 监听的网络栈："
        echo -e "  ${green}1.${none} IPv4 (${IPv4})"
        echo -e "  ${green}2.${none} IPv6 (${IPv6})"
        read -p "请选择 [1-2] (默认: 1): " netstack_choice
        
        if [[ "$netstack_choice" == "2" ]]; then
            netstack=6
            ip=${IPv6}
        else
            netstack=4
            ip=${IPv4}
        fi
    elif [[ -n "$IPv4" ]]; then
        echo -e "检测到 IPv4 服务器: ${cyan}${IPv4}${none}"
        netstack=4
        ip=${IPv4}
    elif [[ -n "$IPv6" ]]; then
        echo -e "检测到 IPv6 服务器: ${cyan}${IPv6}${none}"
        netstack=6
        ip=${IPv6}
    else
        echo -e "${red}无法获取本机IP地址，请检查网络连接${none}"
        exit 1
    fi
    
    # 询问端口
    echo
    default_port=3777
    read -p "$(echo -e "请输入端口 [${magenta}1-65535${none}] (默认: ${cyan}${default_port}${none}): ")" port
    [ -z "$port" ] && port=$default_port
    
    # 询问密码
    echo
    read -p "$(echo -e "请输入密码 (默认UUID: ${cyan}6798d376-e9d4-90c8-123c-437b6856e8bf${none}): ")" pwd
    [ -z "$pwd" ] && pwd="6798d376-e9d4-90c8-123c-437b6856e8bf"
    
    # 询问别名
    echo
    read -p "$(echo -e "请输入别名 (默认: ${cyan}hy2${none}): ")" alias_name
    [ -z "$alias_name" ] && alias_name="hy2"
    
    # 询问证书域名
    echo
    read -p "$(echo -e "请输入证书域名 (默认: ${cyan}learn.microsoft.com${none}): ")" domain
    [ -z "$domain" ] && domain="learn.microsoft.com"
    
    # 显示配置
    echo
    echo -e "${green}配置确认：${none}"
    echo -e "  网络栈: ${cyan}IPv${netstack}${none}"
    echo -e "  IP地址: ${cyan}${ip}${none}"
    echo -e "  端口: ${cyan}${port}${none}"
    echo -e "  密码: ${cyan}${pwd}${none}"
    echo -e "  别名: ${cyan}${alias_name}${none}"
    echo -e "  证书域名: ${cyan}${domain}${none}"
    echo "----------------------------------------------------------------"
    
    pause
    
    # Hy2官方脚本 安装最新版本
    echo
    echo -e "${yellow}安装 Hysteria 2...${none}"
    echo "----------------------------------------------------------------"
    bash <(curl -fsSL https://get.hy2.sh/)
    
    systemctl start hysteria-server.service
    systemctl enable hysteria-server.service
    
    # 生成证书
    echo -e "${yellow}生成证书...${none}"
    cert_dir="/etc/ssl/private"
    mkdir -p ${cert_dir}
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "${cert_dir}/${domain}.key" -out "${cert_dir}/${domain}.crt" -subj "/CN=${domain}" -days 36500
    chmod -R 777 ${cert_dir}
    
    # 生成 pinSHA256
    pinsha256_cert=$(openssl x509 -in "${cert_dir}/${domain}.crt" -outform DER | sha256sum | awk '{print $1}')
    
    # 配置 /etc/hysteria/config.yaml
    echo -e "${yellow}配置 Hysteria 2...${none}"
    cat >/etc/hysteria/config.yaml <<-EOF
listen: :${port}     # 工作端口

tls:
  cert: ${cert_dir}/${domain}.crt    # 证书路径
  key: ${cert_dir}/${domain}.key     # 证书路径
auth:
  type: password
  password: ${pwd}    # 密码

ignoreClientBandwidth: true

acl:
  inline:
    # 如果你想利用 *ray 的分流规则, 那么在hy2自己的分流规则里面设置全部走socks5出去, 将下面一行的注释取消
    # - s5_outbound(all)

outbounds:
  # 没有分流规则, 默认生效第一个出站 直接出站
  - name: direct_outbound
    type: direct
  # 如果你想利用 *ray 的分流规则, 那么在hy2自己的分流规则里面设置全部走socks5出去
  - name: s5_outbound
    type: socks5
    socks5:
      addr: 127.0.0.1:1080

EOF
    
    # 重启 Hy2
    echo -e "${yellow}重启 Hysteria 2 服务...${none}"
    service hysteria-server restart
    
    # 生成链接
    if [[ $netstack == "6" ]]; then
        ip="[${ip}]"
    fi
    hy2_url="hysteria2://${pwd}@${ip}:${port}?alpn=h3&insecure=1&pinSHA256=${pinsha256_cert}#${alias_name}"
    
    echo
    echo "---------- Hysteria 2 客户端配置信息 ----------"
    echo -e "$yellow 地址 (Address) = $cyan${ip}$none"
    echo -e "$yellow 端口 (Port) = ${cyan}${port}${none}"
    echo -e "$yellow 密码 (Password) = ${cyan}${pwd}${none}"
    echo -e "$yellow 传输层安全 (TLS) = ${cyan}tls${none}"
    echo -e "$yellow 应用层协议协商 (Alpn) = ${cyan}h3${none}"
    echo -e "$yellow 跳过证书验证 (allowInsecure) = ${cyan}true${none}"
    echo
    echo "---------- 链接 URL ----------"
    echo -e "${cyan}${hy2_url}${none}"
    echo
    echo "---------- END -------------"
    echo "以上节点信息保存在 ~/_hy2_url_ 中"
    
    # 节点信息保存到文件中
    echo $hy2_url > ~/_hy2_url_
}

# 主菜单
main() {
    echo
    echo -e "${cyan}=== Hysteria 2 一键安装脚本 ===${none}"
    echo
    echo -e "${green}1.${none} 全自动安装 (使用默认参数)"
    echo -e "${yellow}2.${none} 交互式安装 (自定义参数)"
    echo -e "${red}3.${none} 卸载 Hysteria 2"
    echo -e "${magenta}4.${none} 退出"
    echo
    read -p "请选择操作 [1-4]: " choice
    
    case $choice in
    1)
        auto_install
        ;;
    2)
        interactive_install
        ;;
    3)
        echo
        echo -e "${red}警告：这将完全删除 Hysteria 2 及其所有配置文件！${none}"
        echo -e "${yellow}你确定要卸载 Hysteria 2 吗？(y/n): ${none}" 
        read -p "" confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            uninstall_hysteria
        else
            echo -e "${yellow}卸载已取消${none}"
        fi
        ;;
    4)
        echo -e "${yellow}退出脚本${none}"
        exit 0
        ;;
    *)
        echo -e "${red}无效选择，请重新运行脚本${none}"
        exit 1
        ;;
    esac
}

# 检查命令行参数
case "$1" in
"auto"|"1"|"--auto")
    auto_install
    ;;
"interactive"|"2"|"--interactive")
    interactive_install
    ;;
"uninstall"|"remove"|"3"|"--uninstall"|"--remove")
    uninstall_hysteria
    ;;
"help"|"-h"|"--help")
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  auto, 1, --auto        全自动安装 (使用默认参数)"
    echo "  interactive, 2, --interactive 交互式安装 (自定义参数)"
    echo "  uninstall, remove, 3, --uninstall, --remove 卸载 Hysteria 2"
    echo "  help, -h, --help       显示此帮助信息"
    echo ""
    echo "默认参数:"
    echo "  密码(UUID): 6798d376-e9d4-90c8-123c-437b6856e8bf"
    echo "  别名: hy2"
    echo "  端口: 3777"
    echo "  证书域名: learn.microsoft.com"
    exit 0
    ;;
*)
    # 启动主菜单
    main
    ;;
esac