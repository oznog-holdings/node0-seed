# Caddy with the DNSimple DNS provider (design › Network: rung 1's certificates by DNS-01
# through the registrar's API). Stock Caddy lacks the module; this is Caddy's documented
# xcaddy build, both stages pinned by digest, the module by commit (it has no tags).
FROM caddy:2.11.4-builder@sha256:401121e61853cb9c7df83cba43e532e49a68e30f32921c7bdcb7a4912168c067 AS build
RUN xcaddy build v2.11.4 --with github.com/caddy-dns/dnsimple@0433343c56102ab9415e95486fb3dbba4a2e7d55
FROM caddy:2.11.4@sha256:0c994536bddb66445885237f1a5dcc1916bccea922661c76b4e9fc24061f9b52
COPY --from=build /usr/bin/caddy /usr/bin/caddy
