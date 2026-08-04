import urllib.request
import urllib.parse
import json
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

refresh_token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MTE4NzIzZC00M2FjLTRlMTMtYThiMi02YzhkMWRjYmNjZTIiLCJpc3MiOiJodHRwczovL2FwaS1wb3J0YWwucnR0LmlvIn0.K6_AWC4WdUdkx5GebMotjifGjHG21Z5cLkFP-LIVKsg"
req = urllib.request.Request("https://data.rtt.io/api/get_access_token", headers={"Authorization": f"Bearer {refresh_token}"})
access_token = json.loads(urllib.request.urlopen(req, context=ctx).read().decode())['token']

req2 = urllib.request.Request("https://data.rtt.io/gb-nr/location?location=CCH", headers={"Authorization": f"Bearer {access_token}"})
data = json.loads(urllib.request.urlopen(req2, context=ctx).read().decode())
services = data.get('services', [])
if services:
    uid = services[0]['scheduleMetadata']['uniqueIdentity']
    encoded_uid = urllib.parse.quote(uid)
    
    url = f"https://data.rtt.io/gb-nr/service?uniqueIdentity={encoded_uid}"
    try:
        r = urllib.request.Request(url, headers={"Authorization": f"Bearer {access_token}"})
        res = urllib.request.urlopen(r, context=ctx)
        print(f"SUCCESS! {url}")
    except urllib.error.HTTPError as e:
        print(f"Failed {url}: {e.code}")
        print(e.read().decode())

