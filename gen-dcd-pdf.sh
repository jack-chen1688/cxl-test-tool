#!/bin/bash

# Usage: ./gen-dcd-pdf.sh <input.md>
if [ $# -ne 1 ]; then
  echo "Usage: $0 <input.md>"
  exit 1
fi

INPUT_MD="$1"
BASENAME="$(basename "$INPUT_MD" .md)"
WRAP_MD="${BASENAME}-wrap.md"
FINAL_MD="${BASENAME}-final.md"
OUTPUT_PDF="${BASENAME}.pdf"

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

#pandoc --number-sections "$WRAP_MD" -o "$FINAL_MD"

#python3 number_and_toc_md.py "$WRAP_MD" "$FINAL_MD"
# markdown-toc "$FINAL_MD"

# Generate PDF from the processed Markdown file, using A4 paper and listings config
pandoc "$INPUT_MD" -o "$OUTPUT_PDF" \
  -V geometry=a4paper \
  -V geometry:left=0.6in \
  -V geometry:right=0.6in \
  -V geometry:top=0.5in \
  -V geometry:bottom=0.5in \
  --no-highlight  -H wrap-fvextra.tex
#   --listings -H listings-setup.tex
