# RSS 镜像部署

生产只保留 `docker-compose.production.yml`、`update.sh`、私有 `.env.production` 和备份。源码及构建工具留在开发机和 CI。ZJU_Platform 继续调用 `https://rss.tuotuzju.com`，账号及订阅继续保存在原 MySQL 中。

## 构建与发布

推送 `master` 后 GitHub Actions 执行账号测试、构建 Linux AMD64 镜像并检查运行镜像不包含应用源码、测试或 source map。成功后发布到当前仓库所属 GHCR 包，生成 `sha-提交号` 标签及不可变摘要，并上传 `rss-deploy-提交号` artifact。使用 artifact 中的 `image.env` 获取镜像摘要，不使用 `latest`。

GHCR 包必须能被服务器拉取：公开包可匿名访问，私有包需由管理员先执行 `docker login ghcr.io`，使用仅有读取包权限的凭据。不要把登录凭据放进仓库或 Compose。

## 现有生产服务迁移

1. 确认 Caddy、主站、磁盘及内存正常，停止未完成的构建；不在生产重新编译。
2. 从 CI artifact 下载 Compose、脚本和 image.env，放入独立部署目录。保留原部署目录，不删除源文件或数据。
3. 从原部署目录安全复制 `.env.production`，权限设为 600，保留数据库密码和 AUTH_CODE。将 `FEED_MODE` 改为 `metadata`，把 CI 摘要写入 `WEWE_RSS_IMAGE`。
4. 固定项目名为 `wewe-rss-beta`；现有外部卷必须为 `wewe-rss-beta_wewe-rss-beta-db`。卷不存在时停止，不能新建空库代替。数据库容器必须已经运行。
5. 核对并执行：

```sh
chmod 600 .env.production
sh update.sh ghcr.io/ayanami-wu/wewe-rss-beta@sha256:真实摘要
```

脚本拉取镜像，保留旧镜像、备份数据库，然后仅 `up --no-build --no-deps app`。应用健康失败自动恢复旧应用镜像；不自动恢复数据库。旧运行镜像缺失时会在修改容器前失败，需要先准备可靠回滚镜像。

RSS 应用限制为 512 MB 内存（不增加 swap）、0.5 CPU、128 个进程、320 MB Node 堆；日志每个文件 10 MB，最多 3 个。数据库保持现有配置。本轮不做数据库迁移设计变化。限额并不证明运行负载安全；若 RSS 内存不足而退出，先分析，不直接提高生产限额。

## 验收

检查运行容器镜像摘要、健康状态、资源限额、Caddy 和主站健康。通过主平台现有管理服务读取账号及订阅，核对数量。必要的 Feed 测试限定为 `?limit=1&mode=metadata`，不得使用全量全文 Feed 做健康检查。真实多账号采集需至少两个有效账号，账号登录由用户完成。

## 回滚

备份保存在部署目录 `backups/时间/`；旧镜像保留为 `wewe-rss-beta:rollback-时间`。需要手动回滚时，将 `.env.production` 的 `WEWE_RSS_IMAGE` 改为该旧镜像，再执行：

```sh
docker compose -p wewe-rss-beta --env-file .env.production -f docker-compose.production.yml up -d --no-build --no-deps app
```

不执行 `down -v`、镜像清理或数据库重建。数据库恢复必须单独核对备份并确认，不因应用失败自动覆盖数据。

## GHCR 网络受阻时

CI artifact 同时提供 `rss-runtime.tar.gz`、SHA-256 校验文件和 `image-id.txt`。可在开发机下载完整 artifact，再通过 SSH 上传部署目录，无需向生产传输源码或凭据。校验和不通过时停止；加载后按不可变镜像 ID 运行同一个部署脚本：

```sh
sha256sum -c rss-runtime.tar.gz.sha256
docker load -i rss-runtime.tar.gz
sh update.sh "$(cat image-id.txt)"
```

脚本在本地镜像 ID 模式下只使用已加载镜像，不重试 GHCR；备份、资源限制和回滚行为相同。
