# Entorno de desarrollo: Lua 5.1 (la version que usa el cliente de WoW),
# busted (tests), luacheck (analisis estatico), shellcheck y zip (empaquetado de releases).
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends lua5.1 liblua5.1-0-dev luarocks build-essential git ca-certificates \
    unzip zip shellcheck \
 && rm -rf /var/lib/apt/lists/*

RUN luarocks --lua-version=5.1 install busted \
 && luarocks --lua-version=5.1 install luacheck

WORKDIR /addon
CMD ["sh", "-c", "luacheck . && busted"]
