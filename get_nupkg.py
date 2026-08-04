import urllib.request
import json
import zipfile
import os

url = "https://www.nuget.org/api/v2/package/ParkSquare.RealTimeTrains/10.1.0"
req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
print("Downloading ParkSquare.RealTimeTrains v10...")
with urllib.request.urlopen(req) as res, open("package.zip", "wb") as f:
    f.write(res.read())

print("Extracting...")
with zipfile.ZipFile("package.zip", 'r') as zip_ref:
    zip_ref.extractall("package_extracted")

print("Files extracted:")
for root, dirs, files in os.walk("package_extracted"):
    for file in files:
        if file.endswith(".dll"):
            dll_path = os.path.join(root, file)
            print(f"Found DLL: {dll_path}")
            # Use strings to find endpoints
            os.system(f"strings '{dll_path}' | grep 'api/' > dll_strings.txt")
