# danmu-api 一键部署脚本



一个用于在 Linux 服务器上一键部署 [danmu_api](https://github.com/huangxd-/danmu_api) 的 Shell 脚本。自动识别系统、切换国内软件源、安装 Docker、配置镜像加速，并以交互方式完成部署；同时提供可逐项选择的卸载功能。

## 特性



- **自动识别系统**：兼容 Debian、Ubuntu、CentOS、Rocky Linux、AlmaLinux 等常见发行版
- **国内源加速**：自动切换阿里云 APT / YUM 源，加速依赖安装
- **Docker 镜像加速**：自动写入多个国内镜像源，提升拉取速度
- **交互式部署**：部署时手动输入 TOKEN、ADMIN_TOKEN、端口和缓存目录
- **分项卸载**：卸载时逐项询问，按需保留容器、缓存、镜像、Docker 或系统源
- **幂等设计**：已安装 Docker 会跳过；已存在 `daemon.json` 不会被覆盖

## 支持的系统



系统家族代表系统换源策略Debian 系Debian、Ubuntu切换阿里云 APT 源RHEL 系（现代）Rocky Linux、AlmaLinux、CentOS Stream系统源保持默认RHEL 系（CentOS 7）CentOS 7切换阿里云 vault 归档源



## 快速开始



### 1. 下载脚本

```
bash <(curl -fsSL https://raw.githubusercontent.com/SunMoonWithYou/danmu/main/install.sh)
```

### 2. 选择操作

运行后出现菜单：

```
==============================
   danmu-api 管理脚本
==============================
1) 安装 / 重新部署
2) 卸载
3) 退出
请选择 [1-3]:
```



### 3. 安装

选择 `1` 后依次输入：

| 输入项             | 说明                         | 默认值             |
| :----------------- | :--------------------------- | :----------------- |
| 普通 TOKEN         | 访问 API 的令牌              | `87654321`         |
| 管理员 ADMIN_TOKEN | 访问管理后台的令牌，**必填** | 无                 |
| 映射端口           | 宿主机对外端口               | `9321`             |
| 缓存目录           | 持久化数据目录               | `/opt/danmu/cache` |

安装完成后会输出访问地址：

```
==========================================
安装完成！
API 地址：http://服务器IP:端口/TOKEN
管理后台：http://服务器IP:端口/ADMIN_TOKEN
缓存目录：/opt/danmu/cache
==========================================
```



> 请确认服务器防火墙或云厂商安全组已放行所填端口。

### 4. 卸载

选择 `2` 后，脚本会依次询问 5 个项目，每项独立处理：

| 序号 | 询问项         | 选 `y`                     | 选 `n` 或回车 |
| :--- | :------------- | :------------------------- | :------------ |
| 1    | 删除容器       | 删除容器                   | 保留          |
| 2    | 删除缓存目录   | 删除目录                   | 保留          |
| 3    | 删除镜像       | 删除镜像                   | 保留          |
| 4    | 卸载 Docker    | 卸载 Docker 及镜像加速配置 | 保留          |
| 5    | 还原系统软件源 | 用备份还原                 | 保留          |

不存在的项目会显示 `[跳过]` 并继续询问下一项，全程不会中断。

## 部署后使用

### API 示例

bash

```
# 搜索动漫
curl "http://服务器IP:9321/87654321/api/v2/search/anime?keyword=生万物"

# 获取弹幕
curl "http://服务器IP:9321/87654321/api/v2/comment/1?format=json"
```



### 播放器配置

以 senplayer 为例，在「设置 → 弹幕设置 → 自定义弹幕 API」中填写：

```
http://服务器IP:9321/你的TOKEN
```



其他支持弹幕 API 的播放器（Forward、Hills、Yamby 等）配置方式类似。

### 管理后台

浏览器访问：

```
http://服务器IP:9321/你的ADMIN_TOKEN
```



可进行环境变量配置、日志查看、接口调试、本地弹幕上传等操作。

## 常用维护命令

bash

```
# 查看容器状态
docker ps

# 查看实时日志
docker logs -f danmu-api

# 重启容器
docker restart danmu-api

# 更新镜像并重启
docker pull logvar/danmu-api:latest
docker rm -f danmu-api
# 然后重新运行脚本选择「安装」或手动 docker run
```



## 安全建议

- **务必修改默认 TOKEN**：默认值 `87654321` 仅适合内网测试，公网部署请改成强密码
- **设置强 ADMIN_TOKEN**：管理后台权限较高，建议使用复杂密码
- **及时更新镜像**：关注上游项目的安全更新，定期 `docker pull` 最新镜像
- **限制端口访问**：如无公网使用需求，建议通过防火墙限制端口来源 IP

## 常见问题

### 外部无法访问

1. 确认容器运行中：`docker ps` 显示状态为 `Up`
2. 本机测试：`curl http://127.0.0.1:9321/你的TOKEN/api/v2/search/anime?keyword=测试`
3. 检查云厂商安全组是否放行端口
4. 检查系统防火墙（如 `ufw`、`firewalld`）规则

### 镜像拉取缓慢

脚本已自动配置国内镜像加速。如仍缓慢，可手动编辑 `/etc/docker/daemon.json` 增加或替换镜像源，然后执行：

bash

```
systemctl daemon-reload
systemctl restart docker
```



### 修改 TOKEN 或端口

环境变量在容器启动时传入，修改需重建容器。重新运行脚本选择「安装」，填入新值即可覆盖旧容器。

## 目录结构

```
.
├── danmu.sh      # 一键部署脚本
└── README.md     # 说明文档
```



## 免责声明

本脚本仅用于简化 [danmu_api](https://github.com/huangxd-/danmu_api) 的部署流程，不对上游项目的功能、稳定性及合规性负责。请遵守上游项目及所在地区的相关法律法规，合理使用。

```
如果需要，我可以再补一份 `LICENSE` 建议或给脚本加上版本号与 `--help` 参数。
```
