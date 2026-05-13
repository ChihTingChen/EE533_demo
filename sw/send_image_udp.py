#!/usr/bin/env python
# -*- coding: utf-8 -*-

import socket
import sys
import struct
import time
import subprocess

FPGA_IP = '10.0.7.255'
FPGA_PORT = 9999

PADDING = '\x00\x00\x00\x00\x00\x00'

def load_image_bytes(hex_file):
    data = ''
    
    f = open(hex_file, 'r')
    for line in f:
        line = line.strip()
        if not line or line.startswith('//'): 
            continue
        val = int(line, 16)
        data += struct.pack(">Q", val)
    f.close()
    
    return data

def send_chunk(chunk_data):
    payload = PADDING + chunk_data
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.sendto(payload, (FPGA_IP, FPGA_PORT))
    s.close()

def main():
    if len(sys.argv) < 2:
        print "Usage: python send_image_udp.py <image.hex>"
        sys.exit(1)

    hex_file = sys.argv[1]
    img_data = load_image_bytes(hex_file)

    if len(img_data) != 2352:
        print "WARNING: Expected 2352 bytes, got %d" % len(img_data)

    chunk1 = img_data[:1176]
    chunk2 = img_data[1176:]

    print "Sending Packet 1 (%d bytes payload)..." % len(chunk1)
    send_chunk(chunk1)
    
    time.sleep(0.1)
    
    print "Sending Packet 2 (%d bytes payload)..." % len(chunk2)
    send_chunk(chunk2)

    print "\nPackets sent! Waiting for AI inference to complete..."
    time.sleep(1)

    print "\n=== Inference Result ==="
    subprocess.call(["./idsreg", "status"])

if __name__ == '__main__':
    main()