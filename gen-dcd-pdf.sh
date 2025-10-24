#!/bin/bash

# Check and install system prerequisites
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

fold -s -w 100 DCD-Qemu-Explanation.md > DCD-Qemu-Explanation-wrap.md
# Wrap all lines in the Markdown file to 100 characters for better PDF formatting
python3 number_and_toc_md.py DCD-Qemu-Explanation-wrap.md DCD-Qemu-Explanation-Final.md
# markdown-toc DCD-Qemu-Explanation-Final.md


# Generate PDF from the wrapped Markdown file, using A4 paper and listings config
pandoc DCD-Qemu-Explanation-Final.md -o DCD-Qemu-Explanation.pdf \
  -V geometry=a4paper \
  -V geometry:left=0.5in \
  -V geometry:right=0.5in \
  -V geometry:top=0.5in \
  -V geometry:bottom=0.5in \
  --listings -H listings-setup.tex
