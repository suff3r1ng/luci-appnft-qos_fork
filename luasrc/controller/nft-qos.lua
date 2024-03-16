-- Check if the file exists
if not nixio.fs.access("/tmp/dhcp.leases") then
    print("File /tmp/dhcp.leases does not exist.")
    return
end

local dhcp_leases = io.open("/tmp/dhcp.leases", "r")

-- Check if the file was opened successfully
if not dhcp_leases then
    print("Failed to open file /tmp/dhcp.leases.")
    return
end

-- Create a table to map IP addresses to hostnames
local ip_to_hostname = {}

-- Parse the DHCP leases
for line in dhcp_leases:lines() do
    -- Each line is a string like: "1625469943 00:0c:29:8d:9e:9a 192.168.1.2 myhostname 01:00:0c:29:8d:9e:9a"
    local _, _, ip, hostname = line:match("(%d+) (%S+) (%S+) (%S+)")

    -- Add the mapping from IP address to hostname to the table
    ip_to_hostname[ip] = hostname
end

-- Close the DHCP leases file
dhcp_leases:close()

module("luci.controller.nft-qos", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/nft-qos") then
		return
	end

	local e

	e = entry({"admin", "status", "realtime", "rate"}, template("nft-qos/rate"), _("Rate"), 5)
	e.leaf = true
	e.acl_depends = { "luci-app-nft-qos" }

	e = entry({"admin", "status", "realtime", "rate_status"}, call("action_rate"))
	e.leaf = true
	e.acl_depends = { "luci-app-nft-qos" }

	e = entry({"admin", "services", "nft-qos"}, cbi("nft-qos/nft-qos"), _("QoS over Nftables"), 60)
	e.leaf = true
	e.acl_depends = { "luci-app-nft-qos" }
end
function _action_rate(rv, n)
	local c = nixio.fs.access("/proc/net/ipv6_route") and
		io.popen("nft list chain inet nft-qos-monitor " .. n .. " 2>/dev/null") or
		io.popen("nft list chain ip nft-qos-monitor " .. n .. " 2>/dev/null")

	if c then
		for l in c:lines() do
			local _, i, p, b = l:match('^%s+ip ([^%s]+) ([^%s]+) counter packets (%d+) bytes (%d+)')
			if i and p and b then
				-- Replace the IP address with the hostname
				local hostname = ip_to_hostname[i] or i

				-- Use the hostname and IP address in your JSON output
				rv[#rv + 1] = {
					rule = {
						family = "inet",
						table = "nft-qos-monitor",
						chain = n,
						handle = 0,
						expr = {
							{ match = { right = hostname, ip = i } }, -- Add the IP address here
							{ counter = { packets = p, bytes = b } }
						}
					}
				}
			end
		end
		c:close()
	end
end

function action_rate()
	luci.http.prepare_content("application/json")
	local data = { nftables = {} }
	_action_rate(data.nftables, "upload")
	_action_rate(data.nftables, "download")
	luci.http.write_json(data)
end

