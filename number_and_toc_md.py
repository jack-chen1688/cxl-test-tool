#!/usr/bin/env python3
import re
import click

def slugify(text):
    return re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')

@click.command()
@click.argument('input_file', type=click.Path(exists=True))
@click.argument('output_file', type=click.Path())
@click.option('--number-headers/--no-number-headers', default=True, help='Number level 3 headers (###).')
@click.option('--update-toc/--no-update-toc', default=False, help='Update the table of contents.')
def main(input_file, output_file, number_headers, update_toc):
    """Process a Markdown file to number level 3 headers and/or update the TOC."""
    with open(input_file, 'r') as f:
        lines = f.readlines()

    h1 = h2 = h3 = 0
    output = []
    toc = []

    for idx, line in enumerate(lines):
        m1 = re.match(r'^(#) (.*)', line)
        m2 = re.match(r'^(##) (.*)', line)
        m3 = re.match(r'^(###) ?(.*)', line)
        if m1:
            h1 += 1
            h2 = h3 = 0
            title = m1.group(2)
            anchor = slugify(title)
            toc.append(f"- [{title}](#{anchor})\n")
            output.append(f"# {title}\n")
        elif m2:
            h2 += 1
            h3 = 0
            title = m2.group(2)
            anchor = slugify(title)
            toc.append(f"  - [{title}](#{anchor})\n")
            output.append(f"## {title}\n")
        elif m3:
            h3 += 1
            title = m3.group(2).strip()
            num = f"{h1}.{h2}.{h3}"
            anchor = slugify(f"{num} {title}")
            if number_headers:
                toc.append(f"    - [{num} {title}](#{anchor})\n")
                output.append(f"### {num} {title}\n")
            else:
                toc.append(f"    - [{title}](#{anchor})\n")
                output.append(f"### {title}\n")
        else:
            output.append(line)

    if update_toc:
        # Replace the old TOC (first block after '# Table of Contents')
        new_output = []
        toc_started = False
        toc_ended = False
        for line in output:
            if not toc_started and line.strip() == '# Table of Contents':
                new_output.append(line)
                toc_started = True
                continue
            if toc_started and not toc_ended:
                if line.strip().startswith('#') and line.strip() != '# Table of Contents':
                    toc_ended = True
                    new_output.extend(toc)
                    new_output.append(line)
                # skip old toc lines
                continue
            new_output.append(line)
        output = new_output

    with open(output_file, 'w') as f:
        f.writelines(output)

if __name__ == '__main__':
    main()
