set -eu
cd "$(dirname "$0")/../.."
SOURCE=${MGBA_PROFILE_SOURCE:-/tmp/greymecha_gba_sources/mgba-profile}
if [ ! -d "$SOURCE/.git" ]; then
    mkdir -p "$(dirname "$SOURCE")"
    git clone --depth 1 --branch 0.10.5 https://github.com/mgba-emu/mgba.git "$SOURCE"
fi
OUTPUT=${MGBA_PROFILE_BUILD:-/tmp/greymecha_gba_memory_profile}
python3 tools/memory_profile/instrument_mgba.py "$SOURCE" ${MGBA_PROFILE_CONTROL_FLAG:-}
cmake -S "$SOURCE" -B "$OUTPUT" -G Ninja -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release -DBUILD_QT=OFF -DBUILD_SDL=OFF -DBUILD_GL=OFF -DBUILD_GLES2=OFF -DBUILD_GLES3=OFF -DBUILD_LIBRETRO=OFF -DBUILD_STATIC=ON -DBUILD_SHARED=OFF -DBUILD_LTO=OFF -DUSE_DEBUGGERS=OFF -DUSE_FFMPEG=OFF -DUSE_ZLIB=OFF -DUSE_MINIZIP=OFF -DUSE_PNG=OFF -DUSE_LIBZIP=OFF -DUSE_SQLITE3=OFF -DUSE_ELF=OFF -DUSE_LUA=OFF -DUSE_LZMA=OFF -DUSE_DISCORD_RPC=OFF -DM_CORE_GB=OFF
cmake --build "$OUTPUT" --target gba-memory-profile -j 6
