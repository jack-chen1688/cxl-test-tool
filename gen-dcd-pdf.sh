#!/bin/bash
# Check and install prerequisites
REQUIRED_PKGS=(pandoc texlive-full)
MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    MISSING_PKGS+=("$pkg")
  fi
done
if [ ${#MISSING_PKGS[@]} -ne 0 ]; then
  echo "Installing missing packages: ${MISSING_PKGS[*]}"
  sudo apt-get update
  sudo apt-get install -y "${MISSING_PKGS[@]}"
fi

pandoc DCD-Inside-Out.md -o DCD-Qemu-Explanation.pdf \
  -V geometry=a3paper \
  -V geometry:landscape \
  -V geometry:left=0.5in \
  -V geometry:right=0.5in \
  -V geometry:top=0.5in \
  -V geometry:bottom=0.5in \
  --listings -H listings-setup.tex
