# FAQ

针对一些常见问题的解答

## vClash插件问题

1. 为什么安装包很大？
   - 目前已经尽量在优化缩减大小，Yacd替换成了XD面板，内核由之前内置 Clash.meta和 ClashPremium 两个版本改为只携带 ClashPremium版本，而 Country.mmdb 文件原则上不携带为好，但为了防止用户无法下载而没有删掉。
2. 为什么有三种代理模式？  
   - NAT模式： 采用NAT技术实现的透明代理转发规则， 与Clash配合时，会有比如下载Github文件失败问题，路由器本机流量无法走代理，不支持IPv6代理透传（意思是不能使用有IPv6地址的代理节点，并不是不能使用IPv6地址访问外网）。
   - TPROXY模式: **此模式适合 ClashMeta 版本内核使用**，需要内核集成了TPROXY模块功能， 解决路由器本机流量无法走代理问题，但由于配置规则略复杂而可能导致流量回环问题，通常流量回环两种解决方法分别是 mark标记 和 gid用户分离方法。
   - TPROXY+NAT模式: **此模式适合 ClashPremium 版本内核使用**，采用TPROXY模式透传，但对于DNS请求还是采用NAT转发的方式交给Clash内核解析。
3. 如何添加订阅源？
   - 自己修改配置文件： 配置文件规则参考 [clash.wiki](https://clash.wiki/configuration/configuration-reference.html) ，慢慢读下去，照猫画虎，很好配置的。
4. 如何添加自己的节点？
    - 内置了一个 provider_diy.yaml 配置文件，此文件用于添加私有节点，配置方法参考[代理配置规则](https://clash.wiki/configuration/outbound.html)

## 内核相关

1. Clash内核使用哪个？ 目前(2024)建议是使用官方ClashPremium版本，虽然不再更新，但并没有影响使用，而其他内核虽然新功能较多，但使用问题也较多，未来可能会在不断完善过程中变得更好或有更好的替代品。


