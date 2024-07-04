# docker-ocserv
A set of Docker images of OpenConnect VPN server (ocserv)

### Caddy layer4 proxy config
```
"layer4": {
	"servers": {
		"example": {
			"listen": [":443"],
			"routes": [
				{
					"match": [
						{
							"tls": {"sni": ["ocserv.example.com"]}
						}
					],
					"handle": [
						{
							"handler": "proxy",
							"upstreams": [
								{"dial": ["ocserv.address.local:443"]}
							]
						}
					]
				},
				{
					"match": [
						{
							"not": [
								{
									"tls": {"sni": ["ocserv.example.com"]}
								}
							]
						}
					],
					"handle": [
						{
							"handler": "proxy",
							"upstreams": [
								{"dial": ["localhost:444"]}
							]
						}
					]
				}
			]
		}
	}
},
```