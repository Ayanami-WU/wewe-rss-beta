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

```sh
docker compose --env-file .env.production \
  -f docker-compose.production.yml up -d --build
docker compose --env-file .env.production \
  -f docker-compose.production.yml ps
curl --fail http://127.0.0.1:4000/
```

将 `deploy/Caddyfile.rss.tuotuzju.com` 的站点块合并到现有 Caddyfile，确认配置并重载：

```sh
caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
curl --fail --retry 5 --retry-delay 2 https://rss.tuotuzju.com/dash/
```

首次进入 Dashboard 时使用 `.env.production` 中的 `AUTH_CODE`。WeRead 账号令牌由 WeWe RSS 保存到数据库，数据库卷和 `.env.production` 都不能提交或公开。

## 回滚与维护

- 回滚前保留当前镜像和数据库卷；不要删除 `wewe-rss-beta-db`；
- 生产升级前先执行 MySQL 备份；
- `PLATFORM_URL` 仍然是外部微信读书适配服务，当前 beta 部署不改变这一依赖；
- Caddy 的 HTTPS 必须以真实证书和 `curl https://rss.tuotuzju.com/dash/` 验证为准。
