import urllib.request
import ssl

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI4MTE4NzIzZC00M2FjLTRlMTMtYThiMi02YzhkMWRjYmNjZTIiLCJpc3MiOiJodHRwczovL2FwaS1wb3J0YWwucnR0LmlvIn0.K6_AWC4WdUdkx5GebMotjifGjHG21Z5cLkFP-LIVKsg"
urls_to_try = [
    "https://api.rtt.io/api/v1/json/search/EUS",
    "https://data.rtt.io/api/v1/json/search/EUS"
]

for url in urls_to_try:
    print(f"Testing {url} with Bearer Auth")
    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {token}'})
    try:
        with urllib.request.urlopen(req, context=ctx) as response:
            if response.status == 200:
                print(f"SUCCESS with Bearer! Endpoint works.")
                break
    except urllib.error.HTTPError as e:
        print(f"Failed Bearer: {e.code}")
    except Exception as e:
        print(f"Failed Bearer: {e}")
        
    print(f"Testing {url} with Basic Auth (username=token)")
    import base64
    b64 = base64.b64encode(f"{token}:".encode()).decode()
    req = urllib.request.Request(url, headers={'Authorization': f'Basic {b64}'})
    try:
        with urllib.request.urlopen(req, context=ctx) as response:
            if response.status == 200:
                print(f"SUCCESS with Basic! Endpoint works.")
                break
    except urllib.error.HTTPError as e:
        print(f"Failed Basic: {e.code}")
    except Exception as e:
        print(f"Failed Basic: {e}")
