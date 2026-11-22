// Per-app tunnel engine (tun2socks wrapper) — DRAFT, not yet in the repo.
//
// Why this exists: the stock BPB engine lets Xray-core own the TUN fd.
// That hides the originating app from Xray, so per-app chain choices
// cannot be enforced in the tunnel. This engine takes the TUN fd itself
// (tun2socks v2, gVisor netstack), looks up the UID of each new
// connection's source port in /proc/net, asks the Android side
// (PerAppResolver) which exit the app wants, and dials one of two local
// Xray mixed inbounds:
//
//	app-chain-in  (127.0.0.1:10810) -> the connection's exit node
//	app-direct-in (127.0.0.1:10811) -> the connection itself (no extra hop)
//
// Xray must therefore start WITHOUT a tun inbound (fd 0) and with the
// two dispatch inbounds (see XrayConfigBuilder.perAppEngine).
//
// Design language: no UI change at all — this is entirely under the hood.
package xray

import (
	"context"
	"fmt"
	"net"
	"strconv"
	"sync"
	"syscall"

	"gvisor.dev/gvisor/pkg/tcpip/stack"

	"github.com/xjasonlyu/tun2socks/v2/core"
	"github.com/xjasonlyu/tun2socks/v2/core/device"
	"github.com/xjasonlyu/tun2socks/v2/core/device/fdbased"
	M "github.com/xjasonlyu/tun2socks/v2/metadata"
	"github.com/xjasonlyu/tun2socks/v2/proxy"
	"github.com/xjasonlyu/tun2socks/v2/proxy/socks5"
	"github.com/xjasonlyu/tun2socks/v2/tunnel"
)

// The two local Xray mixed inbounds the engine dials. Must match
// XrayConfigBuilder.appChainProxyPort / appDirectProxyPort.
const (
	appChainAddr  = "127.0.0.1:10810"
	appDirectAddr = "127.0.0.1:10811"
)

// PerAppResolver is implemented by the Android side (Kotlin, via gobind).
// It answers, per Linux UID, which exit the app's traffic takes:
// 0 = through the connection's exit node (chain), 1 = direct (no extra hop).
// Unknown UIDs must return 0 (follow the connection's exit).
type PerAppResolver interface {
	ExitForUID(uid int32) int32
}

// dispatchProxy implements proxy.Proxy: every connection is routed by the
// UID of its source port.
type dispatchProxy struct {
	chain    proxy.Proxy
	direct   proxy.Proxy
	resolver PerAppResolver
}

func (d *dispatchProxy) upstream(md *M.Metadata) proxy.Proxy {
	if d.resolver == nil {
		return d.chain
	}
	uid, ok := lookupUID(md.Network, md.SrcPort)
	if !ok {
		// Socket not (yet) listed in /proc/net: fall back to the
		// connection's exit, the same as an app with no choice.
		return d.chain
	}
	if d.resolver.ExitForUID(uid) == 1 {
		return d.direct
	}
	return d.chain
}

func (d *dispatchProxy) DialContext(ctx context.Context, md *M.Metadata) (net.Conn, error) {
	return d.upstream(md).DialContext(ctx, md)
}

func (d *dispatchProxy) DialUDP(md *M.Metadata) (net.PacketConn, error) {
	return d.upstream(md).DialUDP(md)
}

var (
	tunMu     sync.Mutex
	tunStack  *stack.Stack
	tunDevice device.Device
)

// StartTunEngine starts the per-app tunnel engine on the TUN fd handed over
// by the Android VpnService. The fd is duplicated first: the original stays
// owned by the ParcelFileDescriptor — Go only ever closes the duplicate,
// and it does so through the fdbased device (FD.Close closes its fd).
func StartTunEngine(tunFd int, mtu int, resolver PerAppResolver) error {
	tunMu.Lock()
	defer tunMu.Unlock()
	if tunStack != nil {
		return fmt.Errorf("tun engine already running")
	}
	chain, err := socks5.New(appChainAddr, "", "")
	if err != nil {
		return fmt.Errorf("chain proxy: %w", err)
	}
	direct, err := socks5.New(appDirectAddr, "", "")
	if err != nil {
		return fmt.Errorf("direct proxy: %w", err)
	}

	dupFd, err := syscall.Dup(tunFd)
	if err != nil {
		return fmt.Errorf("dup tun fd: %w", err)
	}
	dev, err := fdbased.Open(strconv.Itoa(dupFd), uint32(mtu), 0)
	if err != nil {
		_ = syscall.Close(dupFd)
		return fmt.Errorf("open tun device: %w", err)
	}
	tunnel.T().SetProxy(&dispatchProxy{chain: chain, direct: direct, resolver: resolver})
	s, err := core.CreateStack(&core.Config{
		LinkEndpoint:     dev,
		TransportHandler: tunnel.T(),
	})
	if err != nil {
		dev.Close()
		return fmt.Errorf("create stack: %w", err)
	}
	tunStack, tunDevice = s, dev
	return nil
}

// StopTunEngine stops the engine. Mirrors engine.Stop: device first,
// then the stack. The duplicated fd is closed by the device itself.
func StopTunEngine() error {
	tunMu.Lock()
	defer tunMu.Unlock()
	if tunDevice != nil {
		tunDevice.Close()
		tunDevice = nil
	}
	if tunStack != nil {
		tunStack.Close()
		tunStack.Wait()
		tunStack = nil
	}
	return nil
}
