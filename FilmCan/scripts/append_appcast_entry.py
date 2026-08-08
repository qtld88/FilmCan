#!/usr/bin/env python3
"""Insert one <item> into an appcast.xml, newest-first. Used by package_release.sh."""
import sys
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)


def build_item(version, short_version, dmg_url, ed_signature, length, pub_date, notes, min_system_version):
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {short_version}"
    ET.SubElement(item, "pubDate").text = pub_date
    ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = version
    ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = short_version
    ET.SubElement(item, f"{{{SPARKLE_NS}}}minimumSystemVersion").text = min_system_version
    desc = ET.SubElement(item, "description")
    desc.text = notes
    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", dmg_url)
    enclosure.set(f"{{{SPARKLE_NS}}}edSignature", ed_signature)
    enclosure.set("length", length)
    enclosure.set("type", "application/octet-stream")
    return item


def main():
    if len(sys.argv) != 9:
        print(
            "usage: append_appcast_entry.py <appcast.xml> <version> <short_version> "
            "<dmg_url> <ed_signature> <length> <pub_date> <notes>",
            file=sys.stderr,
        )
        sys.exit(1)

    path, version, short_version, dmg_url, ed_signature, length, pub_date, notes = sys.argv[1:]

    tree = ET.parse(path)
    channel = tree.getroot().find("channel")
    if channel is None:
        print(f"error: {path} has no <channel> element", file=sys.stderr)
        sys.exit(1)

    for existing in channel.findall("item"):
        existing_version = existing.find(f"{{{SPARKLE_NS}}}version")
        if existing_version is not None and existing_version.text is not None and existing_version.text.strip() == version.strip():
            print(f"error: appcast already has an item for version {version}", file=sys.stderr)
            sys.exit(1)

    item = build_item(version, short_version, dmg_url, ed_signature, length, pub_date, notes, "13.0")

    first_item = channel.find("item")
    if first_item is not None:
        first_item_index = list(channel).index(first_item)
        channel.insert(first_item_index, item)
    else:
        channel.append(item)

    ET.indent(tree, space="    ")
    tree.write(path, encoding="utf-8", xml_declaration=True)
    with open(path, "a") as f:
        f.write("\n")


if __name__ == "__main__":
    main()
