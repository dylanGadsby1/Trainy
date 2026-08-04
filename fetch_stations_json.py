import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

url = "https://raw.githubusercontent.com/davwheat/uk-railway-stations/main/stations.json"
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, context=ctx) as response:
        data = json.loads(response.read().decode())
        
        valid_stations = []
        for station in data:
            name = station.get("stationName", "")
            crs = station.get("crsCode", "")
            lat = station.get("lat")
            lon = station.get("long")
            
            if crs and lat is not None and lon is not None:
                valid_stations.append({
                    "name": name,
                    "crs": crs,
                    "lat": lat,
                    "lon": lon
                })
                
        # Sort by name
        valid_stations.sort(key=lambda x: x["name"])
        
        # Serialize to minimal JSON
        json_str = json.dumps(valid_stations, separators=(',', ':'))
        
        # Swift string literal
        swift_code = f'let ukStationsJSON = """\n{json_str}\n"""\n'
        
        with open("ukStations_json_generated.swift", "w") as f:
            f.write(swift_code)
            
        print(f"Generated JSON string with {len(valid_stations)} stations.")
except Exception as e:
    print("Error:", e)
