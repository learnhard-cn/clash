#!/bin/sh
#########################################################
# Clash Process Control script for AM380 merlin firmware
# Writen by vxiaov (next4nextjob(at)gmail.com)
# Website: https://vlike.work
#########################################################

KSHOME="/koolshare"
app_name="clash"

source ${KSHOME}/scripts/base.sh

# 配置文件根目录(如果希望使用最新版Clash，这是必要的，因为默认的/koolshare/分区为jffs2类型，不支持 mmap操作，结果就是无法缓存上次选择的节点，每次重启服务后都需要重新设置) #
CONFIG_HOME="$KSHOME/${app_name}"

# 路由器IP地址
lan_ipaddr="$(nvram get lan_ipaddr)"
wan_ipaddr=$(nvram get wan0_ipaddr)
dbus set clash_lan_ipaddr=$lan_ipaddr

eval $(dbus export ${app_name}_)

alias curl="curl --connect-timeout 300"

if [ "$clash_ipv6_mode" = "on" ] ; then
    CURL_OPTS=" -4L "
else
    CURL_OPTS=" -L "
fi

dns_port="1053"         # Clash DNS端口
redir_port="3333"       # Clash 透明代理端口
tproxy_port="3330"      # TPROXY 透明代理端口，支持TCP/UDP
tproxy_mark="0x99"      # TPROXY 数据包标记
yacd_port="9090"        # Yacd 端口
# 存放规则文件目录#
rule_src_dir="${CONFIG_HOME}/ruleset"
config_file="${CONFIG_HOME}/config.yaml"
temp_provider_file="/tmp/clash_provider.yaml"

debug_log=/tmp/upload/clash_debug.log
# 备份数据文件(包括:providers/rules/config.yaml)
backup_file=/tmp/upload/${app_name}_backup.tar.gz
env_file="${app_name}_env.sh"


# 开启对旁路由IP自动化监控脚本

main_script="${KSHOME}/scripts/clash_control.sh"

# 可执行程序变量 #
YQ=${CONFIG_HOME}/bin/yq
JQ=${CONFIG_HOME}/bin/jq
BINFILE=${CONFIG_HOME}/bin/${app_name}
PARAMS="-d ${CONFIG_HOME}"
CMD="${BINFILE} ${PARAMS}"

cron_id="clash_daemon"             # 调度ID,用来查询和删除操作标识
FW_TYPE_CODE=""     # 固件类型代码
FW_TYPE_NAME=""     # 固件类型名称

tmode_list="NAT"  # 支持的透明代理模式列表
# 检测是否支持TUN设备 #
support_tun() {
    [[ -r /dev/net/tun ]] || [[ -r /dev/tun ]]
}

check_config_file() {
    # 检查 config.yaml 文件配置信息
    # 修改UI控制参数
    # 修改代理端口 redir-port 和 tproxy-port
    # 修改 是否可以使用 tun模式
    [[ "$clash_config_filepath" == "" ]] && clash_config_filepath="config/config_default.yaml" && dbus set clash_config_filepath="$clash_config_filepath"

    # clash_tmode支持检测
    # TUN模式：不适合在路由器上使用，暂时屏蔽#
    # support_tun && tmode_list="$tmode_list TUN"
    modprobe xt_TPROXY >/dev/null 2>&1 && tmode_list="$tmode_list TPROXY TPROXY+NAT"

    # tun_exp=".tun.enable=false|" # 默认不支持TUN，不填写任何修改表达式 #
    # [[ "$clash_tmode" = "TUN" ]] && tun_exp=".tun.enable=true|"

    [[ "$clash_tmode" == "" ]] && dbus set clash_tmode="NAT"

    tmode_exp=""
    [[ "${clash_tmode:0:6}" == "TPROXY" ]] && tmode_exp=".routing-mark=env(tproxy_mark)|.tproxy-port=env(tport)|"
    [[ "$clash_ipv6_mode" == "" ]] && dbus set clash_ipv6_mode="off"      # 默认关闭IPv6模式
    ipv6_expr=".ipv6=false|.dns.ipv6=false|.bind-address=\"*\"|"
    [[ "$clash_ipv6_mode" == "on" ]] && ipv6_expr=".ipv6=true|.dns.ipv6=true|.bind-address=\"*\"|"

    yq_expr=${tmode_exp}${ipv6_expr}'.redir-port=env(tmp_port)|.dns.listen=strenv(tmp_dns)|.external-controller=strenv(tmp_yacd)|.external-ui=strenv(dashboard)|.allow-lan=true'
    
    # 生成当前工作的配置文件
    tmp_yacd="${lan_ipaddr}:$yacd_port" tmp_dns="0.0.0.0:$dns_port" tport=$tproxy_port tproxy_mark=$tproxy_mark tmp_port=$redir_port dashboard="${CONFIG_HOME}/dashboard" ${YQ} e "$yq_expr" ${CONFIG_HOME}/$clash_config_filepath > $config_file
    [[ "$?" != "0" ]] && LOGGER "生成Clash启动配置文件失败!请检查Yaml格式！" && return 1


    [[ "$clash_geoip_url" == "" ]] && dbus set clash_geoip_url="https://cdn.jsdelivr.net/gh/alecthw/mmdb_china_ip_list@release/Country.mmdb"
    [[ "$clash_trans" == "" ]] && dbus set clash_trans="on"           # 默认开启透明代理模式

    dbus set clash_tmode_list=$tmode_list

    # 设置默认的Clash内核 #
    [[ "$clash_core_current" == "" ]] && dbus set clash_core_current="clash_for_arm64"
    [[ "$clash_core_list" == "" ]] && list_clash_core

    # 编辑文件没指定或文件不存在则获取默认值 #
    [[ "$clash_edit_filepath" == "" || ! -f "${CONFIG_HOME}/$clash_edit_filepath" ]] && dbus set clash_edit_filepath="$clash_config_filepath"
    clash_yacd_secret=$(${YQ} e '.secret' $config_file)
    clash_yacd_ui="http://${lan_ipaddr}:${yacd_port}/ui/yacd/?hostname=${lan_ipaddr}&port=${yacd_port}&secret=$clash_yacd_secret"
    dbus set clash_yacd_ui=$clash_yacd_ui
}

LOGGER() {
    echo -e "$(date +'%Y年%m月%d日%H:%M:%S'): $@"
}

SYSLOG() {
    logger -t "$(date +'%Y年%m月%d日%H:%M:%S'):clash" "$@"
}
if [ "$lan_ipaddr" = "" ]; then
    LOGGER "真糟糕! nvram 命令没找到局域网路由器地址，这样防火墙规则配置不了啦!还是自己手动设置后再执行吧!"
    echo "XU6J03M6"
    exit 1
fi
# 检测是否有 cru 命令
if [ ! -x "$(which cru)" ]; then
    if [ -x "$(which cru.sh)" ]; then
        alias cru="cru.sh"
    else
        LOGGER "糟糕!没有找到 cru 命令! 这样配置不了调度啦!"
    fi
fi

echo_status() {
    if [ "$1" = "head" ]; then
        printf "%-20s %-20s %-s" "进程名称" "进程号" "运行状态"
        return 0
    fi
    pids=$(pidof $1)
    if [ "$pids" == "" ]; then
        printf "%-15s %-15s %-s" "$1" "$pids" "已停止."
    else
        printf "%-15s %-15s %-s" "$1" "$pids" "正常运行中."
    fi
}


get_arch() {
    # 暂时支持ARM芯片吧，等手里有 MIPS 芯片再适配
    case $(uname -m) in
        armv7l)
            if grep -i vfpv3 /proc/cpuinfo >/dev/null 2>&1; then
                ARCH="armv7"
            else
                ARCH="armv5"
            fi
            ;;
        aarch64)
            # ARCH="armv8"
            ARCH="arm64"        # 更新aarch64架构名称，由 armv8 改为 arm64 架构,2022/12/12
            ;;
        *)
            LOGGER "糟糕!平台类型不支持呀!赶紧通知开发者适配!或者自己动手丰衣足食!"
            echo "XU6J03M6"
            exit 0
            ;;
    esac
    echo "$ARCH"
}

