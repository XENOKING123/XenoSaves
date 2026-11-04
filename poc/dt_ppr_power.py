#!/usr/bin/env python3
import argparse
import os
import socket
import struct

from poc.dt_ppr_client import derive_with_oracle
from poc.dt_psk_client import command_header, recv_exact, recv_record, send_record

CAPTURED_BODY = bytes.fromhex(
    "c6e469cc8242a4e1c3dbdaf6e206d6c6"
    "7bab7d471e62dc60cae6b9596a783b7e"
    "5c843cc6d72700002c01000002000000"
    "82020000010000006e70000000000000"
    "00000000000000000000000007006013"
    "0100000007006013"
)


def main():
    parser = argparse.ArgumentParser(description="Send a PS5 Data Transfer power request")
    parser.add_argument("host")
    parser.add_argument("--oracle-host", default="192.168.0.125")
    parser.add_argument("--oracle-port", type=int, default=9022)
    parser.add_argument("--hardware", type=int, default=3)
    args = parser.parse_args()
    assert len(CAPTURED_BODY) == 88
    body = bytearray(CAPTURED_BODY)
    struct.pack_into("<I", body, 44, args.hardware)

    with socket.create_connection((args.host, 1004), timeout=10) as sock:
        client_value = os.urandom(16)
        sock.sendall(client_value + bytes(48))
        server_value = recv_exact(sock, 64)[:16]
        send_key, recv_key, send_nonce, recv_nonce = derive_with_oracle(
            args.oracle_host, args.oracle_port, client_value, server_value
        )
        send_record(sock, send_key, send_nonce, 0, b"")
        send_record(sock, send_key, send_nonce, 1, command_header(0x91, len(body)))
        send_record(sock, send_key, send_nonce, 2, body)
        response = recv_record(sock, recv_key, recv_nonce, 0)
        print("[+] response header:", response.hex())
        if len(response) == 16:
            print("[+] result:", hex(struct.unpack_from("<I", response, 4)[0]))
            size = struct.unpack_from("<Q", response, 8)[0]
            if size:
                body = recv_record(sock, recv_key, recv_nonce, 1)
                print("[+] console info:", body.hex())


if __name__ == "__main__":
    main()
