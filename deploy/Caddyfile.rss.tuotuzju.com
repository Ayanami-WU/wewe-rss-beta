# Merge this site block into the server's existing Caddyfile.
# Keep the application bound to 127.0.0.1:4000; expose it through Caddy only.
rss.tuotuzju.com {
    @dashboard path /dash /dash/*
    respond @dashboard 404

    encode gzip
    reverse_proxy 127.0.0.1:4000
}