get_proc_status() {
    
    free_mem="$(free | grep Mem | awk '{printf("%.02f MB", $4/1024);}')"
    total_mem="$(free | grep Mem | awk '{printf("%.02f MB", $2/1024);}')"
    echo "+----------[ 服务信息: ${clash_rule_mode} ]--------------------------------"
    echo "| $(echo_status head)"
    echo "| $(echo_status $app_name)"
    if [ "$(pidof $app_name)" != "" ]; then
        clash_use_mem="$(cat /proc/$(pidof ${app_name})/status | grep VmRSS | awk '{printf("%.02f MB", $2/1024);}')"
        echo "| Clash占用内存: $clash_use_mem, 系统剩余内存: $free_mem, 系统总内存: $total_mem"
    fi
    echo "+----------[ 调度信息 ]--------------------------------"
    tmp_cron=$(cru l| grep ${cron_id})
    if [ "$tmp_cron" != "" ]; then
        echo "|  $tmp_cron"
    fi

    echo "+---------------------------------------------------"
    echo "| Clash重启信息: [$(grep 'clash 服务启动' /tmp/syslog.log|wc -l)] 次, 最近 [3次] 时间如下:"
    echo "$(grep 'clash 服务启动' /tmp/syslog.log|tail -3| awk '{printf("| %s\n", $0);}')"
    echo "+---------------------------------------------------"
}


# 添加守护监控脚本
add_cron() {
    if cru l | grep ${cron_id} >/dev/null; then
        LOGGER "进程守护脚本已经添加!不需要重复添加吧？!？"
        return 0
    fi

    cru a "${cron_id}" "*/5 * * * * $main_script start"
    if cru l | grep ${cron_id} >/dev/null; then
        LOGGER "添加进程守护脚本成功!"
    else
        LOGGER "不知道啥原因，守护脚本没添加到调度里!赶紧查查吧!"
        return 1
    fi
}

# 删除守护监控脚本
del_cron() {
    cru d "${cron_id}"
    LOGGER "删除进程守护脚本成功!"
}


create_ipset() {
    # 创建 ipset 表
    tname="localnet4"

    # 防止重复创建ipset #
    if ipset test $tname 127.0.0.1/8  > /dev/null 2>&1 ; then
        return
    fi
    LOGGER "开始创建 ipset: $tname"
    ipset -! destroy $tname > /dev/null 2>&1
    ipset create $tname hash:net family inet hashsize 1024 maxelem 65536
    ipset add $tname  127.0.0.1/8
    ipset add $tname  10.0.0.0/8
    ipset add $tname  169.254.0.0/16
    ipset add $tname  172.16.0.0/12
    ipset add $tname  192.168.0.0/16
    ipset add $tname  224.0.0.0/4
    ipset add $tname  255.255.255.255/32

    tname="localnet6"
    LOGGER "开始创建 ipset: $tname"
    ipset -! destroy $tname > /dev/null 2>&1
    ipset create $tname hash:net family inet6 hashsize 1024 maxelem 65536
    ipset add $tname  ::1/128
    ipset add $tname  fc00::/7   #本地链路专用网络
    ipset add $tname  240e::/16   #电信IPv6地址段
    ipset add $tname  2408::/16   #联通IPv6地址段
    ipset add $tname  2409::/16   #移动IPv6地址段
}

del_iptables_tproxy() {

    # 设置策略路由 v4
    ip rule del fwmark 1 table 100
    ip route del local 0.0.0.0/0 dev lo table 100

    # 设置策略路由 v6
    ip -6 rule del fwmark 1 table 106
    ip -6 route del local ::/0 dev lo table 106

    # 代理局域网设备 v4
    iptables -t mangle -D PREROUTING -p udp -j ${app_name}_XRAY
    iptables -t mangle -D PREROUTING -p tcp -j ${app_name}_XRAY
    iptables -t mangle -F ${app_name}_XRAY
    iptables -t mangle -X ${app_name}_XRAY

    # 代理局域网设备 v6
    ip6tables -t mangle -D PREROUTING -p udp -j ${app_name}_XRAY6
    ip6tables -t mangle -D PREROUTING -p tcp -j ${app_name}_XRAY6
    ip6tables -t mangle -F ${app_name}_XRAY6
    ip6tables -t mangle -X ${app_name}_XRAY6

    # 代理网关本机 v4
    iptables -t mangle -D OUTPUT -p udp -j ${app_name}_XRAY_MASK
    iptables -t mangle -D OUTPUT -p tcp -j ${app_name}_XRAY_MASK
    iptables -t mangle -F ${app_name}_XRAY_MASK
    iptables -t mangle -X ${app_name}_XRAY_MASK

    # 代理网关本机 v6
    ip6tables -t mangle -D OUTPUT -p udp -j ${app_name}_XRAY6_MASK
    ip6tables -t mangle -D OUTPUT -p tcp -j ${app_name}_XRAY6_MASK
    ip6tables -t mangle -F ${app_name}_XRAY6_MASK
    ip6tables -t mangle -X ${app_name}_XRAY6_MASK

    # 新建 ${app_name}_DIVERT 规则，避免已有连接的包二次通过 TPROXY，理论上有一定的性能提升
    iptables -t mangle -D PREROUTING -p udp -m socket -j ${app_name}_DIVERT
    iptables -t mangle -D PREROUTING -p tcp -m socket -j ${app_name}_DIVERT
    iptables -t mangle -F ${app_name}_DIVERT
    iptables -t mangle -X ${app_name}_DIVERT

    ip6tables -t mangle -D PREROUTING -p udp -m socket -j ${app_name}_DIVERT
    ip6tables -t mangle -D PREROUTING -p tcp -m socket -j ${app_name}_DIVERT
    ip6tables -t mangle -F ${app_name}_DIVERT
    ip6tables -t mangle -X ${app_name}_DIVERT

    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports $dns_port
    iptables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $dns_port

}

