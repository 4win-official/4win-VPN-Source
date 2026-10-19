#!/usr/bin/env python3
"""Update the generated RIPE operator IPv4 catalog.

The updater intentionally has no project-specific range data: all ranges come from
RIPE Stat's announced-prefixes response.  Use --input-dir for deterministic offline
fixtures named AS197207.json and AS44244.json.
"""
from __future__ import annotations

import argparse
import datetime as dt
import ipaddress
import json
import os
import pathlib
import tempfile
import urllib.parse
import urllib.request

ENDPOINT = "https://stat.ripe.net/data/announced-prefixes/data.json"
TIMEOUT_SECONDS = 20
OPERATORS = (
    ("mci", "MCI (Hamrah Aval)", "AS197207"),
    ("irancell", "Irancell", "AS44244"),
)


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0)


def iso_time(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).replace(tzinfo=None).isoformat(timespec="seconds")


def source_url(asn: str, start: str, end: str) -> str:
    q = urllib.parse.urlencode({"resource": asn, "starttime": start, "endtime": end})
    return f"{ENDPOINT}?{q}"

def resource_url(asn: str) -> str:
    return f"{ENDPOINT}?resource={asn}"


def load_response(asn: str, url: str, input_dir: pathlib.Path | None) -> dict:
    if input_dir is not None:
        path = input_dir / f"{asn}.json"
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    request = urllib.request.Request(url, headers={"User-Agent": "4win-vpn-operator-ipv4-updater/1"})
    with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        if response.status != 200:
            raise RuntimeError(f"{asn}: RIPE HTTP status {response.status}")
        return json.loads(response.read().decode("utf-8"))


def parse_response(asn: str, response: dict, query_end: str) -> tuple[list[tuple[int, int]], int, int, str]:
    if response.get("status") != "ok" or response.get("status_code") != 200:
        raise ValueError(f"{asn}: invalid RIPE status/resource response")
    data = response.get("data")
    if not isinstance(data, dict) or not isinstance(data.get("prefixes"), list):
        raise ValueError(f"{asn}: missing data.prefixes")
    if str(data.get("resource")) != asn.removeprefix("AS"):
        raise ValueError(f"{asn}: response resource mismatch")
    returned_at = response.get("time")
    if not isinstance(returned_at, str) or not returned_at:
        raise ValueError(f"{asn}: missing returned time")
    networks: list[ipaddress.IPv4Network] = []
    raw_ipv4_total = 0
    raw_ipv4 = 0
    end_dt = dt.datetime.fromisoformat(query_end.replace("Z", "+00:00")).replace(tzinfo=None)
    for item in data["prefixes"]:
        if not isinstance(item, dict) or not isinstance(item.get("prefix"), str):
            raise ValueError(f"{asn}: malformed prefix entry")
        prefix = item["prefix"]
        try:
            network = ipaddress.ip_network(prefix, strict=True)
        except ValueError as exc:
            raise ValueError(f"{asn}: invalid prefix {prefix!r}: {exc}") from exc
        timelines = item.get("timelines")
        if not isinstance(timelines, list):
            raise ValueError(f"{asn}: missing timelines for {prefix}")
        if network.version != 4:
            continue
        raw_ipv4_total += 1
        visible = False
        for timeline in timelines:
            if not isinstance(timeline, dict) or not isinstance(timeline.get("starttime"), str) or not isinstance(timeline.get("endtime"), str):
                raise ValueError(f"{asn}: malformed timeline for {prefix}")
            start = dt.datetime.fromisoformat(timeline["starttime"].replace("Z", "+00:00")).replace(tzinfo=None)
            finish = dt.datetime.fromisoformat(timeline["endtime"].replace("Z", "+00:00")).replace(tzinfo=None)
            if finish < start:
                raise ValueError(f"{asn}: reversed timeline for {prefix}")
            if start <= end_dt <= finish:
                visible = True
        if visible:
            raw_ipv4 += 1
            networks.append(network)
    collapsed: list[tuple[int, int]] = [
        (int(network.network_address), int(network.broadcast_address))
        for network in ipaddress.collapse_addresses(networks)
    ]
    if not collapsed:
        raise ValueError(f"{asn}: no visible IPv4 prefixes at query end")
    return collapsed, raw_ipv4_total, raw_ipv4, returned_at


