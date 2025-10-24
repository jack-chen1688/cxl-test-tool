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

# Wrap all lines in the Markdown file to 100 characters for better PDF formatting
fold -s -w 100 DCD-Inside-Out.md > DCD-Inside-Out-wrap.md

# Generate PDF from the wrapped Markdown file, using A4 paper and listings config
pandoc DCD-Inside-Out-wrap.md -o DCD-Qemu-Explanation.pdf \
  -V geometry=a4paper \
  -V geometry:left=0.5in \
  -V geometry:right=0.5in \
  -V geometry:top=0.5in \
  -V geometry:bottom=0.5in \
  --listings -H listings-setup.tex