check_iptables_tproxy() {
    iptables -t mangle -C ${app_name}_DIVERT -j MARK --set-mark 1 2>/dev/null || return 1
    iptables -t mangle -C ${app_name}_XRAY -j RETURN -m mark --mark ${tproxy_mark} 2>/dev/null || return 1
    iptables -t mangle -C ${app_name}_XRAY_MASK -j RETURN -m mark --mark ${tproxy_mark} 2>/dev/null || return 1
}
# TPROXY模式（TCP+UDP）
add_iptables_tproxy() {

    if check_iptables_tproxy ; then
        LOGGER "已经配置过 TPROXY透明代理模式 的iptables 规则."
        return 0
    fi
    # 设置策略路由 v4
    ip rule add fwmark 1 table 100
    ip route add local 0.0.0.0/0 dev lo table 100

    # 新建 ${app_name}_DIVERT 规则，避免已有连接的包二次通过 TPROXY，理论上有一定的性能提升
    iptables -t mangle -N ${app_name}_DIVERT
    iptables -t mangle -F ${app_name}_DIVERT
    iptables -t mangle -A ${app_name}_DIVERT -j MARK --set-mark 1
    iptables -t mangle -A ${app_name}_DIVERT -j ACCEPT
    iptables -t mangle -A PREROUTING -p udp -m socket -j ${app_name}_DIVERT
    iptables -t mangle -A PREROUTING -p tcp -m socket -j ${app_name}_DIVERT

    # 代理局域网设备 v4
    ! iptables -t mangle -N ${app_name}_XRAY && LOGGER "${app_name}_XRAY 表已经创建过，清理后再执行"
    iptables -t mangle -F ${app_name}_XRAY
    iptables -t mangle -A ${app_name}_XRAY -m set --match-set localnet4 dst -j RETURN
    iptables -t mangle -A ${app_name}_XRAY -j RETURN -m mark --mark ${tproxy_mark}
    iptables -t mangle -A ${app_name}_XRAY -p udp -j TPROXY --on-ip 127.0.0.1 --on-port ${tproxy_port} --tproxy-mark 1
    iptables -t mangle -A ${app_name}_XRAY -p tcp -j TPROXY --on-ip 127.0.0.1 --on-port ${tproxy_port} --tproxy-mark 1
    iptables -t mangle -A PREROUTING -p udp -j ${app_name}_XRAY
    iptables -t mangle -A PREROUTING -p tcp -j ${app_name}_XRAY

    # 代理网关本机 v4
    iptables -t mangle -N ${app_name}_XRAY_MASK
    iptables -t mangle -A ${app_name}_XRAY_MASK -m set --match-set localnet4 dst -j RETURN
    iptables -t mangle -A ${app_name}_XRAY_MASK -j RETURN -m mark --mark ${tproxy_mark}
    iptables -t mangle -A ${app_name}_XRAY_MASK -p udp -j MARK --set-mark 1
    iptables -t mangle -A ${app_name}_XRAY_MASK -p tcp -j MARK --set-mark 1
    iptables -t mangle -A OUTPUT -p udp -j ${app_name}_XRAY_MASK
    iptables -t mangle -A OUTPUT -p tcp -j ${app_name}_XRAY_MASK


    if [ "$clash_ipv6_mode" = "on" ] ; then
        # 设置策略路由 v6
        ip -6 rule add fwmark 1 table 106
        ip -6 route add local ::/0 dev lo table 106

        # 新建 ${app_name}_DIVERT 规则，避免已有连接的包二次通过 TPROXY，理论上有一定的性能提升
        ip6tables -t mangle -N ${app_name}_DIVERT
        ip6tables -t mangle -F ${app_name}_DIVERT
        ip6tables -t mangle -A ${app_name}_DIVERT -j MARK --set-mark 1
        ip6tables -t mangle -A ${app_name}_DIVERT -j ACCEPT
        ip6tables -t mangle -A PREROUTING -p udp -m socket -j ${app_name}_DIVERT
        ip6tables -t mangle -A PREROUTING -p tcp -m socket -j ${app_name}_DIVERT

        # # 代理局域网设备 v6
        ip6tables -t mangle -N ${app_name}_XRAY6
        ip6tables -t mangle -F ${app_name}_XRAY6
        ip6tables -t mangle -A ${app_name}_XRAY6 -m set --match-set localnet6 dst -j RETURN
        ip6tables -t mangle -A ${app_name}_XRAY6 -j RETURN -m mark --mark ${tproxy_mark}
        ip6tables -t mangle -A ${app_name}_XRAY6 -p udp -j TPROXY --on-ip ::1 --on-port ${tproxy_port} --tproxy-mark 1
        ip6tables -t mangle -A ${app_name}_XRAY6 -p tcp -j TPROXY --on-ip ::1 --on-port ${tproxy_port} --tproxy-mark 1
        ip6tables -t mangle -A PREROUTING -p udp -j ${app_name}_XRAY6
        ip6tables -t mangle -A PREROUTING -p tcp -j ${app_name}_XRAY6

        # # 代理网关本机 v6
        ip6tables -t mangle -N ${app_name}_XRAY6_MASK
        ip6tables -t mangle -A ${app_name}_XRAY6_MASK -m set --match-set localnet6 dst -j RETURN
        ip6tables -t mangle -A ${app_name}_XRAY6_MASK -j RETURN -m mark --mark ${tproxy_mark}
        ip6tables -t mangle -A ${app_name}_XRAY6_MASK -p udp -j MARK --set-mark 1
        ip6tables -t mangle -A ${app_name}_XRAY6_MASK -p tcp -j MARK --set-mark 1
        ip6tables -t mangle -A OUTPUT -p udp -j ${app_name}_XRAY6_MASK
        ip6tables -t mangle -A OUTPUT -p tcp -j ${app_name}_XRAY6_MASK
    fi
}

# TPROXY模式（TCP） + NAT模式转发(UDP协议的DNS服务)
add_iptables_tproxy_nat() {

    if check_iptables_tproxy ; then
        LOGGER "已经配置过 TPROXY+NAT透明代理模式 的iptables 规则."
        return 0
    fi

    # NAT转发UDP协议数据报 DNS服务#
    iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports $dns_port
    iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $dns_port

    # 设置策略路由 v4
    ip rule add fwmark 1 table 100
    ip route add local 0.0.0.0/0 dev lo table 100

    # 新建 ${app_name}_DIVERT 规则，避免已有连接的包二次通过 TPROXY，理论上有一定的性能提升
    iptables -t mangle -N ${app_name}_DIVERT
    iptables -t mangle -F ${app_name}_DIVERT
    iptables -t mangle -A ${app_name}_DIVERT -j MARK --set-mark 1
    iptables -t mangle -A ${app_name}_DIVERT -j ACCEPT
    iptables -t mangle -I PREROUTING -p udp -m socket -j ${app_name}_DIVERT
    iptables -t mangle -I PREROUTING -p tcp -m socket -j ${app_name}_DIVERT

    # 代理局域网设备 v4
    ! iptables -t mangle -N ${app_name}_XRAY && LOGGER "${app_name}_XRAY 表已经创建过，清理后再执行"
    iptables -t mangle -F ${app_name}_XRAY
    iptables -t mangle -A ${app_name}_XRAY -p udp --dport 53 -j RETURN
    iptables -t mangle -A ${app_name}_XRAY -m set --match-set localnet4 dst -j RETURN
    iptables -t mangle -A ${app_name}_XRAY -j RETURN -m mark --mark ${tproxy_mark}
    iptables -t mangle -A ${app_name}_XRAY -p udp -j TPROXY --on-ip 127.0.0.1 --on-port ${tproxy_port} --tproxy-mark 1
    iptables -t mangle -A ${app_name}_XRAY -p tcp -j TPROXY --on-ip 127.0.0.1 --on-port ${tproxy_port} --tproxy-mark 1
    iptables -t mangle -A PREROUTING -p udp -j ${app_name}_XRAY
    iptables -t mangle -A PREROUTING -p tcp -j ${app_name}_XRAY

    # 代理网关本机 v4
    iptables -t mangle -N ${app_name}_XRAY_MASK
    iptables -t mangle -A ${app_name}_XRAY_MASK -p udp --dport 53 -j RETURN
    iptables -t mangle -A ${app_name}_XRAY_MASK -m set --match-set localnet4 dst -j RETURN
    iptables -t mangle -A ${app_name}_XRAY_MASK -j RETURN -m mark --mark ${tproxy_mark}
    iptables -t mangle -A ${app_name}_XRAY_MASK -p udp -j MARK --set-mark 1
    iptables -t mangle -A ${app_name}_XRAY_MASK -p tcp -j MARK --set-mark 1
    iptables -t mangle -A OUTPUT -p udp -j ${app_name}_XRAY_MASK
    iptables -t mangle -A OUTPUT -p tcp -j ${app_name}_XRAY_MASK


    if [ "$clash_ipv6_mode" = "on" ] ; then
        # 设置策略路由 v6
        ip -6 rule add fwmark 1 table 106
        ip -6 route add local ::/0 dev lo table 106

        # 新建 ${app_name}_DIVERT 规则，避免已有连接的包二次通过 TPROXY，理论上有一定的性能提升
        ip6tables -t mangle -N ${app_name}_DIVERT
        ip6tables -t mangle -F ${app_name}_DIVERT
        ip6tables -t mangle -A ${app_name}_DIVERT -j MARK --set-mark 1
        ip6tables -t mangle -A ${app_name}_DIVERT -j ACCEPT
        ip6tables -t mangle -I PREROUTING -p udp -m socket -j ${app_name}_DIVERT
        ip6tables -t mangle -I PREROUTING -p tcp -m socket -j ${app_name}_DIVERT

        # # 代理局域网设备 v6
        ip6tables -t mangle -N ${app_name}_XRAY6
        ip6tables -t mangle -F ${app_name}_XRAY6
        ip6tables -t mangle -A ${app_name}_XRAY6 -p udp --dport 53 -j RETURN
        ip6tables -t mangle -A ${app_name}_XRAY6 -m set --match-set localnet6 dst -j RETURN
        ip6tables -t mangle -A ${app_name}_XRAY6 -j RETURN -m mark --mark ${tproxy_mark}
        ip6tables -t mangle -A ${app_name}_XRAY6 -p udp -j TPROXY --on-ip ::1 --on-port ${tproxy_port} --tproxy-mark 1
        ip6tables -t mangle -A ${app_name}_XRAY6 -p tcp -j TPROXY --on-ip ::1 --on-port ${tproxy_port} --tproxy-mark 1
        ip6tables -t mangle -A PREROUTING -p udp -j ${app_name}_XRAY6
        ip6tables -t mangle -A PREROUTING -p tcp -j ${app_name}_XRAY6

        # # 代理网关本机 v6
        ip6tables -t mangle -N ${app_name}_XRAY6_MASK
        ip6tables -t mangle -A ${app_name}_XRAY6_MASK -p udp --dport 53 -j RETURN
        ip6tables -t mangle -A ${app_name}_XRAY6_MASK -m set --match-set localnet6 dst -j RETURN
        ip6tables -t mangle -A ${app_name}_XRAY6_MASK -j RETURN -m mark --mark ${tproxy_mark}
        ip6tables -t mangle -A ${app_name}_XRAY6_MASK -p udp -j MARK --set-mark 1
        ip6tables -t mangle -A ${app_name}_XRAY6_MASK -p tcp -j MARK --set-mark 1
        ip6tables -t mangle -A OUTPUT -p udp -j ${app_name}_XRAY6_MASK
        ip6tables -t mangle -A OUTPUT -p tcp -j ${app_name}_XRAY6_MASK
    fi
}

