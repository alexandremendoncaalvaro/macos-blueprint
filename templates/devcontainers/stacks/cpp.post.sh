#!/usr/bin/env bash
# C++ stack post-create: install clangd + clang-format + clang-tidy and
# scaffold a minimal CMake + vcpkg layout if the project is empty.
# Defaults reflect personal preferences inferred from CorridorKey-Runtime:
#   - CMake 3.28+ / Ninja
#   - C++20 enforced
#   - vcpkg manifest mode
#   - Catch2 v3 for tests
#   - clang-format Google-derived (col 100, indent 4)
#   - clang-tidy strict checks
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# clangd / clang-format / clang-tidy are not in the base cpp image.
if command -v sudo >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends \
    clangd clang-format clang-tidy >/dev/null
fi

if [ ! -f "CMakeLists.txt" ]; then
  cat > CMakeLists.txt <<'CMAKE'
cmake_minimum_required(VERSION 3.28)
project(app LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(MSVC)
  add_compile_options(/W4 /permissive-)
else()
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

add_executable(app src/main.cpp)
CMAKE
  echo "[post-create:cpp] wrote CMakeLists.txt"
fi

if [ ! -d "src" ]; then
  mkdir -p src
  cat > src/main.cpp <<'CPP'
#include <iostream>

int main() {
  std::cout << "ok\n";
  return 0;
}
CPP
  echo "[post-create:cpp] wrote src/main.cpp"
fi

if [ ! -f "vcpkg.json" ]; then
  local_dir_name="$(basename "$PWD")"
  cat > vcpkg.json <<JSON
{
  "name": "${local_dir_name//[^a-z0-9-]/-}",
  "version-string": "0.1.0",
  "dependencies": []
}
JSON
  echo "[post-create:cpp] wrote vcpkg.json"
fi

if [ ! -f "CMakePresets.json" ]; then
  cat > CMakePresets.json <<'JSON'
{
  "version": 6,
  "cmakeMinimumRequired": { "major": 3, "minor": 28, "patch": 0 },
  "configurePresets": [
    {
      "name": "debug",
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build/debug",
      "toolchainFile": "$env{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake",
      "cacheVariables": { "CMAKE_BUILD_TYPE": "Debug" }
    },
    {
      "name": "release",
      "inherits": "debug",
      "binaryDir": "${sourceDir}/build/release",
      "cacheVariables": { "CMAKE_BUILD_TYPE": "Release" }
    }
  ],
  "buildPresets": [
    { "name": "debug",   "configurePreset": "debug" },
    { "name": "release", "configurePreset": "release" }
  ]
}
JSON
  echo "[post-create:cpp] wrote CMakePresets.json"
fi

if [ ! -f ".clang-format" ]; then
  cat > .clang-format <<'YAML'
BasedOnStyle: Google
IndentWidth: 4
TabWidth: 4
UseTab: Never
ColumnLimit: 100
Standard: c++20
AccessModifierOffset: -2
PointerAlignment: Left
AllowShortFunctionsOnASingleLine: Inline
SortIncludes: CaseSensitive
IncludeBlocks: Regroup
NamespaceIndentation: None
YAML
  echo "[post-create:cpp] wrote .clang-format"
fi

if [ ! -f ".clang-tidy" ]; then
  cat > .clang-tidy <<'YAML'
Checks: >
  -*,
  bugprone-*,
  cert-*,
  cppcoreguidelines-*,
  modernize-*,
  performance-*,
  readability-*,
  -modernize-use-trailing-return-type,
  -readability-identifier-length,
  -cppcoreguidelines-avoid-magic-numbers,
  -readability-magic-numbers
WarningsAsErrors: ''
HeaderFilterRegex: '^(src|include)/'
FormatStyle: file
YAML
  echo "[post-create:cpp] wrote .clang-tidy"
fi
