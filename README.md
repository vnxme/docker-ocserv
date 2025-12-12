# docker-ocserv
A set of Docker images of OpenConnect VPN server (ocserv)

### OCServ behind Caddy listening for OCServ traffic on a dedicated TCP port
```caddyfile
{
	layer4 {
		tcp/:443 {
			# Handle ocserv traffic
			@ocserv tls sni ocsev.example.com
			route @ocserv {
				proxy tcp/ocserv.machine.local:443
			}

			# Proxy anything else to another machine
			route {
				proxy tcp/another.machine.local:443
			}
		}
	}
}

# No site blocks should use 443/tcp simultaneously
```

### OCServ behind Caddy multiplexing OCServ and other TLS traffic on a single TCP port
```caddyfile
{
	servers {
		listener_wrappers {
			# Proxy ocserv traffic if any
			layer4 {
				@ocserv tls sni ocsev.example.com
				route @ocserv {
					proxy tcp/ocserv.machine.local:443
				}
			}

			# Terminate TLS and serve HTTPS on 443/tcp
			tls
		}
	}
}

*.example.com {
	respond "OK" 200
}
```