check_iptables_nat() {
    iptables -t nat -C ${app_name} -m set --match-set localnet4 dst -j RETURN 2>/dev/null || return 1
}

# 配置iptables规则
add_iptables_nat() {
    if [ "$clash_trans" = "off" ]; then
        LOGGER "透明代理模式已关闭!不需要添加iptables转发规则!"
        return 0
    fi
    if check_iptables_nat ; then
        LOGGER "已经配置过 NAT透明代理模式 的iptables规则!"
        return 0
    fi

    iptables -t nat -N ${app_name} || LOGGER "${app_name} 表已经存在！开始执行清空操作"
    iptables -t nat -F ${app_name}
    # 本地地址请求不转发
    iptables -t nat -A ${app_name} -m set --match-set localnet4 dst -j RETURN
    # 服务端口${redir_port}接管HTTP/HTTPS请求转发
    iptables -t nat -A ${app_name} -s ${lan_ipaddr}/24 -p udp -j REDIRECT --to-ports ${redir_port}
    iptables -t nat -A ${app_name} -s ${lan_ipaddr}/24 -p tcp -j REDIRECT --to-ports ${redir_port}

    # 1.局域网DNS请求走代理
    iptables -t nat -A PREROUTING -p udp -s ${lan_ipaddr}/24 --dport 53 -j REDIRECT --to-ports $dns_port
    iptables -t nat -A PREROUTING -p tcp -s ${lan_ipaddr}/24 --dport 53 -j REDIRECT --to-ports $dns_port
    # 2.代理所有TCP和UDP请求(UDP消息中排除TPROXY转发消息，暂时屏蔽UDP)
    # iptables -t nat -A PREROUTING -p udp -s ${lan_ipaddr}/24  -j ${app_name}
    iptables -t nat -A PREROUTING -p tcp -s ${lan_ipaddr}/24  -j ${app_name}

    # 3.路由器本机消息转发到代理(DNS请求和其他所有非本地请求)
    iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $dns_port
    iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $dns_port

    iptables -t nat -A OUTPUT -p udp -d 198.18.0.0/16 -j REDIRECT --to-ports ${redir_port}
    iptables -t nat -A OUTPUT -p tcp -d 198.18.0.0/16 -j REDIRECT --to-ports ${redir_port}
    
    LOGGER "完成添加 iptables NAT 配置"

}

# 清理iptables规则
del_iptables_nat() {

    # 1.局域网DNS请求走代理
    iptables -t nat -D PREROUTING -p udp -s ${lan_ipaddr}/24 --dport 53 -j REDIRECT --to-ports $dns_port
    iptables -t nat -D PREROUTING -p tcp -s ${lan_ipaddr}/24 --dport 53 -j REDIRECT --to-ports $dns_port
    # 2.代理所有TCP和UDP请求(UDP消息中排除TPROXY转发消息)
    # iptables -t nat -D PREROUTING -p udp -s ${lan_ipaddr}/24  -j ${app_name}
    iptables -t nat -D PREROUTING -p tcp -s ${lan_ipaddr}/24  -j ${app_name}

    # 3.路由器本机消息转发到代理(DNS请求和其他所有非本地请求)
    iptables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $dns_port
    iptables -t nat -D OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $dns_port

    iptables -t nat -D OUTPUT -p udp -d 198.18.0.0/16 -j REDIRECT --to-ports ${redir_port}
    iptables -t nat -D OUTPUT -p tcp -d 198.18.0.0/16 -j REDIRECT --to-ports ${redir_port}

    iptables -t nat -F ${app_name}
    iptables -t nat -X ${app_name}
    LOGGER "完成清理 iptables NAT 配置"
}

# 配置iptables规则
add_iptables_all() {
    # 透明代理的方案启用原则：
    #  1. 优先启用TPROXY模式
    #  2. 其次，支持的TUN模式(TODO:暂时关闭)
    #  3. 最后，使用NAT方式（不支持IPv6代理）
    if [ "$clash_trans" = "off" ]; then
        LOGGER "透明代理模式已关闭!不需要添加iptables转发规则!"
        return 0
    fi

    create_ipset

    if [ "$clash_tmode" = "TPROXY" ]; then
        # TPROXY模式透明代理 #
        modprobe xt_TPROXY && modprobe xt_socket && LOGGER "加载 xt_TPROXY 和 xt_socket 模块成功!"
        if [ "$?" = "0" ] ; then 
            # 支持 TPROXY 内核模块 #
            LOGGER "透明代理模式: $clash_tmode 模式"
            add_iptables_tproxy
            LOGGER "完成配置 ${app_name} iptables $clash_tmode 模式规则!"
            return
        fi
    elif [ "$clash_tmode" = "TPROXY+NAT" ]; then
        # TPROXY模式透明代理 #
        modprobe xt_TPROXY && modprobe xt_socket && LOGGER "加载 xt_TPROXY 和 xt_socket 模块成功!"
        if [ "$?" = "0" ] ; then 
            LOGGER "透明代理模式: TPROXY+NAT模式"
            add_iptables_tproxy_nat
            LOGGER "完成配置 ${app_name} iptables $clash_tmode 模式规则!"
            return
        fi
    elif [ "$clash_tmode" = "TUN" ] ; then
        LOGGER "透明代理模式: $clash_tmode 模式"
        add_iptables_nat
    else
        LOGGER "透明代理模式: $clash_tmode 模式"
        add_iptables_nat
    fi
    LOGGER "完成配置 ${app_name} iptables $clash_tmode 模式规则!"
}

