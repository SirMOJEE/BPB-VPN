// UID lookup for the per-app tunnel engine — DRAFT, not yet in the repo.
package xray

import (
	"bufio"
	"os"
	"strconv"
	"strings"

	M "github.com/xjasonlyu/tun2socks/v2/metadata"
)

// lookupUID finds the Linux UID that owns the socket with the given local
// (source) port, by reading /proc/net — the same technique NetGuard uses,
// and it needs no root. TCP sockets live in tcp/tcp6, UDP in udp/udp6.
// A connection's source port is unique per socket, so the port alone is
// enough to identify its owner. Returns ok=false when the socket is not
// (yet) listed — the caller then falls back to the connection's exit.
func lookupUID(network M.Network, srcPort uint16) (uid int32, ok bool) {
	files := []string{"/proc/net/tcp", "/proc/net/tcp6"}
	if network == M.UDP {
		files = []string{"/proc/net/udp", "/proc/net/udp6"}
	}
	for _, path := range files {
		if u, found := uidForPort(path, srcPort); found {
			return u, true
		}
	}
	return 0, false
}

// uidForPort scans one /proc/net/<proto> file for a socket whose local
// port matches. Each line is:
//
//	sl local_address rem_address st ... uid timeout inode
//
// local_address is hex IP:hex port (IP bytes little-endian); field 7 is
// the owning UID. Listening sockets (st 0A) are skipped: an ephemeral
// port never collides with a listener, and the app's outbound socket is
// the one we want.
func uidForPort(path string, srcPort uint16) (int32, bool) {
	f, err := os.Open(path)
	if err != nil {
		return 0, false
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) < 8 {
			continue
		}
		local := fields[1]
		i := strings.LastIndexByte(local, ':')
		if i < 0 {
			continue
		}
		port, err := strconv.ParseUint(local[i+1:], 16, 16)
		if err != nil || uint16(port) != srcPort {
			continue
		}
		if fields[3] == "0A" { // LISTEN — not an outbound socket
			continue
		}
		u, err := strconv.ParseInt(fields[7], 10, 32)
		if err != nil {
			continue
		}
		return int32(u), true
	}
	return 0, false
}
