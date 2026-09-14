#!/usr/bin/env -S uv run
# /// script
# dependencies = ["bleak", "pillow"]
# ///
"""Niimbot D110 over BLE. Protocol from github.com/MultiMote/niimbluelib.

  niim.py info   printer + loaded label (RFID) info
  niim.py test   print a 12x22mm test label (fits any D110 roll)
"""
import asyncio
import sys

from bleak import BleakClient, BleakScanner
from PIL import Image, ImageDraw

SERVICE = "e7810a71-73ae-499d-8c15-faa9aef0c3f2"
PRINTHEAD_PX = 96  # D110, 203dpi = 8px/mm
DENSITY = 2  # 1-3
LABEL_WITH_GAPS = 1
# request cmd -> response cmd (PrinterInfo 0x40 replies 0x40 + info type)
RESPONSE = {0xC1: 0xC2, 0x21: 0x31, 0x23: 0x33, 0x01: 0x02, 0x20: 0x30, 0x03: 0x04, 0x13: 0x14,
            0x15: 0x16, 0xE3: 0xE4, 0xA3: 0xB3, 0xF3: 0xF4, 0x1A: 0x1B}
INFO_TYPES = {8: "model_id", 9: "software_version", 10: "battery", 11: "serial", 12: "hardware_version"}


def encode(cmd: int, data: bytes = b"\x01") -> bytes:
    chk = cmd ^ len(data)
    for b in data:
        chk ^= b
    return bytes([0x55, 0x55, cmd, len(data), *data, chk, 0xAA, 0xAA])


def decode(buf: bytearray) -> list[tuple[int, bytes]]:
    """Pop complete packets off the front of buf (notifications may split/merge them)."""
    out = []
    while (start := buf.find(b"\x55\x55")) != -1 and len(buf) >= start + 4:
        del buf[:start]
        end = 4 + buf[3] + 3
        if len(buf) < end:
            break
        cmd, data, chk = buf[2], bytes(buf[4 : 4 + buf[3]]), buf[4 + buf[3]]
        if buf[end - 2 : end] == b"\xaa\xaa" and encode(cmd, data)[-3] == chk:
            out.append((cmd, data))
        del buf[:end]
    return out


def image_packets(img: Image.Image) -> list[bytes]:
    """1-bit image, PRINTHEAD_PX wide, one row per feed line -> 0x85 bitmap / 0x84 empty row packets."""
    assert img.mode == "1" and img.width == PRINTHEAD_PX
    rows = [bytes(~b & 0xFF for b in img.crop((0, y, img.width, y + 1)).tobytes()) for y in range(img.height)]
    out, y = [], 0
    while y < len(rows):
        n = 1
        while y + n < len(rows) and rows[y + n] == rows[y] and n < 255:
            n += 1
        row, pos = rows[y], y.to_bytes(2)
        if any(row):
            chunk = PRINTHEAD_PX // 8 // 3  # black-pixel count per third of the printhead
            counts = bytes(sum(bin(b).count("1") for b in row[i * chunk : (i + 1) * chunk]) for i in range(3))
            out.append(encode(0x85, pos + counts + bytes([n]) + row))
        else:
            out.append(encode(0x84, pos + bytes([n])))
        y += n
    return out


def test_image(length_px=240) -> Image.Image:  # 240px = 30mm roll
    # drawn as the label reads (landscape), rotated 90° CW for printDirection "left".
    # 1px rectangles inset 0/1/2mm: count survivors per edge to measure clipping.
    img = Image.new("1", (length_px, PRINTHEAD_PX), 1)
    d = ImageDraw.Draw(img)
    for mm in range(3):
        d.rectangle((mm * 8, mm * 8, img.width - 1 - mm * 8, img.height - 1 - mm * 8), outline=0)
    d.text((30, 28), "niim", fill=0, font_size=20)
    d.text((30, 52), "start ->", fill=0, font_size=16)
    return img.transpose(Image.Transpose.ROTATE_270)


def calib_image(length_px=240) -> Image.Image:
    # 2px rulers at 0..6mm from each end; line k spans (k+1)/7 of the width (staircase),
    # so the shortest surviving line at each end = mm clipped there.
    img = Image.new("1", (length_px, PRINTHEAD_PX), 1)
    d = ImageDraw.Draw(img)
    for mm in range(7):
        h = (mm + 1) * PRINTHEAD_PX // 7 - 1
        d.rectangle((mm * 8, 0, mm * 8 + 1, h), fill=0)  # start end, staircase from top
        d.rectangle((length_px - 2 - mm * 8, PRINTHEAD_PX - 1 - h, length_px - 1 - mm * 8, PRINTHEAD_PX - 1), fill=0)
    d.text((80, 36), "calib", fill=0, font_size=20)
    return img.transpose(Image.Transpose.ROTATE_270)