# 清理iptables规则
del_iptables_all() {
    LOGGER "开始清理 ${app_name} iptables规则 ..."
    # 执行全部清理(这里简化处理逻辑才这样做) #
    del_iptables_nat
    del_iptables_tproxy
    LOGGER "完成清理 ${app_name} iptables规则!"
}

iptables_status() {
    echo "IPv4 地址配置 NAT 规则:"
    iptables -t nat -S | grep -E "${dns_port}|${redir_port}|${tproxy_port}|${app_name}"
    echo "+---------------------------------------------------------------+"
    echo "IPv4 地址配置 mangle 规则:"
    iptables -t mangle -S | grep -E "${dns_port}|${redir_port}|${tproxy_port}|${app_name}"
    echo "+---------------------------------------------------------------+"
    echo "IPv6 地址配置 mangle 规则:"
    ip6tables -t mangle -S | grep -E "${dns_port}|${redir_port}|${tproxy_port}|${app_name}"
}


status() {
    pidof ${app_name}
}

service_start() {
    # 1. 启动服务进程
    # 2. 配置iptables策略
    if [ "$clash_enable" = "off" ]; then
        echo "Clash开关处于关闭状态，无法启动Clash"
        return 0
    fi
    # 解决路由器刷新后，导致iptables规则丢失问题,下次启动任务时添加 #
    add_iptables_all

    if status >/dev/null 2>&1; then
        LOGGER "$app_name 正常运行中! pid=$(pidof ${app_name})"
        return 0
    fi

    check_config_file  # 检查文件比较慢
    [[ "$?" != "0" ]] && LOGGER "配置文件格式错误！修正好配置文件后再尝试启动!" && return 1

    LOGGER "启动配置文件 ${config_file} : 检测完毕!"

    switch_clash_core

    # nohup ${CMD} >/dev/null 2>&1 &   # ${BINFILE} ${PARAMS}
    start-stop-daemon -b --start -x ${BINFILE} -- ${PARAMS}
    # 节省了下面检测时间，这样会无法识别启动失败结果
    # sleep 1
    # if status >/dev/null 2>&1; then
    #     LOGGER "${CMD} 启动成功!"
    # else
    #     dbus set clash_enable="off"
    #     LOGGER "${CMD} 启动失败! 执行失败原因如下:"
    #     return 1
    # fi
    # 用于记录Clash服务稳定程度
    SYSLOG "${app_name} 服务启动成功 : pid=$(pidof ${app_name})"
    dbus set ${app_name}_enable="on"

    add_cron
    LOGGER "启动完毕!"
}

service_stop() {
    # 1. 停止服务进程
    # 2. 清理iptables策略
    #echo "停止 $app_name"
    if status >/dev/null 2>&1; then
        LOGGER "开始停止 ${app_name} ..."
        killall ${app_name}
    fi
    del_iptables_all  2>/dev/null
    #stop_dns
    del_cron
    if status >/dev/null 2>&1; then
        LOGGER "${CMD} 停止失败!"
        dbus set ${app_name}_enable="on"
    else
        LOGGER "${CMD} 停止成功!"
        dbus set ${app_name}_enable="off"
    fi
}

########## config part ###########

# 更新Country.mmdb文件
update_geoip() {
    #
    geoip_file="${CONFIG_HOME}/Country.mmdb"
    mv ${geoip_file} ${geoip_file}.bak
    # 精简中国IP列表生成MaxMind数据库: https://cdn.jsdelivr.net/gh/Hackl0us/GeoIP2-CN@release/Country.mmdb
    # 全量MaxMind数据库文件: https://cdn.jsdelivr.net/gh/Dreamacro/maxmind-geoip@release/Country.mmdb
    # 全量MaxMind数据库文件（融合了ipip.net数据）: https://cdn.jsdelivr.net/gh/alecthw/mmdb_china_ip_list@release/Country.mmdb
    # 切换使用代理dns转发

    geoip_url="https://cdn.jsdelivr.net/gh/alecthw/mmdb_china_ip_list@release/Country.mmdb"
    if [ ! -z "$clash_geoip_url" ] ; then
        geoip_uri="$clash_geoip_url"
    fi
    curl ${CURL_OPTS} -o ${geoip_file} ${geoip_uri}
    if [ "$?" != "0" ] ; then
        LOGGER "下载「$geoip_file」文件失败!"
        rm -f ${geoip_file}
        mv -f ${geoip_file}.bak ${geoip_file}
        return 1
    fi
    LOGGER "「$geoip_file」文件更新成功! 下次重启后生效!"
    LOGGER "文件大小变化[`du -h ${geoip_file}.bak|cut -f1`]=>[`du -h ${geoip_file}|cut -f1`]"
}

# 透明代理开关
switch_trans_mode(){
    LOGGER "切换透明代理模式:$clash_trans"
}

switch_ipv6_mode(){
    if [ "$clash_ipv6_mode" = "on" ] ; then
        LOGGER "开启IPv6模式..."
    else
        LOGGER "关闭IPv6模式..."
    fi
}
# 忽略clash新版本提醒
ignore_vclash_new_version() {
    dbus set clash_vclash_version=$clash_vclash_new_version
    LOGGER "已忽略当前版本:$clash_vclash_new_version"
}

md5sum_update() {
    # 如果md5sum结果不一致就更新替换文件
    old_file="$1"
    new_file="$2"
    if [ ! -f "$old_file" ] ; then
        LOGGER "文件不存在: $old_file"
        return 1
    fi
    if [ ! -f "$new_file" ] ; then
        LOGGER "文件不存在: $new_file"
        return 1
    fi
    old_md5sum="$(md5sum $old_file|cut -d' ' -f1)"
    new_md5sum="$(md5sum $new_file|cut -d' ' -f1)"
    if [ "$old_md5sum" = "$new_md5sum" ] ; then
        LOGGER "文件一致,无需更新: $old_file"
        return 0
    fi
    LOGGER "文件不一致,开始更新: $old_file"
    mv -f $old_file $old_file.bak && cp $new_file $old_file && rm -f $old_file.bak
    if [ "$?" != "0" ] ; then
        LOGGER "文件更新失败: $old_file"
        return 1
    fi
    LOGGER "文件更新成功: $old_file"
}

