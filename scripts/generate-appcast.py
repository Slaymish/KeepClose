#!/usr/bin/env python3
"""Generate a one-release Sparkle feed; sign it afterwards with Sparkle sign_update."""
import argparse
from pathlib import Path
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--version', required=True)
parser.add_argument('--build', required=True, type=int)
parser.add_argument('--archive', required=True, type=Path)
parser.add_argument('--signature', required=True)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
rss = ET.Element('rss', version='2.0')
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = 'Keep Close'
ET.SubElement(channel, 'link').text = 'https://github.com/slaymish/KeepClose'
ET.SubElement(channel, 'description').text = 'Keep Close updates for macOS'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = 'Keep Close ' + args.version
ET.SubElement(item, '{%s}version' % ns).text = str(args.build)
ET.SubElement(item, '{%s}shortVersionString' % ns).text = args.version
ET.SubElement(item, '{%s}minimumSystemVersion' % ns).text = '14.0'
ET.SubElement(item, 'link').text = 'https://github.com/slaymish/KeepClose/releases/tag/v' + args.version
ET.SubElement(item, 'enclosure', {
    'url': 'https://github.com/slaymish/KeepClose/releases/download/v%s/KeepClose-macOS.zip' % args.version,
    'length': str(args.archive.stat().st_size), 'type': 'application/octet-stream',
    '{%s}edSignature' % ns: args.signature,
})
ET.indent(rss)
ET.ElementTree(rss).write(args.output, encoding='utf-8', xml_declaration=True)
