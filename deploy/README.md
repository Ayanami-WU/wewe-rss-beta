# rss.tuotuzju.com 部署说明

## 前置条件

- `rss.tuotuzju.com` 的 A/AAAA 记录指向实际服务器；
- 服务器已安装 Docker Compose 和 Caddy；
- 80/443 端口由 Caddy 统一接收；
- 4000 端口不对公网开放。

## 部署步骤

```sh
cp .env.production.example .env.production
openssl rand -hex 32
```

将生成的随机值分别填入 `MYSQL_ROOT_PASSWORD`、`MYSQL_PASSWORD` 和 `AUTH_CODE`。然后构建并启动：

如果服务器无法访问官方 npm registry，可在服务器的 `.env.production` 中将
`NPM_REGISTRY` 设置为可访问的 npm 镜像；它只影响构建阶段的 pnpm 安装。

```sh
docker compose --env-file .env.production \
  -f docker-compose.production.yml up -d --build
docker compose --env-file .env.production \
  -f docker-compose.production.yml ps
curl --fail http://127.0.0.1:4000/
curl --fail http://127.0.0.1:4000/feeds/all.atom
```

将 `deploy/Caddyfile.rss.tuotuzju.com` 的站点块合并到现有 Caddyfile，确认配置并重载：

```sh
caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
curl --fail --retry 5 --retry-delay 2 https://rss.tuotuzju.com/
curl --fail --retry 5 --retry-delay 2 https://rss.tuotuzju.com/feeds/all.atom
test "$(curl --silent --output /dev/null --write-out '%{http_code}' https://rss.tuotuzju.com/dash/)" = 404
```

生产部署为 headless backend，不提供 Dashboard；微信读书账号、订阅源和文章管理统一通过 ZJU_Platform 管理后台完成。WeRead 账号令牌由 WeWe RSS 保存到数据库，数据库卷和 `.env.production` 都不能提交或公开。

## 回滚与维护

- 回滚前保留当前镜像和数据库卷；不要删除 `wewe-rss-beta-db`；
- 生产升级前先执行 MySQL 备份；
- `PLATFORM_URL` 仍然是外部微信读书适配服务，当前 beta 部署不改变这一依赖；
- Caddy 的 HTTPS 必须以真实证书、根路径、feed API 和 `/dash/` 返回 404 验证为准；回滚时只移除 `/dash` 拒绝规则并恢复旧镜像。