class Printer:
    def __init__(self, client, char):
        self.client, self.char, self.buf, self.replies = client, char, bytearray(), asyncio.Queue()

    def on_notify(self, _, data):
        self.buf.extend(data)
        for pkt in decode(self.buf):
            self.replies.put_nowait(pkt)

    async def send(self, cmd, data=b"\x01"):
        await self.client.write_gatt_char(self.char, encode(cmd, data), response=False)
        await asyncio.sleep(0.01)
        want = 0x40 + data[0] if cmd == 0x40 else RESPONSE[cmd]
        while True:
            rcmd, rdata = await asyncio.wait_for(self.replies.get(), 3)
            if rcmd == want:
                return rdata
            if rcmd in (0x00, 0xDB):  # not supported / print error
                sys.exit(f"cmd 0x{cmd:02x} got {'not supported' if rcmd == 0 else 'print error'}: {rdata.hex()}")
            print(f"  (skipped 0x{rcmd:02x} {rdata.hex()} while waiting for 0x{want:02x})")

    async def print_image(self, img: Image.Image):
        await self.send(0xC1)  # connect
        await self.send(0x21, bytes([DENSITY]))
        await self.send(0x23, bytes([LABEL_WITH_GAPS]))
        await self.send(0x01)  # print start
        await self.send(0x20)  # print clear
        await self.send(0x03)  # page start
        await self.send(0x13, img.height.to_bytes(2) + img.width.to_bytes(2))
        await self.send(0x15, (1).to_bytes(2))  # quantity
        for pkt in image_packets(img):
            await self.client.write_gatt_char(self.char, pkt, response=False)
            await asyncio.sleep(0.01)
        await self.send(0xE3)  # page end
        for _ in range(100):  # ponytail: 30s cap, raise if long labels ever time out
            s = await self.send(0xA3)  # status: page u16, print %, feed %, [.. error @8]
            print(f"status page={int.from_bytes(s[:2])} print={s[2]}% feed={s[3]}%")
            if len(s) == 10 and s[8]:
                sys.exit(f"printer error 0x{s[8]:02x}")
            if int.from_bytes(s[:2]) >= 1 and s[2] == 100 and s[3] == 100:
                break
            await asyncio.sleep(0.3)
        await self.send(0xF3)  # print end


def parse_rfid(d: bytes) -> dict:
    if len(d) < 9:
        return {"label": "no RFID tag read"}
    i = 8
    barcode = d[i + 1 : i + 1 + d[i]].decode(errors="replace"); i += 1 + d[i]
    serial = d[i + 1 : i + 1 + d[i]].decode(errors="replace"); i += 1 + d[i]
    return {"barcode": barcode, "serial": serial, "total": int.from_bytes(d[i : i + 2]),
            "used": int.from_bytes(d[i + 2 : i + 4]), "type": d[i + 4]}


async def main(cmd):
    dev = await BleakScanner.find_device_by_filter(lambda d, _: (d.name or "").startswith("D110"), timeout=15)
    if not dev:
        sys.exit("No D110 found. Is it on and not connected to your phone?")
    print("found", dev.address, dev.name)
    async with BleakClient(dev) as client:
        char = next(
            c for c in client.services.get_service(SERVICE).characteristics
            if {"notify", "write-without-response"} <= set(c.properties)
        )
        p = Printer(client, char)
        await client.start_notify(char, p.on_notify)
        if cmd == "info":
            for t, name in INFO_TYPES.items():
                print(name, (await p.send(0x40, bytes([t]))).hex())
            rfid = await p.send(0x1A)
            print("rfid raw", rfid.hex(), parse_rfid(rfid))
        elif cmd in ("test", "calib"):
            await p.print_image(test_image() if cmd == "test" else calib_image())
            print("done")


def selftest():
    assert encode(0x40, b"\x08") == bytes.fromhex("555540010849aaaa")
    buf = bytearray(encode(0x48, b"\x09\x00") + encode(0x49, b"\x01")[:3])
    assert decode(buf) == [(0x48, b"\x09\x00")] and buf == encode(0x49, b"\x01")[:3]
    img = Image.new("1", (PRINTHEAD_PX, 4), 1)
    img.putpixel((0, 1), 0); img.putpixel((95, 1), 0); img.putpixel((0, 2), 0); img.putpixel((95, 2), 0)
    pkts = image_packets(img)
    assert pkts[0] == encode(0x84, b"\x00\x00\x01")  # blank row 0
    row = bytes([0x80] + [0] * 10 + [0x01])  # MSB-first: col 0 -> bit 7, col 95 -> bit 0
    assert pkts[1] == encode(0x85, b"\x00\x01" + b"\x01\x00\x01" + b"\x02" + row)  # rows 1-2 merged
    assert pkts[2] == encode(0x84, b"\x00\x03\x01") and len(pkts) == 3
    assert test_image().size == calib_image().size == (PRINTHEAD_PX, 240)


if __name__ == "__main__":
    selftest()
    if len(sys.argv) > 1:
        asyncio.run(main(sys.argv[1]))