# 更新vclash 至最新版本
update_vclash_bin() {
    # 从github下载vclash的Release版本
    UPLOAD_DIR="/tmp/upload"
    rm -rf ${UPLOAD_DIR}/clash ${UPLOAD_DIR}/clash.tar.gz
    # 更新vclash地址
    vclash_url="https://github.com/vxiaov/vClash/raw/ksmerlin386/release/clash.tar.gz"
    LOGGER "开始下载vclash更新包..."
    LOGGER "下载地址:[$vclash_url]"
    curl -L -o ${UPLOAD_DIR}/clash.tar.gz $vclash_url
    if [ "$?" != "0" ] ; then
        LOGGER "下载vclash更新包失败!"
        return 1
    fi
    LOGGER "下载vclash更新包成功!"
    LOGGER "开始更新vclash..."
    cd ${UPLOAD_DIR}
    tar -zxf ./clash.tar.gz
    if [ "$?" != "0" ] ; then
        LOGGER "解压vclash更新包失败!"
        return 1
    fi
    LOGGER "解压vclash更新包成功!"

    # 版本判断
    vclash_new_version=`cat ./clash/clash/version| awk -F: '/vClash/{ print $2 }'`

    ARCH="`get_arch`"

    # 更新 clash_control.sh 脚本
    md5sum_update ${KSHOME}/scripts/clash_control.sh ${UPLOAD_DIR}/clash/scripts/clash_control.sh
    # 更新 Module_clash.asp 网页
    md5sum_update ${KSHOME}/webs/Module_clash.asp ${UPLOAD_DIR}/clash/webs/Module_clash.asp
    # 更新 res/clash_style.css 网页样式
    md5sum_update ${KSHOME}/res/clash_style.css ${UPLOAD_DIR}/clash/res/clash_style.css
    # 更新 res/icon-clash.png 网页图标
    md5sum_update ${KSHOME}/res/icon-clash.png ${UPLOAD_DIR}/clash/res/icon-clash.png

    # 更新配置文件（不更新配置）
    if [[ "${clash_vclash_version:1:1}" == "2" && "${clash_vclash_version:3:1}" -ge "5" ]] ; then
        LOGGER "v2.5.1 版本之后的升级过程对版本号进行规划"
        LOGGER "2: major_verison,主版本号(比如适用与不同路由器的重大差异，重写代码等会升级此版本)"
        LOGGER "5: minor_version,分支版本号，涉及新功能升级时会修改此版本号）"
        LOGGER "1: hotfix_version,功能优化等小修改的版本号, 不涉及新功能的升级)"
        LOGGER "当用户使用的版本与最新版本差异过大时，建议是重新安装，当然是可以使用升级方式。"
        LOGGER "升级过程，尽可能不破坏现有启动配置文件。"
    fi

    # 更新 version 文件
    md5sum_update ${CONFIG_HOME}/version ${UPLOAD_DIR}/clash/clash/version
    
    # 更新环境变量
    dbus set clash_vclash_new_version=$vclash_new_version
    dbus set clash_vclash_version=$vclash_new_version
    dbus set softcenter_module_clash_version=$vclash_new_version
    LOGGER "vClash更新完毕! 请刷新页面后再使用!"
    rm -rf ${UPLOAD_DIR}/clash ${UPLOAD_DIR}/clash.tar.gz
}

# 忽略clash新版本提醒
ignore_new_version() {
    dbus set clash_version=$clash_new_version
    LOGGER "已忽略当前版本:$clash_new_version"
}

# 更新新版本clash客户端可执行程序
update_clash_bin() {
    cd /tmp
    new_ver=$clash_new_version
    old_version=$clash_version
    
    # 专业版更新
    # https://hub.fastgit.org/Dreamacro/clash/releases/tag/premium
    # https://github.com/Dreamacro/clash/releases/tag/premium
    # Github更新了API调用获取release文件
    # https://github.com/Dreamacro/clash/releases/expanded_assets/premium
    # 更新URL地址
    tag_url="https://github.com/Dreamacro/clash/releases/expanded_assets/premium"
    LOGGER "CURL_OPTS:${CURL_OPTS}"
    LOGGER "正在执行命令: curl ${CURL_OPTS} $tag_url"
    ARCH="`get_arch`"
    NEW_VERSION="$(curl -sL $tag_url | grep href= | grep linux-arm64 | awk -F \" '{ print $2 }')"
    download_url="https://github.com${NEW_VERSION}"
    bin_file="new_$app_name"
    LOGGER "正在下载新版本:curl ${CURL_OPTS} -o ${bin_file}.gz $download_url"
    curl ${CURL_OPTS} -o ${bin_file}.gz $download_url && gzip -d ${bin_file}.gz && chmod +x ${bin_file} && mv ${BINFILE} ${BINFILE}.${old_version} && mv ${bin_file} ${BINFILE}
    if [ "$?" != "0" ]; then
        LOGGER "更新出现了点问题!"
        [[ -f ${BINFILE}.${old_version} ]] && mv ${BINFILE}.${old_version} ${BINFILE}
        if [ -f ${BINFILE} ]; then
            LOGGER "更新 ${BINFILE} 失败啦!"
            LOGGER 当前Clash版本信息: $(${BINFILE} -v)
            LOGGER "别急!先把更新失败原因找到再想更新的事儿吧!"
        else
            LOGGER "太牛啦!如果走到这里，说明Clash可执行程序搞的不翼而飞啦!谁吃了呢？"
        fi
        return 1
    else
        # 更新成功啦
        LOGGER "更新到新版本!"
        dbus set clash_version=$clash_new_version
        dbus remove clash_new_version
        # rm -f ${BINFILE}.${old_version}
    fi
}

get_fw_type() {
    local KS_TAG=$(nvram get extendno|grep koolshare)
    if [ -d "$KSHOME" ];then
        if [ -n "${KS_TAG}" ];then
            FW_TYPE_CODE="2"
            FW_TYPE_NAME="koolshare官改固件"
        else
            FW_TYPE_CODE="4"
            FW_TYPE_NAME="koolshare梅林改版固件"
        fi
    else
        if [ "$(uname -o|grep Merlin)" ];then
            FW_TYPE_CODE="3"
            FW_TYPE_NAME="梅林原版固件"
        else
            FW_TYPE_CODE="1"
            FW_TYPE_NAME="华硕官方固件"
        fi
    fi
}

switch_option_tab() {
    if [ "$1" == "on" ] ; then
        LOGGER "开启选项卡"
    else
        LOGGER "关闭选项卡"
    fi
}

debug_info() {
    printf "|%20s : %-40.40s|\n" "$1" "$2"
}

# DEBUG 路由器信息
show_router_info() {
    get_fw_type
    echo "您的路由器基本信息(反馈开发者帮您分析问题用):"
    echo "+---------------------------------------------------------------+"
    echo "| 操作系统 : $(uname -nmrso)|"
    echo "| 固件版本 : $(nvram get productid):${FW_TYPE_NAME}:$(nvram get buildno)|"
    echo "| 内存使用 : $(free -m|awk '/Mem/{printf("free: %6.2f MB,total: %6.2f MB,usage: %6.2f%%\n", $4/1024,$2/1024, $3/$2*100)}')|"
    echo "| 磁盘空间 : $(df /koolshare |awk '!/Filesystem|Mounted/{printf("free: %6.2f MB,total: %6.2f MB,usage: %6.2f%%\n", $4/1024,$2/1024, $3/$2*100)}')|"
    echo "+---------------------------------------------------------------+"
    echo "|>> vClash当前正在使用的软件版本：                                  |"
    debug_info "vClash" "$(dbus get ${app_name}_vclash_version)"
    debug_info "clash_premium" $(${CONFIG_HOME}/core/clash -v|head -n1|awk '{printf("%s_%s_%s", $2, $3, $4)}')
    debug_info "yq" "$(${YQ} -V|awk '{ print $NF}')"
    debug_info "jq" "$(${JQ} -V)"
    echo "|>> vClash初始安装包自带的软件版本(分析是否个人更改过):                |"
    cat ${CONFIG_HOME}/version | awk -F':' '{ printf("|%20s : %-40.40s|\n",$1,$2) }'
    echo "+---------------------------------------------------------------+"
    echo "vClash的转发规则,分析转发规则是否正常:"
    iptables_status
    echo "+---------------------------------------------------------------+"
}


backup_env() {
    # 输出环境变量到${CONFIG_HOME}/$env_file文件
    LOGGER "开始备份环境变量"
    echo "source ${KSHOME}/scripts/base.sh" > ${CONFIG_HOME}/$env_file
    dbus list clash_ | grep -v "clash_enable" | sed 's/^/dbus set /; s/=/=\"/;s/$/\"/' >> ${CONFIG_HOME}/$env_file
    if [ "$?" != "0" ] ; then
        LOGGER "备份环境变量失败"
    else
        LOGGER "备份环境变量成功"
    fi
}

