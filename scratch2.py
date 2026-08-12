import urllib.request
import json
import ssl
from datetime import datetime

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

refresh_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MTE4NzIzZC00M2FjLTRlMTMtYThiMi02YzhkMWRjYmNjZTIiLCJpc3MiOiJodHRwczovL2FwaS1wb3J0YWwucnR0LmlvIn0.K6_AWC4WdUdkx5GebMotjifGjHG21Z5cLkFP-LIVKsg"
url = "https://data.rtt.io/api/get_access_token"
req = urllib.request.Request(url, headers={'Authorization': f'Bearer {refresh_token}'}, method='GET')
access_token = json.loads(urllib.request.urlopen(req, context=ctx).read().decode())['token']

dep_url = "https://data.rtt.io/gb-nr/location?code=CCH&filterTo=HAV"
req = urllib.request.Request(dep_url, headers={'Authorization': f'Bearer {access_token}', 'Accept': 'application/json'}, method='GET')
res = urllib.request.urlopen(req, context=ctx)
data = json.loads(res.read().decode())
services = data.get('services', [])
print(f"Total services with filterTo=HAV: {len(services)}")
for s in services[:3]:
    identity = s['scheduleMetadata']['identity']
    date = s['scheduleMetadata']['departureDate']
    det_url = f"https://data.rtt.io/gb-nr/service?identity={identity}&departureDate={date}"
    req2 = urllib.request.Request(det_url, headers={'Authorization': f'Bearer {access_token}', 'Accept': 'application/json'}, method='GET')
    try:
        res2 = urllib.request.urlopen(req2, context=ctx)
        data2 = json.loads(res2.read().decode())
        locs = data2.get('service', {}).get('locations', [])
        cch = next((l for l in locs if 'CCH' in (l.get('location', {}).get('shortCodes') or [])), None)
        hav = next((l for l in locs if 'HAV' in (l.get('location', {}).get('shortCodes') or [])), None)
        if cch and hav:
            cch_dep_sched = cch['temporalData'].get('departure', {}).get('scheduleAdvertised', 'N/A')
            cch_dep_real = cch['temporalData'].get('departure', {}).get('realtimeForecast', 'N/A')
            hav_arr_sched = hav['temporalData'].get('arrival', {}).get('scheduleAdvertised', 'N/A')
            hav_arr_real = hav['temporalData'].get('arrival', {}).get('realtimeForecast', 'N/A')
            print(f"Train {identity}: CCH(Sched {cch_dep_sched[-8:-3]}, Real {cch_dep_real[-8:-3]}) -> HAV(Sched {hav_arr_sched[-8:-3]}, Real {hav_arr_real[-8:-3]})")
    except Exception as e:
        print(f"Failed {identity}: {e}")
