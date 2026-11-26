#!/bin/sh
# Empaqueta el addon en <dist>/Richarsilus-<versión>.zip con la carpeta Richarsilus/ dentro,
# lista para descomprimir en Interface\AddOns.
#
# Uso: tools/package.sh [versión esperada]
#   Si se pasa una versión (la etiqueta "v1.2.0" o "1.2.0"), debe coincidir con "## Version:" del TOC.
#
# Comprueba antes de empaquetar que cada fichero del TOC existe y que no hay ficheros .lua fuera del TOC.
# Variables opcionales: ADDON_DIRECTORY (carpeta del addon) y DIST_DIRECTORY (carpeta de salida).
# Imprime en la salida estándar la ruta del zip creado; los errores van a la salida de error.
set -eu

root_directory=$(cd "$(dirname "$0")/.." && pwd)
addon_directory=${ADDON_DIRECTORY:-"$root_directory/Richarsilus"}
dist_directory=${DIST_DIRECTORY:-"$root_directory/dist"}
toc_file="$addon_directory/Richarsilus.toc"

if [ ! -f "$toc_file" ]; then
  echo "error: TOC file not found: $toc_file" >&2
  exit 1
fi

version=$(tr -d '\r' < "$toc_file" | sed -n 's/^## Version:[[:space:]]*\([^[:space:]]*\).*$/\1/p')
if [ -z "$version" ]; then
  echo "error: no '## Version:' line in $toc_file" >&2
  exit 1
fi

if [ $# -gt 0 ]; then
  expected_version=${1#v}
  if [ "$expected_version" != "$version" ]; then
    echo "error: version $expected_version does not match the TOC version $version" >&2
    exit 1
  fi
fi

# Ficheros que carga el TOC (líneas que no son comentarios ni están vacías), con "/" como separador
# (\134 es la barra invertida en octal).
toc_entries=$(tr -d '\r' < "$toc_file" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^#/d' -e '/^$/d' | tr '\134' '/')
if [ -z "$toc_entries" ]; then
  echo "error: $toc_file does not list any file" >&2
  exit 1
fi

problems=0
for entry in $toc_entries; do
  if [ ! -f "$addon_directory/$entry" ]; then
    echo "error: listed in the TOC but missing: $entry" >&2
    problems=1
  fi
done

lua_files=$(cd "$addon_directory" && find . -type f -name '*.lua' | sed 's|^\./||' | sort)
for lua_file in $lua_files; do
  listed=0
  for entry in $toc_entries; do
    if [ "$entry" = "$lua_file" ]; then
      listed=1
    fi
  done
  if [ "$listed" -eq 0 ]; then
    echo "error: Lua file not listed in the TOC (the game would never load it): $lua_file" >&2
    problems=1
  fi
done

if [ "$problems" -ne 0 ]; then
  exit 1
fi

mkdir -p "$dist_directory"
dist_directory=$(cd "$dist_directory" && pwd)
archive="$dist_directory/Richarsilus-$version.zip"
rm -f "$archive"

# El zip siempre contiene la carpeta "Richarsilus/", sea cual sea el nombre de la carpeta de origen.
staging_directory=$(mktemp -d)
trap 'rm -rf "$staging_directory"' EXIT
cp -R "$addon_directory" "$staging_directory/Richarsilus"
(cd "$staging_directory" && zip -r -X -q "$archive" Richarsilus -x '*.DS_Store')

echo "$archive"
