import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

refresh_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MTE4NzIzZC00M2FjLTRlMTMtYThiMi02YzhkMWRjYmNjZTIiLCJpc3MiOiJodHRwczovL2FwaS1wb3J0YWwucnR0LmlvIn0.K6_AWC4WdUdkx5GebMotjifGjHG21Z5cLkFP-LIVKsg"
req = urllib.request.Request("https://data.rtt.io/api/get_access_token", headers={"Authorization": f"Bearer {refresh_token}"})
with urllib.request.urlopen(req, context=ctx) as response:
    access_token = json.loads(response.read().decode())['token']

req2 = urllib.request.Request("https://data.rtt.io/gb-nr/location?location=CCH", headers={"Authorization": f"Bearer {access_token}"})
with urllib.request.urlopen(req2, context=ctx) as response:
    data = json.loads(response.read().decode())
    services = data.get('services', [])
    if services:
        first_service = services[0]
        uid = first_service.get('scheduleMetadata', {}).get('uniqueIdentity')
        print(f"UID: {uid}")
        
        # Try fetching full service details
        if uid:
            date = first_service.get('temporalData', {}).get('scheduleAdvertised', '')[:10]
            print(f"Date: {date}")
            urls = [
                f"https://data.rtt.io/gb-nr/service/{uid}/{date}",
                f"https://data.rtt.io/gb-nr/service/{uid}",
                f"https://data.rtt.io/api/v1/json/service/{uid}/{date.replace('-','/')}"
            ]
            for u in urls:
                try:
                    r = urllib.request.Request(u, headers={"Authorization": f"Bearer {access_token}"})
                    with urllib.request.urlopen(r, context=ctx) as res:
                        print(f"Success fetching {u}!")
                        service_data = json.loads(res.read().decode())
                        print("Keys in service data:", list(service_data.keys()))
                        break
                except Exception as e:
                    print(f"Failed {u}: {e}")
