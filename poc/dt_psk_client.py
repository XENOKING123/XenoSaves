#!/usr/bin/env python3
import argparse
import os
import socket
import struct

from cryptography.hazmat.primitives import cmac
from cryptography.hazmat.primitives.ciphers import algorithms
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

PSK = bytes.fromhex("59e63288b04e7f68f8b8db83861e0750")


SBOX = bytes.fromhex(
    "637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0"
    "b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b275"
    "09832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cf"
    "d0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2"
    "cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdb"
    "e0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08"
    "ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9e"
    "e1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16"
)
INV_SBOX = bytearray(256)
for _index, _value in enumerate(SBOX):
    INV_SBOX[_value] = _index
INV_SBOX = bytes(INV_SBOX)


def gf_mul(a, b):
    result = 0
    while b:
        if b & 1:
            result ^= a
        a = ((a << 1) ^ 0x11B) if a & 0x80 else a << 1
        b >>= 1
    return result & 0xFF


def expand_key(key):
    words = [list(key[offset:offset + 4]) for offset in range(0, 16, 4)]
    rcon = 1
    for index in range(4, 44):
        word = words[index - 1][:]
        if index % 4 == 0:
            word = word[1:] + word[:1]
            word = [SBOX[value] for value in word]
            word[0] ^= rcon
            rcon = gf_mul(rcon, 2)
        words.append([a ^ b for a, b in zip(words[index - 4], word)])
    return b"".join(bytes(word) for word in words)


def inv_shift_rows(state):
    output = [0] * 16
    for row in range(4):
        for column in range(4):
            output[row + 4 * column] = state[row + 4 * ((column - row) % 4)]
    return output


def inv_mix_columns(state):
    output = []
    for column in range(4):
        a = state[4 * column:4 * column + 4]
        output.extend((
            gf_mul(a[0], 14) ^ gf_mul(a[1], 11) ^ gf_mul(a[2], 13) ^ gf_mul(a[3], 9),
            gf_mul(a[0], 9) ^ gf_mul(a[1], 14) ^ gf_mul(a[2], 11) ^ gf_mul(a[3], 13),
            gf_mul(a[0], 13) ^ gf_mul(a[1], 9) ^ gf_mul(a[2], 14) ^ gf_mul(a[3], 11),
            gf_mul(a[0], 11) ^ gf_mul(a[1], 13) ^ gf_mul(a[2], 9) ^ gf_mul(a[3], 14),
        ))
    return output


def aes_dec(block):
    if len(block) != 16:
        raise ValueError("AES input must be one block")
    schedule = expand_key(PSK)
    state = [a ^ b for a, b in zip(block, schedule[160:176])]
    for round_number in range(9, 0, -1):
        state = inv_shift_rows(state)
        state = [INV_SBOX[value] for value in state]
        state = inv_mix_columns(state)
        round_key = schedule[16 * round_number:16 * round_number + 16]
        state = [a ^ b for a, b in zip(state, round_key)]
    state = inv_shift_rows(state)
    state = [INV_SBOX[value] for value in state]
    return bytes(a ^ b for a, b in zip(state, schedule[:16]))


def derive_keys(client_value, server_value):
    source = b"\x00\x10" + PSK + aes_dec(client_value) + aes_dec(server_value)
    output = []
    for counter in (1, 2, 3):
        mac = cmac.CMAC(algorithms.AES(PSK))
        mac.update(counter.to_bytes(2, "big") + source)
        output.append(mac.finalize())
    return output[0], output[1], output[2][:4], output[2][4:8]


def pad(plaintext):
    count = 16 - len(plaintext) % 16
    return plaintext + bytes(count - 1) + bytes([count])


def unpad(padded):
    if not padded:
        raise ValueError("empty plaintext")
    count = padded[-1]
    if count < 1 or count > 16 or len(padded) < count:
        raise ValueError("invalid record padding")
    return padded[:-count]


def send_record(sock, key, nonce_prefix, sequence, plaintext):
    padded = pad(plaintext)
    header = struct.pack("<QQQ", 8, sequence, len(padded))
    nonce = nonce_prefix + struct.pack("<Q", sequence)
    encrypted = AESGCM(key).encrypt(nonce, padded, header)
    sock.sendall(header + encrypted)


def recv_exact(sock, size):
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise EOFError(f"connection closed after {len(data)}/{size} bytes")
        data.extend(chunk)
    return bytes(data)


def recv_record(sock, key, nonce_prefix, sequence):
    header = recv_exact(sock, 24)
    version, wire_sequence, size = struct.unpack("<QQQ", header)
    if version != 8 or wire_sequence != sequence or size > 0x400000:
        raise ValueError(f"unexpected record header: {header.hex()}")
    encrypted = recv_exact(sock, size + 16)
    nonce = nonce_prefix + struct.pack("<Q", sequence)
    padded = AESGCM(key).decrypt(nonce, encrypted, header)
    return unpad(padded)


def command_header(cmd, body_size, sub=2, version=0x130):
    return struct.pack("<BBHIQ", cmd, sub, version, 0, body_size)


def command(cmd, body=b"", version=0x130):
    return command_header(cmd, len(body), version=version) + body


def main():
    parser = argparse.ArgumentParser(description="PS5 Data Transfer IPv6 PSK/AES-GCM client")
    parser.add_argument("host", help="PS5 IPv6 address; use %interface for a link-local address")
    parser.add_argument("--port", type=int, default=1004)
    parser.add_argument("--message", default="HELLO-DT-PSK")
    args = parser.parse_args()
    if ":" not in args.host:
        raise SystemExit("an IPv6 address is required: IPv4 selects the separate SblNcdtPpr KDF")

    with socket.create_connection((args.host, args.port), timeout=10) as sock:
        print("[*] connected; performing 64-byte AE handshake")
        client_value = os.urandom(16)
        sock.sendall(client_value + bytes(48))
        server_frame = recv_exact(sock, 64)
        server_value = server_frame[:16]
        send_key, recv_key, send_nonce, recv_nonce = derive_keys(client_value, server_value)

        print("[*] sending encrypted handshake completion record")
        send_record(sock, send_key, send_nonce, 0, b"")

        body = args.message.encode()
        print("[*] sending encrypted Echo header and body in separate records")
        send_record(sock, send_key, send_nonce, 1, command_header(0x92, len(body)))
        send_record(sock, send_key, send_nonce, 2, body)

        print("[*] waiting for encrypted Echo response")
        response = recv_record(sock, recv_key, recv_nonce, 0)
        print("[+] response:", response.hex())
        if len(response) >= 16:
            print("[+] response body:", response[16:])


if __name__ == "__main__":
    main()
