# vClash说明
> vClash插件的安装、开发过程说明。

## 001.如何使用vClash
> 安装vClash方法以及安装过程遇到问题怎么解决。


### 000.路由器固件信息

首先，先说一下RT-AC86U的华硕路由器固件koolcenter发布的有这么几个版本：
- 官方改版：原汁原味的官方版本+koolshare软件中心，这个版本**包含TUN设备支持能力**，同时包含了TPROXY内核模块。
- 梅林改版：这个版本**仅支持TPROXY内核模块**，不包含TUN设备支持能力（实际上TUN在路由器上性能也不是很好）。

对于这两个版本的差异，vClash插件进行支持能力自动识别，让选择困难症患者不再犯愁。


## 透明代理规则升级说明-202404

透明代理目前的几个关键点：
- 解决DNS污染问题（局域网和**路由器本机**）
- 支持IPv6地址代理


通过`iptables`实现透明代理的方法：
- NAT方式：最简单通用的代理规则，由于是存在修改数据包端口情况，理论上效率相比TPROXY模式会更低。
- TPROXY方式： 通过给数据包打标记方式转发数据包给透明代理端口(TPROXY端口），前提是路由器固件内核自带了 TPROXY 模块(xt_TPROXY.ko) 才可以用。
- 使用TUN模式： 原理类似VPN（适合主机使用，而不适合路由器），需要Clash支持TUN模式，另外一个前提是路由器固件支持TUN设备,能找到 /dev/net/tun 这个设备文件，[阅读更多TUN知识](https://mirrors.edge.kernel.org/pub/linux/kernel/people/marcelo/linux-2.4/Documentation/networking/tuntap.txt).


vClash透明代理对以上方法都进行了实现，并提供了切换选择功能。下面对这几种透明代理模式简要的说明区别:

1. NAT模式:默认模式,万能通用规则,但不支持IPv6透传,国内IPv6直连正常
2. TPROXY模式(可能删除):支持IPv6透传,UDP协议透传存在问题,比如访问raw.githusercontent.com返回0.0.0.0
3. TPROXY+NAT模式(推荐):解决了TPROXY模式的DNS解析问题,同时支持IPv6透传

> 重要提示：
> 目前使用情况来说，如果不适用IPv6，默认的NAT足以满足，需要IPv6支持，TPROXY+NAT模式应是首选。




### 如何支持IPv6代理更合理？
- 代理如果不支持IPv6地址，此时将IPv6地址请求转发给代理会如何？ 测试：两个代理节点（区别是有、无IPv6地址)。
- 怎么配置IPv6的 `iptables` 规则？NAT规则不适用了，是否只能通过 **TPROXY** 模块代理所有请求？




### 001.安装vClash
最新版本安装包存放到release目录中，对应下载链接:

| Github分支  | 支持Koolshare路由器固件版本         | CPU架构       | Github下载链接                                                                                  | 国内CDN下载链接                                                                                   |
| ----------- | ----------------------------------- | ------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| main        | 华硕380版本(停止更新)               | armv7l        | [Github安装包](https://github.com/vxiaov/vClash/raw/main/release/clash.tar.gz)                  | [CDN安装包](https://cdn.jsdelivr.net/gh/vxiaov/vClash@main/release/clash.tar.gz)                  |
| ksmerlin386 | 华硕官改、梅林386/388版本(持续更新) | aarch64/arm64 | [Github安装包](https://github.com/vxiaov/vClash/raw/ksmerlin386/release/clash.tar.gz)           | [CDN安装包](https://cdn.jsdelivr.net/gh/vxiaov/vClash@ksmerlin386/release/clash.tar.gz)           |
| ksmerlin386 | 华硕官改、梅林386/388版本(持续更新) | armv7l        | [Github安装包](https://github.com/vxiaov/vClash/raw/ksmerlin386/release/clash.armv5.tar.gz)     | [CDN安装包](https://cdn.jsdelivr.net/gh/vxiaov/vClash@ksmerlin386/release/clash.armv5.tar.gz)     |
| ksmerlin386 | 华硕官改、梅林384版本(持续更新)     | armv7l        | [Github安装包](https://github.com/vxiaov/vClash/raw/ksmerlin386/release/clash_384.tar.gz)       | [CDN安装包](https://cdn.jsdelivr.net/gh/vxiaov/vClash@ksmerlin386/release/clash_384.tar.gz)       |
| ksmerlin386 | 华硕官改、梅林384版本(持续更新)     | aarch64/arm64 | [Github安装包](https://github.com/vxiaov/vClash/raw/ksmerlin386/release/clash_384.armv5.tar.gz) | [CDN安装包](https://cdn.jsdelivr.net/gh/vxiaov/vClash@ksmerlin386/release/clash_384.armv5.tar.gz) |


路由器插件的安装方法使用 **“离线安装”**，安装前遇到**非法关键词检测**问题可以看下面解决方法。

#### 001.离线安装非法关键词检测不通过怎么办？这样解决。


**离线安装**时，非法关键词检测是在`ks_tar_install.sh`脚本中设置的，检测关键词信息如下：
```sh
    local ILLEGAL_KEYWORDS="ss|ssr|shadowsocks|shadowsocksr|v2ray|trojan|clash|wireguard|koolss|brook|fuck"
```

屏蔽它的方法就是将关键词替换个无意义的词，例如"xxxxxxxxx"。

接下来，我们就来实现这个操作，在路由器控制台终端执行如下命令：
```sh

# 先检查关键词变量是否存在
grep ILLEGAL_KEYWORDS /koolshare/scripts/ks_tar_install.sh

# 替换掉非法关键词信息
sed -i 's/local ILLEGAL_KEYWORDS=.*/local ILLEGAL_KEYWORDS="xxxxxxxxxxxxxxxxxxx"/g' /koolshare/scripts/ks_tar_install.sh

```

就这样，以后可以通过离线上传安装了。

#### 002.clash启动失败问题
> 由于GoLang版本Clash启动时分配内存空间较大，对于小内存(512MB及以下)路由器会出现**启动失败问题**,以`RT-AC86U`为例，启动时分配虚拟内存(VIRT)有600-700MB左右(实际内存使用在30-80MB左右)，对于512MB物理内存路由器直接起不来。

**解决方法**

1. 挂载虚拟内存: 支持**USB接口路由器**可以插入一个1GB以上的优盘作为虚拟内存挂载，可以使用路由器自带了虚拟内存插件。[阅读挂载虚拟内存教程文章](https://vlike.work/VPS/router-mount-swap.html)。



### 003.是否升级新版本clash?使用Clash版本建议

如果你使用最新版本的Clash程序发现不正常(例如：每次重启后都需要设置节点信息，无法保存select模式节点信息)，那么建议你更换到[Clash Premium 2021.09.15 版本](https://github.com/vlikev/clash_binary/tree/f3c4db627f8d091682dc26d5bfe5efd7ad93a8f4/premium/)。

为什么呢？

可以从代码里看到， Clash 这个版本是使用文件方式保存节点选择信息，保存信息目的是为了重启clash后可以不用重新手工设置节点选择信息，但下一个版本`2021.11.08(对应v1.8.0)版本`就更换为名为`cache.db`文件保存信息(代码里是使用了第三方k/v库`bbolt`,但在一些arm系列路由器里无法正常工作)，原因在于/jffs文件系统类型jffs2不支持 **mmap**导致。

如果你使用的不是jffs2类型文件系统，比如自己动手改成了 **ext4**类型文件系统，可以更新到最新版本。


## 002.开发知识

由于开发插件过程想法和需求总是在变化，所以新版本可能会去掉了以前不需要或者冗余的一些功能，而且实现的逻辑也在更新，以达到最简便快捷的实现方式。

如果你打算开发一个自己的插件，多阅读一些插件的代码对你非常有帮助的。


### 001.vClash插件基本目录结构

下面是vClash源码的目录结构:

```text
./clash
├── bin
│   ├── clash_for_armv5
│   ├── clash_for_armv8
│   ├── jq_for_armv5
│   ├── jq_for_armv8 -> jq_for_armv5
│   ├── uri_decoder_for_armv5
│   ├── uri_decoder_for_armv8 -> uri_decoder_for_armv5
│   ├── yq_for_armv5
│   └── yq_for_armv8 -> yq_for_armv5
├── clash
│   ├── config.yaml
│   ├── Country.mmdb
│   ├── dashboard
│   ├── providers
│   ├── ruleset
│   └── version
├── install.sh
├── res
│   ├── clash_style.css
│   └── icon-clash.png
├── scripts
│   └── clash_control.sh
├── uninstall.sh
└── webs
    └── Module_clash.asp
```

### 002.vClash功能说明

看到上面的目录结构后，只有一个功能脚本 **clash_control.sh**文件，这是大部分插件的基本样子了，具体有什么功能都是通过将参数传递给clash_control.sh来决定。

- clash_control.sh : 所有的功能都集成在这个脚本中，根据传入参数不同调用不同功能。
- Module_clash.asp : 插件的Web前端UI界面，就是浏览器中看到的样子，都是在这里配置的。
- install.sh/uninstall.sh: 只在插件离线安装和卸载时调用，初始化和清理与vClash插件相关内容用。
- clash : 这个目录包含Clash运行的基础配置信息，启动配置config.yaml, Country.mmdb包含IP数据， dashboard包含Yacd前端，providers包含代理订阅文件，ruleset包含订阅规则文件，version包含插件版本信息，bin包含所有相关的命令工具。
- res   : clash_style.css美化布局在Module_clash.asp页面中的按钮、标签的样式， icon-clash.png就是 vClash的Logo图标。

以上就是vClash包含的内容了。

### 003.实现功能简述


#### v1开头版本为支持KS梅林380版本固件

- [x] Clash服务启动开关
- [x] 透明代理启用开关: 选择是否需要使用透明代理(感觉不到自己使用了代理，内网应用不做任何配置即可访问Google)
- [ ] ~~网络状态检查(似乎这个功能有点多余)~~
- [x] 节点配置:支持provider(url)更新配置。
- [x] DNS设置：使用无污染的DNS解析国外域名。
- [x] 支持添加和删除个人代理节点(单独分组：命名为DIY)。
- [x] 更改URL订阅源方式为下载文件更新方式，更合理安全，避免URL无法访问导致Clash无法启动情况。

> 为了支持 ss/ssr/vmess URI后台解析，个人开发了`GoLang`版本的`uri_decoder`工具，目的是解析URI并生成新增加节点的yaml文件，最后使用`yq`命令合并两个文件，完成节点添加功能。


#### v2开头版本为支持KS梅林384/386/388版本固件

与v1系列版本差别就是对`Koolshare`软件中心API的`1.5`版本支持。

由于差异比较大的缘故，单独分了一个分支进行维护。

目前支持功能：

- [x] 透明代理模式
- [x] URL订阅源更新(走路由器代理访问)
- [x] 支持**DIY代理组**节点`添加`/`删除`功能(由于URI的不规范原因,支持的代理参数可能存在解析问题)
- [x] ~~代理组类型切换功能: select/url-test/load-blance/fallback~~
- [x] 默认支持Yacd控制面板，
- [x] 支持自定义更新GeoIP数据文件，文件大小由自己选择(200KB~6MB)。
- [x] 支持CloudFlare的DDNS功能，可同时更新同一账号多个域名(多个域名可用)
- [x] 支持中继代理组配置，初衷为了支持解锁Netflix，可以拯救被墙的代理组。
- [x] 增加上传自定义的config.yaml文件功能: 用户可以使用自己的订阅源proxy-providers,以及自己的代理组.
- [x] 增加备份与恢复配置功能: 方便使用者折腾,如果折腾失败了可以快速恢复到备份前状态.
- [x] 增加自定义**黑、白名单规则**界面配置功能: 想要单独设置某个网站使用代理或者直连(比如游戏网站、视频网站等)，这个功能就满足要求了.
- [x] 增加了**黑名单模式/白名单模式**选择: 黑名单模式时默认直连，白名单模式时默认走代理，匹配规则都来自于github分享。
- [x] 可视化编辑config.yaml文件及其包含的providers文件: **v2.2.4**版本支持。



### 004.为什么不提供代理可用性检测
> 因为检测代理可用性总要访问一些没必要的地址。**即使检测了，有时候也是不能证明代理是否可用的**！这就是多此一举的功能,Yacd页面就具备了这个检测功能。

到底代理可不可用，验证就很简单，直接使用就可以了：
- **国外验证**直接通过浏览国外Youtube就可以验证了
- **国内验证** 访问国内网站就可以了。


### 005.插件安装过程条件检测

安装过程需要对路由器的一些基础环境检测, 主要是判断是否能使用此插件,我总结了主要的检测如下:

1. **koolshare**软件中心版本检测: 在[github项目中](https://github.com/koolshare/rogsoft/blob/master/README.md)有介绍, 主要的区别就是 **软件中心API**分 **1.0代(在华硕380版本固件使用)** 和 **1.5代(华硕384/386版本固件使用)**, 二者代码不兼容通用, 最开始开发的main分支就是 **1.0代的华硕380版本固件使用的**, 之后新的路由器都过渡到了 **1.5代的华硕386版本固件**.
2. CPU架构检测: 根据一些分析,主要的架构型号有: armv7l/aarch64/x86_64/mips , 其中华硕固件并不支持x86_64/mips两种架构的CPU, 因此目前也只支持了 armv7l 和 aarch64(armv8).
3. Linux内核版本检测(可选): 如果编译的可执行程序非静态链接生成(依赖一些动态库),可能需要做这个检测,对于没有动态库依赖的可执行程序就没必要检测了,比如**GoLang语言编写的工具**.
4. 固件版本检测(可选): 比如华硕的目前的三个版本号(380/384/386),以后可能有更高版本, 如果对固件自带特殊命令没什么依赖就没什么必要检测.

如果安装失败了,就将安装过程日志反馈给开发者,了解上面几个检测情况,哪个环节不支持,以便于支持更多的固件。你虽然没有写代码，但这样做也是帮助这个插件更加稳定。



## 003.koolshare插件开发的API知识
> 软件中心的API说明文档在固件中详细说明的不多，多数是通过阅读代码了解，这里简单的做一下总结分享。

先列举他人分享内容:
- [官方软件中心1.0老版本API文档说明-(想开发插件推荐先阅读)](https://github.com/koolshare/koolshare.github.io/wiki/%E6%A2%85%E6%9E%97AM380%E8%BD%AF%E4%BB%B6%E4%B8%AD%E5%BF%83%E6%8F%92%E4%BB%B6%E5%BC%80%E5%8F%91%E6%95%99%E7%A8%8B%E8%AF%A6%E8%A7%A3)
- [SukkaW分享的软件中心API文档说明](https://github.com/SukkaW/Koolshare-OpenWrt-API-Documents)
- [httpdb-软件中心API源码](https://github.com/thesadboy/httpdb)

### 001.关于执行shell脚本返回值如何实现JSON数据传递?

常规的方式返回结果就是个字符串数据，调用方法为:

```Bash
http_response "ok"
```

这样在Web前端就会得到如下结果:
```json
{
    "result": "ok"
}
```

想要实现返回JSON数据就要从 **http_response**返回值上入手了，经过一番尝试，成功的返回了JSON结果，看看下面的示例:


```Bash

# 用于返回JSON格式数据: {result: id, status: ok, data: {key:value, ...}}
response_json() {
    # 其中 data 内容格式示例: "{\"key\":\"value\"}"
    # 参数说明:
    #   $1: 请求ID
    #   $2: 想要传递给页面的JSON数据:格式为:key=value\nkey=value\n...
    #   $3: 返回状态码, ok为成功, error等其他为失败
    http_response "$1\",\"data\": "$2", \"status\": \"$3"  >/dev/null 2>&1
}


....#省略了若干代码

    case "$action_job" in
        test_json)
            # awk使用=分隔符会导致追加尾部的=号被忽略而出现错误
            # 因此使用了sub只替换第一个=号为":"，后面的=号不变
            ret_data="{$(dbus list clash_edit| awk '{sub("=", "\":\""); printf("\"%s\",", $0)}'|sed 's/,$//')}"
            response_json "$1" "$ret_data" "ok"
            return 0
            ;;
        *)
            ....
            ;;
    esac

```

看到了，我增加了一个 **response_json()**函数，对 http_response 进行了封装，然后对"key=value\nkey=value\n..."这样格式的数据进行了双引号添加处理(这里没有进行类型检测，一律按字符串处理了)。

看看Web前端得到结果数据吧:

```json
{
    "result": "99822551",
    "data": {
        "clash_edit_filecontent": "cGF5b。。。。。="
    },
    "status": "ok"
}
```

就这样，Ajax动态加载数据的功能就可以实现了, 这样解析数据既简单有快速，比拼接一个很长很长的字符串，然后再截取字符串操作要容易的多了，且不会出错的。

当然，这种返回数据大小是有限制的，取决于这个实现过程的下面几个限制:

- skipdb限制单个 value 最长大小，实测应该是**128KB**以内的value可以设置成功,这里的128KB是value值，如果使用base64编码数据的话，原始数据应该在**96KB**以内，比如rule订阅文件中的 **direct.yaml** 传递过程就因为value太大而报错，这里在实现时需要增加文件大小判断,推荐限制到 **0.75MB**以内，你会问为啥？我只能说实际经验，俺也没读过skipdb源代码，没办法给出精准数据。
- httpdb限制， httpdb对单个value的限制应该是在 skipdb之上，所以对于单个value限制，skipdb才是导致木桶漏水的短板。
- 多个value数据限制： 没实际测试过，但传递数据越多意味着传输时间就越久，而进行Base64编码和解码的时间也会越久(虽然感知不明显)，做到这一点是最好的: **一个操作任务只返回相关的结果数据!**



## 004.为什么有这个项目
> 作为程序员的俺，用了很多年别人写的插件，一天翻出了垃圾堆里**零元购计划**的斐迅K3路由器，打算**变斐为宝**，毕竟曾经被他欺骗过感情的。。。

一开机，发现装了`梅林380版固件`，那就从这里开始吧。

**如何写个小巧的插件呢？** 第一个想法就是 **拿来主义**，毕竟没有 **Ctrl+C/Ctrl+V**解决不了的(玩笑话)。

找了几个插件(比如fancyss、merlinclash等)，都过于庞大,此时恰好看到**clash**挺火的，那就使用**clash**作为核心功能吧。

至此, 这个项目就诞生了。但当时名字为clash，这与clash重名可不行呀，俺想到了《V字仇杀队》电影的V,那就起名为**vClash**啦。

V带着面具，但Clash图标加面具就啥也看不到了，于是想到了另一个角色Z(佐罗)，于是在vClash上加了Z的蒙眼带。

之后，新路由器使用了`梅林改版386固件`, 于是又开发了支持`386版本`的**ksmerlin386分支**版本。

## 005.问题记录

### 如何正确的透传支持QUIC的网站

概念：
- QUIC： 在HTTP/3中，弃用TCP协议，改为使用基于UDP协议的QUIC协议实现。

想要正确的访问支持QUIC协议的网站，需要如下条件：
- 浏览器入口支持QUIC协议： Firefox/Chrome 支持QUIC协议，但Firefox默认启用，而Chrome默认关闭QUIC支持（访问 chrome://flags/#enable-quic 启用QUIC支持）。
- 网站支持QUIC协议： 目前google.com/youtube.com/android.com 网站支持QUIC协议。


由于QUIC协议是基于UDP协议的，因此路由器的**透明代理是需要支持UDP协议透传的**。

- **重点**是透明代理使用的代理节点要配置支持UDP协议，通常是在clash的代理节点配置中添加`udp:true`支持UDP协议。


**配置是否正确该如何验证呢？**
- 访问 https://www.youtube.com 网站如果可以看视频就没问题了。

如何知道访问的网站使用了QUIC协议呢？
- 在vClash中的Yacd面板的**连接**页面，过滤查看UDP协议连接有哪些，端口为:443则说明这个网站使用了QUIC协议。



> 更多深入了解UDP应用知识可以[阅读这里](https://github.com/XTLS/Xray-core/discussions/237)。

为什么会有这一部分说明呢？

在配置UDP透明代理时，iptables规则正常，但youtube访问无法看视频，很奇怪，看了yacd面板的连接信息才发现，youtube.com的**部分连接**使用了QUIC协议，但代理节点没有启用UDP协议支持，还了一个支持UDP的节点后，视频可以正常访问了。

对于一些不了解这些知识的人，可能也会遇到类似现象而不知所措，可能误以为是vClash插件本身存在问题，所以在这里加了这段说明。
以SS配置为例：
```json
  - name: "ss1"
    type: ss
    server: server
    port: 443
    cipher: chacha20-ietf-poly1305
    password: "password"
    udp: true
```
> 我们只需要将 udp: true 前面的 井号(#)注释去掉即可。


## 999.最后


点个赞就是支持！

关注[我的博客](https://vlike.work/)或者[油管频道](https://www.youtube.com/channel/UCsb-LlhxstK3VRLz5_3kZxQ)获取一些相关内容, 虽然更新的并不是很多。

获取免费代理节点，可以订阅[TG频道](https://t.me/free_proxy_001)。
