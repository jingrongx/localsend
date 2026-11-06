#[cfg(target_os = "android")]
use crate::ifaces::{Interface, Kind, NextHop};

#[cfg(target_os = "android")]
use std::io::Error;

#[cfg(target_os = "android")]
use std::net::SocketAddr;

#[cfg(not(target_os = "android"))]
mod nix_impl {
    use super::{Interface, Kind, NextHop};
    use nix::sys::socket::{AddressFamily, SockaddrLike, SockaddrStorage};
    use std::io::Error;
    use std::net::{SocketAddr, SocketAddrV4, SocketAddrV6};

    fn ss_to_netsa(ss: &SockaddrStorage) -> Option<SocketAddr> {
        match ss.family() {
            Some(AddressFamily::Inet) => ss.as_sockaddr_in().map(|sin| {
                SocketAddr::V4(SocketAddrV4::new(
                    std::net::Ipv4Addr::from(sin.ip()),
                    sin.port(),
                ))
            }),
            Some(AddressFamily::Inet6) => ss.as_sockaddr_in6().map(|sin6| {
                SocketAddr::V6(SocketAddrV6::new(
                    sin6.ip(),
                    sin6.port(),
                    sin6.flowinfo(),
                    sin6.scope_id(),
                ))
            }),
            _ => None,
        }
    }

    /// Query the local system for all interface addresses.
    pub fn ifaces() -> Result<Vec<Interface>, Error> {
        let mut ret = Vec::new();
        for ifa in nix::ifaddrs::getifaddrs()? {
            if let Some(kind) = ifa
                .address
                .as_ref()
                .and_then(SockaddrStorage::family)
                .and_then(|af| match af {
                    AddressFamily::Inet => Some(Kind::Ipv4),
                    AddressFamily::Inet6 => Some(Kind::Ipv6),
                    #[cfg(any(
                        target_os = "android",
                        target_os = "linux",
                        target_os = "illumos",
                        target_os = "fuchsia",
                        target_os = "solaris"
                    ))]
                    AddressFamily::Packet => Some(Kind::Packet),
                    #[cfg(any(
                        target_os = "dragonfly",
                        target_os = "freebsd",
                        target_os = "ios",
                        target_os = "macos",
                        target_os = "illumos",
                        target_os = "netbsd",
                        target_os = "openbsd"
                    ))]
                    AddressFamily::Link => Some(Kind::Link),
                    _ => None,
                })
            {
                let name = ifa.interface_name;
                let dst = ifa.destination.as_ref().and_then(ss_to_netsa);
                let broadcast = ifa.broadcast.as_ref().and_then(ss_to_netsa);
                let hop = dst
                    .map(NextHop::Destination)
                    .or(broadcast.map(NextHop::Broadcast));
                let addr = ifa.address.as_ref().and_then(ss_to_netsa);
                let mask = ifa.netmask.as_ref().and_then(ss_to_netsa);

                ret.push(Interface {
                    name,
                    kind,
                    addr,
                    mask,
                    hop,
                });
            }
        }

        Ok(ret)
    }
}

/// LocalSend X local patch: the nix implementation above calls
/// `getifaddrs(3)`, which only exists in bionic since API 24, so on Android
/// the interfaces come from the `if-addrs` crate instead (patched to use
/// netlink there — see support/patches/if-addrs).
#[cfg(target_os = "android")]
pub fn ifaces() -> Result<Vec<Interface>, Error> {
    let mut ret = Vec::new();
    for iface in if_addrs::get_if_addrs()? {
        let (kind, addr, mask, hop) = match iface.addr {
            if_addrs::IfAddr::V4(v4) => (
                Kind::Ipv4,
                SocketAddr::from((v4.ip, 0)),
                Some(SocketAddr::from((v4.netmask, 0))),
                v4.broadcast
                    .map(|broadcast| NextHop::Broadcast(SocketAddr::from((broadcast, 0)))),
            ),
            if_addrs::IfAddr::V6(v6) => (
                Kind::Ipv6,
                SocketAddr::from((v6.ip, 0)),
                Some(SocketAddr::from((v6.netmask, 0))),
                None,
            ),
        };

        ret.push(Interface {
            name: iface.name,
            kind,
            addr: Some(addr),
            mask,
            hop,
        });
    }

    Ok(ret)
}

#[cfg(not(target_os = "android"))]
pub use nix_impl::ifaces;
