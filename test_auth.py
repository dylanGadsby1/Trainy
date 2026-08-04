import urllib.request
import base64

usernames = [
    "rttapi_dylan.p.gadsby",
    "rttapi_dylanpgadsby",
    "dylan.p.gadsby@gmail.com",
    "rttapi_dylan_p_gadsby",
    "rttapi_dylan.p.gadsby@gmail.com",
    "rttapi_dylangadsby"
]
passwords = [
    "196304",
    "mefnYw-zykcaj-ryhka7"
]

url = "https://api.rtt.io/api/v1/json/search/EUS"

found = False
for u in usernames:
    if found: break
    for p in passwords:
        creds = f"{u}:{p}"
        b64 = base64.b64encode(creds.encode()).decode()
        req = urllib.request.Request(url, headers={'Authorization': f'Basic {b64}'})
        try:
            with urllib.request.urlopen(req) as response:
                if response.status == 200:
                    print(f"SUCCESS: {u} : {p}")
                    found = True
                    break
        except urllib.error.HTTPError as e:
            pass # print(f"Failed {u}:{p} - {e.code}")
        except Exception as e:
            pass

if not found:
    print("All combinations failed.")