backup_config_file() {
    # 备份配置信息,打包生成压缩包文件
    # 备份文件: 1.可编辑的文件列表 ； 2.当前clash运行环境变量
    file_list="${clash_edit_filelist} $env_file"
    LOGGER "开始备份配置信息: $file_list"
    if [ -d "${CONFIG_HOME}" ] ; then
        backup_env
        cur_filelist=""
        for fn in $file_list
        do
            [[ ! -r "${CONFIG_HOME}/${fn}" ]] && LOGGER "没不到备份文件或目录: ${CONFIG_HOME}/${fn}" && continue
            cur_filelist="$cur_filelist $fn"
        done
        # 压缩文件名
        tar -zcvf $backup_file -C ${CONFIG_HOME} ${cur_filelist}
        if [ "$?" != "0" ] ; then
            LOGGER "备份配置信息失败"
        else
            LOGGER "备份配置信息成功"
            rm -f ${CONFIG_HOME}/$env_file
        fi
    else
        LOGGER "备份配置信息失败"
    fi
}

restore_config_file() {
    # 恢复配置信息,解压生成配置文件
    LOGGER "开始恢复配置信息"
    if [ "$clash_restore_file" = "" ] ; then
        LOGGER "恢复配置文件上传失败"
        return 1
    fi
    if [ -f "/tmp/upload/$clash_restore_file" ] ; then
        tar -zxvf "/tmp/upload/$clash_restore_file" -C ${CONFIG_HOME}
        if [ "$?" != "0" ] ; then
            LOGGER "恢复配置信息失败!解压过程出错! 文件名:${clash_restore_file}"
        else
            if [ -f "${CONFIG_HOME}/$env_file" ] ; then
                LOGGER "开始执行恢复环境变量脚本"
                sh "${CONFIG_HOME}/$env_file"
                LOGGER "执行恢复环境变量脚本完成"
            fi
            LOGGER "恢复配置信息成功"
        fi
    else
        LOGGER "恢复配置信息文件没找到!"
        return 2
    fi
    rm -f "/tmp/upload/$clash_restore_file"
    dbus remove clash_restore_file
}

upload_clash_file() {
    # 升级clash文件
    LOGGER "开始升级Clash内核文件"
    if [ "$clash_bin_file" = "" ] ; then
        LOGGER "Clash升级文件上传失败"
        return 1
    fi
    if [ -f "/tmp/upload/$clash_bin_file" ] ; then
        # 自动识别升级内核文件格式
        gunzip "/tmp/upload/$clash_bin_file" -c > "${CONFIG_HOME}/core/${clash_bin_file%%.gz}"
        if [ "$?" != "0" ] ; then
            LOGGER "解压Clash文件过程出错! 文件名:${clash_bin_file}"
        else
            if [ -f "${CONFIG_HOME}/core/${clash_bin_file%%.gz}" ] ; then
                chmod +x ${CONFIG_HOME}/core/${clash_bin_file%%.gz}
                LOGGER "上传Clash内核文件成功: ${clash_bin_file%%.gz}"
                LOGGER "使用方法: 1.手动切换Clash内核. 2.切换正确的config配置."
            else
                LOGGER "没有找到Clash内核文件,上传失败!"
            fi
        fi
    else
        LOGGER "没找到上传的Clash文件!"
        return 2
    fi
    rm -f "/tmp/upload/$clash_bin_file"
    dbus remove clash_bin_file
}

# 上传并应用新的config.yaml配置文件
applay_new_config() {
    
    LOGGER "开始应用新配置"
    if [ "$clash_config_file" = "" ] ; then
        LOGGER "没有设置[clash_config_file]参数"
        return 1
    fi
    if [ ! -f "/tmp/upload/${clash_config_file}" ] ; then
        LOGGER "找不到配置文件: /tmp/upload/${clash_config_file}"
        return 2
    fi
    # 生成新配置文件
    rnd=$(openssl rand -hex 3)
    new_file=${CONFIG_HOME}/config_${rnd}.yaml
    cp -f "/tmp/upload/${clash_config_file}" ${new_file}
    if [ -f "${new_file}" ] ; then
        LOGGER "拷贝新配置成功"
    else
        LOGGER "拷贝新配置失败"
    fi
    rm -f "/tmp/upload/${clash_config_file}"
    dbus remove clash_config_file
    LOGGER "如果希望使用新配置，请手工切换新配置。"
}


save_current_tab() {
    # 保存当前tab标签页面id操作
    echo "仅仅用于实时保存最后选择的tab页面id" >/dev/null
}

# 获取 config.yaml 中配置的文件路径
list_config_files() {
    tmp_rule_list="$(${YQ} e '.rule-providers[]|select(.type=="file").path' ${config_file})"
    tmp_proxy_list="$(${YQ} e '.proxy-providers[]|select(.type=="file").path' ${config_file})"
    [[ -z "$tmp_rule_list"  ]] && LOGGER "提示:您的rule-providers 中没有file类型"
    [[ -z "$tmp_proxy_list" ]] && LOGGER "提示:您的proxy-providers中没有file类型"
    is_ok=0
    for fn in ${tmp_rule_list} ; do
        dst_path="${CONFIG_HOME}/${fn}"
        [[ ! -f ${dst_path} ]] && LOGGER "Rule规则集文件不存在: ${dst_path}" && is_ok=1
    done
    for fn in ${tmp_proxy_list} ; do
        dst_path="${CONFIG_HOME}/${fn}"
        [[ ! -f ${dst_path} ]] && LOGGER "Proxy代理集文件不存在: ${dst_path}" && is_ok=1
    done
    [[ "$is_ok" == 1 ]] && LOGGER "请先修改配置文件或手动添加缺失的配置文件"

    # 可用clash启动配置文件列表
    cd $CONFIG_HOME && config_filelist="$(find config/ -type f -name "*.yaml" 2>/dev/null| awk '{ if(i>0)printf(" "); printf("%s",$0); i++; }' )"
    [[ "${config_filelist}" == "" ]] && LOGGER "糟糕！你没有任何可用的启动配置文件！请上传启动配置文件后再来启动!" && return 0
    dbus set clash_config_filelist="$config_filelist"

    tmp_filelist="$config_filelist"
    for fn in $tmp_rule_list $tmp_proxy_list
    do
        tmp_filelist="$tmp_filelist $fn"
    done
    dbus set clash_edit_filelist="$tmp_filelist"
    LOGGER "获取配置文件列表成功!"
}

get_one_file() {
    # 获取单个文件的内容
    local file_name="$(echo $KSHOME/${app_name}/$clash_edit_filepath | sed 's/\/\.\//\//g')"
    if [ ! -f ${file_name} ]; then
        LOGGER "文件没找到: ${file_name}"
        return 1
    fi
    dbus set clash_edit_filecontent=$(cat ${file_name} | base64_encode)
    if [ $? -ne 0 ]; then
        LOGGER "${file_name} 文件读取失败!"
        return 2
    fi
    LOGGER "${file_name} 文件读取完成!"
}

set_one_file() {
    # 设置单个文件的内容: 过滤掉中间的 "./"部分
    local file_name="$(echo $KSHOME/${app_name}/$clash_edit_filepath | sed 's/\/\.\//\//g')"
    if [ ! -f ${file_name} ]; then
        LOGGER "文件没找到: ${file_name}"
        return 1
    fi
    cp ${file_name} ${file_name}.bak
    echo -n ${clash_edit_filecontent} | base64_decode > ${file_name}.tmp
    if [ $? -eq 0 ]; then
        mv ${file_name}.tmp ${file_name}
        LOGGER "${file_name} 保存成功!"
    else
        rm -f ${file_name}.bak
        LOGGER "${file_name} 保存失败!"
        return 1
    fi
    dbus remove clash_edit_filecontent
    rm -f ${file_name}.bak
}

