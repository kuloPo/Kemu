#!/usr/bin/env python3
"""Export the notices accompanying an Android product build for offline viewing."""
import argparse
import gzip
import html
from pathlib import Path
import xml.etree.ElementTree as ET


PARTITIONS = ('system', 'system_ext', 'product', 'vendor', 'odm',
              'system_dlkm', 'vendor_dlkm', 'odm_dlkm')


def render_notice(source):
    with gzip.open(source, 'rb') as stream:
        # AOSP can retain GPL form feeds, which XML 1.0 parsers reject.
        root = ET.fromstring(stream.read().replace(b'\x0c', b'\n'))
    if root.tag != 'licenses':
        raise ValueError('Invalid Android notice root: ' + str(source))
    names, contents = {}, {}
    for item in root:
        content_id = item.get('contentId')
        if item.tag == 'file-name':
            if not content_id:
                raise ValueError('Notice filename is missing a contentId: ' + str(source))
            name = ''.join(item.itertext()).strip()
            library = item.get('lib')
            names.setdefault(content_id, set()).add(name + (' [' + library + ']' if library else ''))
        elif item.tag == 'file-content':
            if not content_id or content_id in contents:
                raise ValueError('Missing or duplicate notice contentId: ' + str(source))
            contents[content_id] = ''.join(item.itertext())
    if not contents or names.keys() - contents.keys():
        raise ValueError('Missing Android license text: ' + str(source))
    sections = []
    for content_id, text in contents.items():
        files = '\n'.join(sorted(names.get(content_id, ())))
        sections.append('Files:\n' + files + '\n\n' + text.strip())
    return ('\n\n' + '=' * 72 + '\n\n').join(sections) + '\n'


def export_notices(product, destination):
    product, destination = Path(product), Path(destination)
    if not (product / 'system/etc/NOTICE.xml.gz').is_file():
        raise ValueError('The Android build is missing system/etc/NOTICE.xml.gz')
    notices = []
    for partition in PARTITIONS:
        source = product / partition / 'etc/NOTICE.xml.gz'
        if source.is_file():
            notices.append((partition, source.read_bytes(), render_notice(source)))
    destination.mkdir(parents=True, exist_ok=True)
    for partition, compressed, text in notices:
        (destination / (partition + '.xml.gz')).write_bytes(compressed)
        (destination / (partition + '.txt')).write_text(text, encoding='utf-8')
    present = {entry[0] for entry in notices}
    for partition in set(PARTITIONS) - present:
        for suffix in ('.xml.gz', '.txt'):
            (destination / (partition + suffix)).unlink(missing_ok=True)
    links = ''.join('<li><a href="' + partition + '.txt">' +
                    html.escape(partition) + '</a></li>\n'
                    for partition, _, _ in notices)
    (destination / 'index.html').write_text(
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<title>Android system notices</title></head><body>'
        '<h1>Android system notices</h1>'
        '<p>Copyright and license notices from the Android build shipped with Kemu, '
        'grouped by partition. Original NOTICE.xml.gz files are also included.</p>'
        '<ul>' + links + '</ul>'
        '<p>Android is a trademark of Google LLC.</p></body></html>\n', encoding='utf-8')
    return len(notices)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('product', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    try:
        print('Exported notices for', export_notices(args.product, args.destination), 'Android partitions')
    except (OSError, ValueError, ET.ParseError) as error:
        parser.exit(1, 'export-android-notices: ' + str(error) + '\n')