def dart_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def generate(records: list[dict], output: pathlib.Path) -> None:
    lines = ["// GENERATED FILE. Run tools/update_operator_ipv4.py to refresh.", "", "class OperatorIpv4Snapshot {", "  const OperatorIpv4Snapshot({", "    required this.id,", "    required this.label,", "    required this.asn,", "    required this.sourceUrl,", "    required this.returnedAt,", "    required this.updatedAt,", "    required this.rawIpv4Count,", "    required this.visibleIpv4Count,", "    required this.collapsedTotalAddresses,", "    required this.ranges,", "  });", "", "  final String id;", "  final String label;", "  final String asn;", "  final String sourceUrl;", "  final String returnedAt;", "  final String updatedAt;", "  final int rawIpv4Count;", "  final int visibleIpv4Count;", "  final int collapsedTotalAddresses;", "  /// Inclusive [start, end] IPv4 integer ranges, sorted and disjoint.", "  final List<List<int>> ranges;", "}", "", "const operatorIpv4Snapshots = <OperatorIpv4Snapshot>[" ]
    for record in records:
        total = sum(hi - lo + 1 for lo, hi in record["ranges"])
        lines += ["  OperatorIpv4Snapshot(", f"    id: {dart_string(record['id'])},", f"    label: {dart_string(record['label'])},", f"    asn: {dart_string(record['asn'])},", f"    sourceUrl: {dart_string(record['source_url'])},", f"    returnedAt: {dart_string(record['returned_at'])},", f"    updatedAt: {dart_string(record['updated_at'])},", f"    rawIpv4Count: {record['raw_ipv4_total']},", f"    visibleIpv4Count: {record['raw_ipv4_count']},", f"    collapsedTotalAddresses: {total},", "    ranges: <List<int>>["]
        for lo, hi in record["ranges"]:
            lines.append(f"      <int>[{lo}, {hi}],")
        lines += ["    ],", "  ),"]
    lines += ["];", ""]
    content = "\n".join(lines)
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=output.name + ".", dir=str(output.parent), text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, output)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=pathlib.Path, help="Read AS*.json fixtures instead of using the network")
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("lib/data/operator_ipv4_snapshot.dart"))
    parser.add_argument("--query-endtime", help="Requested UTC endpoint time; defaults to RIPE's latest available query")
    args = parser.parse_args()
    explicit_end = args.query_endtime is not None
    end = args.query_endtime or iso_time(utc_now())
    end_dt = dt.datetime.fromisoformat(end.replace("Z", "+00:00"))
    if end_dt.tzinfo is not None:
        end = iso_time(end_dt)
    start = iso_time(end_dt - dt.timedelta(days=14))
    records = []
    for ident, label, asn in OPERATORS:
        url = source_url(asn, start, end) if explicit_end else resource_url(asn)
        response = load_response(asn, url, args.input_dir)
        returned_end = response.get("data", {}).get("query_endtime")
        if not isinstance(returned_end, str):
            raise ValueError(f"{asn}: missing data.query_endtime")
        endpoint = dt.datetime.fromisoformat(returned_end.replace("Z", "+00:00"))
        if endpoint.tzinfo is None:
            endpoint = endpoint.replace(tzinfo=dt.timezone.utc)
        authoritative_end = iso_time(endpoint)
        ranges, raw_total, raw_count, returned_at = parse_response(asn, response, authoritative_end)
        records.append({"id": ident, "label": label, "asn": asn, "source_url": url, "updated_at": authoritative_end + "Z", "returned_at": returned_at, "raw_ipv4_total": raw_total, "raw_ipv4_count": raw_count, "ranges": ranges})
    generate(records, args.output)
    for record in records:
        total = sum(hi - lo + 1 for lo, hi in record["ranges"])
        print(f"{record['asn']}: raw_ipv4={record['raw_ipv4_count']} collapsed_ranges={len(record['ranges'])} addresses={total} returned={record['returned_at']}")


if __name__ == "__main__":
    main()