# 切换配置文件
switch_clash_config() {
    # TODO: 切换clash配置文件
    # 1. 备份当前配置文件
    # 2. 格式化验证新配置文件，并修改必要的设置
    # 3. 如果格式验证失败，报错，恢复原来的配置
    # 4. 如果格式验证成功，生成新配置，重启clash服务
    LOGGER "完成备份当前配置文件" && [[ -f ${config_file} ]] && cp ${config_file} ${config_file}.bak

    check_config_file && LOGGER "格式验证成功!新配置文件 $clash_config_filepath 切换完成!" && return 0

    [[ -f ${config_file}.bak ]] && cp ${config_file}.bak ${config_file} && LOGGER "【已经恢复原配置文件】"

    LOGGER "新配置文件 $clash_config_filepath 切换失败! 请检查配置文件格式问题."
    return 1
}

# 获取所有 Clash Core 文件列表 #
list_clash_core() {
    cd $CONFIG_HOME && clash_core_list="$(find core/ -type f 2>/dev/null | grep -vE 'bak|old' | awk '{ if(i>0)printf(" "); printf("%s",$0); i++; }' )"
    [[ "${clash_core_list}" == "" ]] && LOGGER "糟糕！你没有任何可用的Clash 内核文件！请上传Clash内核文件后再来启动!" && return 0
    dbus set clash_core_list="$clash_core_list"
}
# 切换 Clash内核 #
switch_clash_core() {
    LOGGER "切换Clash内核: ${clash_core_current}"
    ln -sf ${CONFIG_HOME}/${clash_core_current} ${BINFILE}
}

# 切换透明代理模式
switch_clash_tmode() {
    # 修改iptables规则
    # 重启clash服务
    LOGGER "切换透明代理模式为: $clash_tmode"
}
clash_config_init() {
    # 校验配置文件
    list_clash_core
    list_config_files
    check_config_file
}

set_log_type() {
    # 设置日志类型
    local log_type="$1"
    if [ -z "$log_type" ]; then
        LOGGER "日志类型不能为空!"
        return 1
    fi
    dbus set clash_log_type="$log_type"
    LOGGER "设置日志类型成功!"
}
# 使用帮助信息
usage() {
    cat <<END
 ======================================================
 使用帮助:
    ${app_name} <start|stop|restart>
    ${app_name} update_provider_file

 参数介绍:
    start   启动服务
    stop    停止服务
    restart 重启服务
    update_provider_file 更新provider_free.yaml文件

 ======================================================
END
    exit 0
}

# 用于返回JSON格式数据: {result: id, status: ok, data: {key:value, ...}}
response_json() {
    # 其中 data 内容格式示例: "{\"key\":\"value\"}"
    # 参数说明:
    #   $1: 请求ID
    #   $2: 想要传递给页面的JSON数据:格式为:key=value\nkey=value\n...
    #   $3: 返回状态码, ok为成功, error等其他为失败
    http_response "$1\",\"data\": "$2", \"status\": \"$3"  >/dev/null 2>&1
}

######## 执行主要动作信息  ########
do_action() {

    if [ "$#" = "2" ] ; then
        # web界面配置操作(返回参数更精准快速)
        action_job="$2"
        case "$action_job" in 
            test_res)
                # awk使用=分隔符会导致追加尾部的=号被忽略而出现错误
                # 因此使用了sub只替换第一个=号为":"，后面的=号不变
                ret_data="{$(dbus list clash_edit| awk '{sub("=", "\":\""); printf("\"%s\",", $0)}'|sed 's/,$//')}"
                response_json "$1" "$ret_data" "ok"
                return 0
                ;;
            start)
                # 启动服务, 并返回状态
                #service_start
                ret_data="{$(dbus list clash_ | awk '{sub("=", "\":\""); printf("\"%s\",", $0)}'|sed 's/,$//')}"
                response_json "$1" "$ret_data" "ok"
                # 先返回成功结果,放在后面执行启动功能，否则页面会一直等待且没有动态执行中的效果
                service_start
                return 0
                ;;
            switch_clash_config)
                # 修改配置后，需要重启操作 #
                $action_job
                service_stop
                service_start
                ret_data="{$(dbus list clash_yacd_ui | awk '{sub("=", "\":\""); printf("\"%s\",", $0)}'|sed 's/,$//')}"
                response_json "$1" "$ret_data" "ok"
                return 0
                ;;
            get_one_file)
                get_one_file
                ret_data="{$(dbus list clash_edit_filecontent | awk '{sub("=", "\":\""); printf("\"%s\",", $0)}'|sed 's/,$//')}"
                response_json "$1" "$ret_data" "ok"
                dbus remove clash_edit_filecontent
                return 0
                ;;
            list_config_files)
                list_config_files
                ret_data="{$(dbus list clash_edit_filelist  | awk '{sub("=", "\":\""); printf("\"%s\",", $0)}'|sed 's/,$//')}"
                response_json "$1" "$ret_data" "ok"
                return 0
                ;;
            list_clash_core|switch_clash_core)
                $action_job
                ret_data="{$(dbus list clash_core | awk '{sub("=", "\":\""); printf("\"%s\",", $0)}'|sed 's/,$//')}"
                response_json "$1" "$ret_data" "ok"
                return 0
                ;;
            clash_config_init)
                clash_config_init
                ret_data="{$(dbus list clash_  | awk '{sub("=", "\":\""); printf("\"%s\",", $0)}'|sed 's/,$//')}"
                response_json "$1" "$ret_data" "ok"
                return 0
                ;;
            ignore_new_version)
                ignore_new_version
                ret_data="{$(dbus list clash_version  | awk '{sub("=", "\":\""); printf("\"%s\",", $0)}'|sed 's/,$//')}"
                response_json "$1" "$ret_data" "ok"
                return 0
                ;;
            ignore_vclash_new_version)
                ignore_vclash_new_version
                ret_data="{$(dbus list clash_vclash_version  | awk '{sub("=", "\":\""); printf("\"%s\",", $0)}'|sed 's/,$//')}"
                response_json "$1" "$ret_data" "ok"
                return 0
                ;;
            *)
                http_response "$1" >/dev/null 2>&1
                ;;
        esac
    else
        # 后台执行脚本
        if [ "$1" = "" ] ; then
            action_job="help"
        else
            action_job="$1"
        fi
    fi
    # LOGGER "执行动作 ${action_job} ..."
    case "$action_job" in
    stop)
        service_stop
        ;;
    start)
        service_start
        ;;
    restart)
        service_stop
        service_start
        ;;
    switch_clash_tmode|update_clash_bin | update_vclash_bin | switch_trans_mode|switch_group_type|restore_config_file|switch_ipv6_mode)
        # 需要重启的操作分类
        $action_job
        if [ "$?" = "0" ]; then
            service_stop
            service_start
        else
            LOGGER "$action_job 执行出错啦!"
        fi
        ;;
    get_proc_status|update_provider_file|update_geoip|backup_config_file|applay_new_config|upload_clash_file)
        # 不需要重启操作
        $action_job
        ;;
    set_one_file|add_iptables | del_iptables | set_log_type|switch_option_tab)
        # 不需要重启操作
        $action_job
        ;;
    show_router_info)
        # 输出debug信息
        $action_job  | tee -a $debug_log
        ;;
    help)
        usage
        ;;
    *)
        LOGGER "无效的操作! clash_action:[$action_job]"
        usage
        ;;
    esac
    # 执行完成动作后，清理动作.
    dbus remove clash_action
}

LOGFILE="/tmp/upload/clash_status.log"
if [ "$#" = "1" ] ; then
    # 后台执行脚本: 输出结果不保存
    LOGFILE=/dev/null
fi


no_output_log=0
case "$2" in
    clash_config_init|save_current_tab|list_config_files)
        # 不需要输入日志内容
        no_output_log=1
        ;;
esac

if [ "$no_output_log" = "0" ] ; then
    echo > $LOGFILE
    do_action $@ 2>&1 | tee -a $LOGFILE
    echo "XU6J03M6" >> $LOGFILE
else
    do_action $@  >/dev/null 2>&1
fi
