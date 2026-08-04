import urllib.request
import json
import ssl
import time

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

refresh_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MTE4NzIzZC00M2FjLTRlMTMtYThiMi02YzhkMWRjYmNjZTIiLCJpc3MiOiJodHRwczovL2FwaS1wb3J0YWwucnR0LmlvIn0.K6_AWC4WdUdkx5GebMotjifGjHG21Z5cLkFP-LIVKsg"
url = "https://data.rtt.io/api/get_access_token"

for _ in range(10):
    try:
        req = urllib.request.Request(url, headers={'Authorization': f'Bearer {refresh_token}'}, method='GET')
        access_token = json.loads(urllib.request.urlopen(req, context=ctx).read().decode())['token']
        break
    except Exception:
        time.sleep(10)

endpoint = "https://data.rtt.io/gb-nr/location?location=EUS"
for _ in range(10):
    try:
        req = urllib.request.Request(endpoint, headers={'Authorization': f'Bearer {access_token}'}, method='GET')
        res = urllib.request.urlopen(req, context=ctx)
        data = json.loads(res.read().decode())
        with open("rtt_response.json", "w") as f:
            json.dump(data, f, indent=2)
        print("Saved rtt_response.json")
        break
    except urllib.error.HTTPError as e:
        if e.code == 429:
            print("429, waiting 10s...")
            time.sleep(10)
        else:
            print(f"Failed: {e}")
            break
    except Exception as e:
        print(f"Failed: {e}")
        break
