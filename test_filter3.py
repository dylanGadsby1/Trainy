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

endpoints = [
    "https://data.rtt.io/gb-nr/location?location=EUS",
    "https://data.rtt.io/gb-nr/location?location=EUS&to=MAN",
    "https://data.rtt.io/gb-nr/location?location=EUS&destination=MAN",
    "https://data.rtt.io/gb-nr/location?location=EUS&filterLocation=MAN"
]

for endpoint in endpoints:
    req = urllib.request.Request(endpoint, headers={'Authorization': f'Bearer {access_token}'}, method='GET')
    res = urllib.request.urlopen(req, context=ctx)
    data = json.loads(res.read().decode())
    services = data.get('services', [])
    print(f"{endpoint}: {len(services)} services")

