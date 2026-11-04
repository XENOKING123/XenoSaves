#!/usr/bin/env python3
import argparse
import json
import socket
import time


SRCH = b"SRCH * HTTP/1.1\ndevice-discovery-protocol-version:00030000\n"


def parse_response(response, address):
    fields = {}
    for line in response.splitlines():
        if b":" in line:
            key, value = line.split(b":", 1)
            fields[key.decode()] = value.decode()
    return {
        "host": address[0],
        "name": fields.get("host-name", "PS5"),
        "type": fields.get("host-type", "PS5"),
        "hostId": fields.get("host-id", ""),
        "firmware": fields.get("system-version", "unknown"),
        "requestPort": fields.get("host-request-port", ""),
        "network": fields.get("host-network", ""),
        "address": fields.get("host-address", ""),
    }


def discover(broadcast, timeout):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(0.2)
    sock.sendto(SRCH, (broadcast, 1006))
    consoles = {}
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            response, address = sock.recvfrom(4096)
        except socket.timeout:
            continue
        if response.startswith(b"HTTP/1.1"):
            console = parse_response(response, address)
            consoles[address[0]] = console
    sock.close()
    return list(consoles.values())


def main():
    parser = argparse.ArgumentParser(description="Discover PS5 consoles using SRCH")
    parser.add_argument("--broadcast", default="255.255.255.255")
    parser.add_argument("--timeout", type=float, default=2.0)
    args = parser.parse_args()
    print(json.dumps({"consoles": discover(args.broadcast, args.timeout)}), flush=True)


if __name__ == "__main__":
    main()
