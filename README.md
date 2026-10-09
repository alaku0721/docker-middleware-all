# 中间件运维实验环境（Docker Compose）

一个面向 **Linux 运维学习与求职** 的中间件一键部署环境。在全新 WSL (Ubuntu) 上 clone 本项目后，执行一条命令即可拉起 **14 个常用中间件**，覆盖数据库、缓存、Web、消息队列、搜索引擎、高可用、监控、对象存储八大类，并附带备份、持久化验证与排障记录。

## 一、快速开始

```bash
git clone <你的仓库地址>
cd ops-middleware-lab
bash setup.sh            # 环境自检 + 自动装 Docker + 配置加速源 + 启动全部服务
```

`setup.sh` 会自动完成：检测/安装 Docker → 配置国内镜像加速 → 逐个拉取镜像（失败自动切换 3 个加速源）→ `docker compose up -d` 启动。

## 二、访问入口（启动后）

| 服务            | 类别   | 端口    | 验证方式                                                     |
| ------------- | ---- | ----- | -------------------------------------------------------- |
| Nginx         | Web  | 8080  | 打开 `http://localhost:8080` 看到 "nginx is running"         |
| Tomcat        | 应用   | 8081  | 打开 `http://localhost:8081/myapp/` 看到 "Hello from Tomcat" |
| MySQL         | 数据库  | 3306  | `docker exec -it mysql mysql -uroot -proot123456`        |
| PostgreSQL    | 数据库  | 5432  | `docker exec -it postgres psql -U postgres`              |
| MongoDB       | 文档库  | 27017 | `docker exec -it mongodb mongosh -u root -p mongo123`    |
| Redis         | 缓存   | 6379  | `docker exec -it redis redis-cli -a redis123`            |
| ZooKeeper     | 协调   | 2181  | `docker exec -it zookeeper zkServer.sh status`           |
| Kafka         | 消息   | 9092  | 见下方「Kafka 验证」                                            |
| RabbitMQ      | 消息   | 15672 | 打开 `http://localhost:15672`（admin/rabbit123）             |
| Elasticsearch | 搜索   | 9200  | `curl http://localhost:9200`                             |
| Keepalived    | 高可用  | —     | `docker exec -it keepalived ip addr` 看 VIP 是否漂移          |
| Prometheus    | 监控   | 9090  | 打开 `http://localhost:9090`                               |
| Grafana       | 可视化  | 3000  | 打开 `http://localhost:3000`（admin/admin123）               |
| MinIO         | 对象存储 | 9001  | 打开 `http://localhost:9001`（minioadmin/minioadmin123）     |

> 端口已避开常见冲突：Nginx 用 8080（非 80），Tomcat 用 8081（非 8080），RabbitMQ 管理台用 15672，MinIO 控制台用 9001。

## 三、Kafka 生产/消费验证

```bash
# 建一个 3 分区的 topic
docker exec -it kafka kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic test --partitions 3 --replication-factor 1

# 生产（终端 A，逐行输入后 Ctrl+C 退出）
docker exec -it kafka kafka-console-producer.sh --bootstrap-server localhost:9092 --topic test

# 消费（终端 B，实时打印）
docker exec -it kafka kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic test --from-beginning
```

## 四、备份与持久化验证

```bash
bash setup.sh backup
```

会自动：① 用 `mysqldump` 导出 `demo` 库到 `backups/`；② 向 Redis 写一个 key → 重启容器 → 读回，验证 AOF 持久化生效。

## 五、常用运维命令

```bash
bash setup.sh check    # 仅环境自检
docker compose ps      # 查看所有容器状态
docker compose logs -f mysql   # 跟踪某服务日志（排障首选）
bash setup.sh down     # 停止并清理容器（数据卷保留，重启后数据仍在）
```

## 六、目录结构

```
ops-middleware-lab/
├── docker-compose.yml          # 14 个中间件的编排定义
├── setup.sh                    # 一键部署（含环境自检/装Docker/加速源/镜像兜底）
├── mysql/
│   ├── conf/custom.cnf         # 字符集 utf8mb4 等自定义配置
│   └── init/01-init.sql        # 首次启动自动建表+灌演示数据
├── redis/redis.conf            # 密码/ AOF / maxmemory 淘汰策略
├── nginx/
│   ├── html/index.html         # 静态页面（验证卷挂载）
│   └── conf/default.conf       # 含反向代理到 tomcat 的示例
├── tomcat/webapps/myapp/       # 挂载部署的应用
├── keepalived/keepalived.conf  # VIP 高可用配置示例
├── prometheus/prometheus.yml   # 监控采集配置
└── backups/                    # setup.sh backup 生成的备份文件
```

## 七、14 个中间件一句话速记

| 中间件                  | 定位                            |
| -------------------- | ----------------------------- |
| MySQL / PostgreSQL   | 关系型数据库（PostgreSQL 是开源新宠）      |
| MongoDB              | 文档数据库，存 JSON                  |
| Redis                | 内存缓存 + 计数器                    |
| Nginx                | Web 服务器 + 反向代理                |
| Tomcat               | Java Web 应用容器                 |
| ZooKeeper            | 分布式协调（老 Kafka 依赖它）            |
| Kafka / RabbitMQ     | 消息队列（Kafka 高吞吐、RabbitMQ 协议标准） |
| Elasticsearch        | 全文搜索 + 日志检索                   |
| Keepalived           | 高可用，虚拟 IP 漂移                  |
| Prometheus + Grafana | 监控采集 + 可视化                    |
| MinIO                | 对象存储（兼容 S3）                   |

## 七、排障记录（真实踩过的坑）

1. **`could not find expected ':'` 的 YAML 报错**：肉眼看着对，其实是编辑器里混入了**中文全角冒号 `：`**。排查命令：`grep -nP '[^\x00-\x7F]' docker-compose.yml`。教训：配置文件里的冒号、引号必须用英文半角。
2. **第三方组织镜像拉取被拒**：`bitnami/kafka:3.6` 走加速源偶发 `denied` / `not found`（DaoCloud 对第三方命名空间有白名单限制）。解决：`setup.sh` 内置了「直连 → 3 个加速源」的自动兜底；也可手动 `docker pull 加速源地址/镜像` 后 `docker tag` 改回标准名。
3. **容器端口冲突**：本环境特意把 Nginx 用 8080、Tomcat 用 8081，避免和本机 80/8080 冲突。

## 八、学习定位

这套环境覆盖 Linux 运维岗 JD 里点名的中间件（MySQL/Redis/Tomcat/ZK/Kafka/Nginx），配套课程见《运维实战课》系列（L01 MySQL → L02 Redis → L03 Tomcat → L04 ZK+Kafka）。
