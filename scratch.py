import urllib.request
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

refresh_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MTE4NzIzZC00M2FjLTRlMTMtYThiMi02YzhkMWRjYmNjZTIiLCJpc3MiOiJodHRwczovL2FwaS1wb3J0YWwucnR0LmlvIn0.K6_AWC4WdUdkx5GebMotjifGjHG21Z5cLkFP-LIVKsg"
url = "https://data.rtt.io/api/get_access_token"
req = urllib.request.Request(url, headers={'Authorization': f'Bearer {refresh_token}'}, method='GET')
access_token = json.loads(urllib.request.urlopen(req, context=ctx).read().decode())['token']

dep_url = "https://data.rtt.io/gb-nr/location?location=KGX"
req = urllib.request.Request(dep_url, headers={'Authorization': f'Bearer {access_token}', 'Accept': 'application/json'}, method='GET')
res = urllib.request.urlopen(req, context=ctx)
data = json.loads(res.read().decode())
services = data.get('services', [])

uid = services[0]['scheduleMetadata']['uniqueIdentity']
parts = uid.split(':')
if len(parts) == 3:
    namespace, service_id, date = parts
    endpoint = f"https://data.rtt.io/{namespace}/service/{namespace}/{service_id}/{date}"
    print(f"Trying {endpoint}")
    req = urllib.request.Request(endpoint, headers={'Authorization': f'Bearer {access_token}', 'Accept': 'application/json'}, method='GET')
    try:
        res = urllib.request.urlopen(req, context=ctx)
        print("SUCCESS")
        service_data = json.loads(res.read().decode())
        print(json.dumps(service_data, indent=2)[:1000])
    except Exception as e:
        print(f"Failed: {e}")
