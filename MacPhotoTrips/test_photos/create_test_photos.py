"""
Create test photos with GPS EXIF data for simulator testing.

Generates small JPEG images with embedded GPS coordinates matching
real trip destinations (Istanbul, London, Paris, etc.) and varied dates.

Usage:
    python create_test_photos.py

Then drag the generated photos onto the iOS Simulator window.
"""

import struct
from PIL import Image
from datetime import datetime, timedelta
import os

# Test locations: (city, lat, lon, color_rgb, dates)
# Dates spread across trips to test trip detection
TEST_PHOTOS = [
    # Home base: Istanbul
    ("istanbul_home_1", 41.0082, 28.9784, (30, 60, 90), "2024:01:15 10:00:00"),
    ("istanbul_home_2", 41.0150, 28.9500, (30, 60, 95), "2024:01:20 14:00:00"),
    ("istanbul_home_3", 41.0200, 29.0100, (30, 60, 100), "2024:02:10 09:00:00"),
    ("istanbul_home_4", 41.0050, 28.9900, (30, 60, 105), "2024:03:05 11:00:00"),
    ("istanbul_home_5", 41.0100, 28.9700, (30, 60, 110), "2024:03:15 16:00:00"),
    ("istanbul_home_6", 41.0120, 28.9800, (30, 60, 115), "2024:04:20 10:00:00"),
    ("istanbul_home_7", 41.0090, 28.9850, (30, 60, 120), "2024:05:10 13:00:00"),
    ("istanbul_home_8", 41.0070, 28.9750, (30, 60, 125), "2024:06:01 09:00:00"),
    ("istanbul_home_9", 41.0110, 28.9820, (30, 60, 130), "2024:07:15 11:00:00"),
    ("istanbul_home_10", 41.0095, 28.9770, (30, 60, 135), "2024:09:01 14:00:00"),

    # Trip 1: London (March 2024)
    ("london_1", 51.5074, -0.1278, (100, 40, 40), "2024:03:20 08:00:00"),
    ("london_2", 51.5014, -0.1419, (110, 40, 40), "2024:03:21 12:00:00"),
    ("london_3", 51.5155, -0.1410, (120, 40, 40), "2024:03:22 15:00:00"),
    ("london_4", 51.5033, -0.1196, (130, 40, 40), "2024:03:23 10:00:00"),

    # Trip 2: Paris (May 2024)
    ("paris_1", 48.8566, 2.3522, (50, 50, 100), "2024:05:15 09:00:00"),
    ("paris_2", 48.8584, 2.2945, (55, 50, 105), "2024:05:16 11:00:00"),
    ("paris_3", 48.8606, 2.3376, (60, 50, 110), "2024:05:17 14:00:00"),

    # Trip 3: Rome (July 2024)
    ("rome_1", 41.9028, 12.4964, (80, 60, 30), "2024:07:20 10:00:00"),
    ("rome_2", 41.8902, 12.4922, (85, 65, 30), "2024:07:21 13:00:00"),
    ("rome_3", 41.9009, 12.4833, (90, 70, 30), "2024:07:22 16:00:00"),
    ("rome_4", 41.8986, 12.4769, (95, 75, 30), "2024:07:23 09:00:00"),

    # Trip 4: Multi-stop Greece (August 2024)
    ("athens_1", 37.9838, 23.7275, (40, 80, 60), "2024:08:05 08:00:00"),
    ("athens_2", 37.9715, 23.7267, (45, 85, 60), "2024:08:06 12:00:00"),
    ("santorini_1", 36.3932, 25.4615, (50, 90, 70), "2024:08:08 10:00:00"),
    ("santorini_2", 36.4618, 25.3753, (55, 95, 75), "2024:08:09 15:00:00"),

    # Trip 5: Barcelona (October 2024)
    ("barcelona_1", 41.3851, 2.1734, (70, 40, 70), "2024:10:10 09:00:00"),
    ("barcelona_2", 41.4036, 2.1744, (75, 45, 75), "2024:10:11 11:00:00"),
    ("barcelona_3", 41.3818, 2.1685, (80, 50, 80), "2024:10:12 14:00:00"),
]


def _to_dms(decimal_degrees):
    """Convert decimal degrees to (degrees, minutes, seconds) as rationals."""
    d = abs(decimal_degrees)
    degrees = int(d)
    m = (d - degrees) * 60
    minutes = int(m)
    seconds = round((m - minutes) * 60 * 100)  # hundredths of seconds
    return degrees, minutes, seconds


def _write_gps_exif(img, lat, lon, date_str):
    """Write GPS and date EXIF data into a PIL Image using raw EXIF bytes."""
    import io
    import struct

    # Build minimal EXIF with GPS IFD
    # This is a simplified approach - we'll write the EXIF after saving
    pass


def create_photo(name, lat, lon, color, date_str, output_dir):
    """Create a 400x300 JPEG with GPS EXIF data."""
    img = Image.new("RGB", (400, 300), color)

    # We need piexif or manual EXIF writing for GPS data
    # Let's try piexif first, fall back to exiftool-style approach
    try:
        import piexif

        # GPS data
        lat_ref = "N" if lat >= 0 else "S"
        lon_ref = "E" if lon >= 0 else "W"
        lat_d, lat_m, lat_s = _to_dms(lat)
        lon_d, lon_m, lon_s = _to_dms(lon)

        gps_ifd = {
            piexif.GPSIFD.GPSLatitudeRef: lat_ref.encode(),
            piexif.GPSIFD.GPSLatitude: ((lat_d, 1), (lat_m, 1), (lat_s, 100)),
            piexif.GPSIFD.GPSLongitudeRef: lon_ref.encode(),
            piexif.GPSIFD.GPSLongitude: ((lon_d, 1), (lon_m, 1), (lon_s, 100)),
        }

        exif_ifd = {
            piexif.ExifIFD.DateTimeOriginal: date_str.encode(),
            piexif.ExifIFD.DateTimeDigitized: date_str.encode(),
        }

        zeroth_ifd = {
            piexif.ImageIFD.DateTime: date_str.encode(),
        }

        exif_dict = {"0th": zeroth_ifd, "Exif": exif_ifd, "GPS": gps_ifd}
        exif_bytes = piexif.dump(exif_dict)

        path = os.path.join(output_dir, f"{name}.jpg")
        img.save(path, "JPEG", exif=exif_bytes, quality=90)
        return path

    except ImportError:
        # No piexif - save without EXIF, user will need to install it
        path = os.path.join(output_dir, f"{name}.jpg")
        img.save(path, "JPEG", quality=90)
        print(f"WARNING: piexif not installed. {name}.jpg saved WITHOUT GPS data.")
        print("Install with: pip install piexif")
        return path


def main():
    output_dir = os.path.dirname(os.path.abspath(__file__))
    os.makedirs(output_dir, exist_ok=True)

    print(f"Creating {len(TEST_PHOTOS)} test photos in {output_dir}/")
    print()

    for name, lat, lon, color, date_str in TEST_PHOTOS:
        path = create_photo(name, lat, lon, color, date_str, output_dir)
        city = name.rsplit("_", 1)[0].replace("_", " ").title()
        print(f"  {name}.jpg  ({city}: {lat:.4f}, {lon:.4f}  {date_str[:10]})")

    print()
    print("Done! To add to simulator:")
    print("  1. Make sure the simulator is running")
    print("  2. Drag all .jpg files onto the simulator window")
    print("  OR run: xcrun simctl addmedia booted *.jpg")


if __name__ == "__main__":
    main()
