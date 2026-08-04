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
        
        swift_array = "let ukStations: [UKStation] = [\n"
        count = 0
        for station in data:
            name = station.get("stationName", "")
            crs = station.get("crsCode", "")
            lat = station.get("lat")
            lon = station.get("long")
            
            if crs and lat is not None and lon is not None:
                name = name.replace('"', '\\"')
                swift_array += f'    UKStation(name: "{name}", crs: "{crs}", coordinate: CLLocationCoordinate2D(latitude: {lat}, longitude: {lon})),\n'
                count += 1
                
        swift_array += "].sorted { $0.name < $1.name }\n"
        
        with open("ukStations_generated.swift", "w") as f:
            f.write(swift_array)
            
        print(f"Generated {count} stations.")
except Exception as e:
    print("Error:", e)
