//! Interface enumeration via netlink for Android.
//!
//! LocalSend X local patch (not upstream): `getifaddrs(3)` only exists in
//! bionic since API 24 (Android 7.0), so a library referencing it fails to
//! load on Android 5.x/6.x with `cannot locate symbol "getifaddrs"`. Instead
//! of linking against it, this module enumerates the interfaces with the
//! netlink requests (RTM_GETLINK / RTM_GETADDR) that bionic itself uses to
//! implement `getifaddrs` — available on every kernel those devices run.

use std::collections::HashMap;
use std::io;
use std::mem;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::os::raw::c_void;
use std::ptr;

use crate::{IfAddr, IfOperStatus, Ifv4Addr, Ifv6Addr, Interface};

/// Alignment of netlink messages and attributes (NLMSG_ALIGNTO).
const ALIGN: usize = 4;

/// Size of the buffer for a single `recv` of dump replies. The kernel only
/// delivers whole messages, so a larger dump is split across several `recv`
/// calls instead of being truncated into this buffer.
const RECV_BUFFER_SIZE: usize = 8192;

/// The end-of-dump message types, re-typed for matching against the u16
/// `nlmsg_type` field (libc defines them as `c_int`).
const NLMSG_DONE: u16 = libc::NLMSG_DONE as u16;
const NLMSG_ERROR: u16 = libc::NLMSG_ERROR as u16;

/// Kernel ABI structures that libc does not define for Android targets.

#[repr(C)]
struct RtAttr {
    rta_len: u16,
    rta_type: u16,
}

#[repr(C)]
struct IfInfoMsg {
    ifi_family: u8,
    __ifi_pad: u8,
    ifi_type: u16,
    ifi_index: i32,
    ifi_flags: u32,
    ifi_change: u32,
}

#[repr(C)]
struct IfAddrMsg {
    ifa_family: u8,
    ifa_prefixlen: u8,
    ifa_flags: u8,
    ifa_scope: u8,
    ifa_index: u32,
}

/// A netlink dump request: the message header followed by an all-zeroes
/// (AF_UNSPEC) link/address message, asking for every one of them.
#[repr(C)]
struct DumpRequest<T> {
    header: libc::nlmsghdr,
    message: T,
}

impl<T> DumpRequest<T> {
    fn new(message_type: u16) -> Self {
        DumpRequest {
            header: libc::nlmsghdr {
                nlmsg_len: mem::size_of::<Self>() as u32,
                nlmsg_type: message_type,
                nlmsg_flags: (libc::NLM_F_REQUEST | libc::NLM_F_DUMP) as u16,
                nlmsg_seq: 1,
                nlmsg_pid: 0,
            },
            message: unsafe { mem::zeroed() },
        }
    }
}

/// Returns every address of every network interface, a drop-in replacement
/// for the `getifaddrs(3)`-based implementation that never calls it.
pub(crate) fn get_if_addrs() -> io::Result<Vec<Interface>> {
    let socket = NetlinkSocket::new()?;

    // Links first: names and interface flags are looked up by index while the
    // addresses are parsed.
    let mut links: HashMap<u32, (String, bool, IfOperStatus)> = HashMap::new();
    let link_request = DumpRequest::<IfInfoMsg>::new(libc::RTM_GETLINK);
    socket.dump(&link_request, |message_type, payload| {
        if message_type != libc::RTM_NEWLINK {
            return;
        }
        let Some((info, attrs)) = parse_message::<IfInfoMsg>(payload) else {
            return;
        };

        let mut name = None;
        let mut oper_status = IfOperStatus::Unknown;
        for_each_attr(attrs, |attr_type, value| match attr_type {
            libc::IFLA_IFNAME => name = name_from_bytes(value),
            libc::IFLA_OPERSTATE => oper_status = oper_status_from(value.first().copied()),
            _ => {}
        });

        if let Some(name) = name {
            let p2p = info.ifi_flags & libc::IFF_POINTOPOINT as u32 != 0;
            links.insert(info.ifi_index as u32, (name, p2p, oper_status));
        }
    })?;

    let mut interfaces = Vec::new();
    let addr_request = DumpRequest::<IfAddrMsg>::new(libc::RTM_GETADDR);
    socket.dump(&addr_request, |message_type, payload| {
        if message_type != libc::RTM_NEWADDR {
            return;
        }
        let Some((info, attrs)) = parse_message::<IfAddrMsg>(payload) else {
            return;
        };

        let mut address = None;
        let mut local = None;
        let mut broadcast = None;
        let mut label = None;
        for_each_attr(attrs, |attr_type, value| match attr_type {
            libc::IFA_ADDRESS => address = ip_from_bytes(info.ifa_family, value),
            libc::IFA_LOCAL => local = ip_from_bytes(info.ifa_family, value),
            libc::IFA_BROADCAST => broadcast = ip_from_bytes(info.ifa_family, value),
            libc::IFA_LABEL => label = name_from_bytes(value),
            _ => {}
        });

        // On IPv4 point-to-point links, IFA_ADDRESS is the peer address and
        // IFA_LOCAL the local one.
        let Some(ip) = local.or(address) else {
            return;
        };

        let index = info.ifa_index;
        let link = links.get(&index);
        let name = label
            .or_else(|| link.map(|(name, ..)| name.clone()))
            .unwrap_or_else(|| format!("if{index}"));
        let (is_p2p, oper_status) = link
            .map(|(_, is_p2p, oper_status)| (*is_p2p, oper_status.clone()))
            .unwrap_or((false, IfOperStatus::Unknown));

        let addr = match ip {
            IpAddr::V4(ip) => {
                let prefixlen = info.ifa_prefixlen.min(32);
                let netmask = Ipv4Addr::from(
                    u32::MAX.checked_shl(32 - u32::from(prefixlen)).unwrap_or(0),
                );
                let broadcast = match broadcast {
                    Some(IpAddr::V4(broadcast)) => Some(broadcast),
                    _ => Some(Ipv4Addr::from(u32::from(ip) | !u32::from(netmask))),
                };
                IfAddr::V4(Ifv4Addr {
                    ip,
                    netmask,
                    prefixlen,
                    broadcast,
                })
            }
            IpAddr::V6(ip) => {
                let prefixlen = info.ifa_prefixlen.min(128);
                let netmask =
                    Ipv6Addr::from(u128::MAX.checked_shl(128 - u32::from(prefixlen)).unwrap_or(0));
                IfAddr::V6(Ifv6Addr {
                    ip,
                    netmask,
                    prefixlen,
                    broadcast: None,
                })
            }
        };

        interfaces.push(Interface {
            name,
            addr,
            index: Some(index),
            oper_status,
            is_p2p,
        });
    })?;

    Ok(interfaces)
}

/// A raw `NETLINK_ROUTE` socket, closed on drop.
struct NetlinkSocket(i32);

impl NetlinkSocket {
    fn new() -> io::Result<Self> {
        let fd = unsafe {
            libc::socket(
                libc::AF_NETLINK,
                libc::SOCK_RAW | libc::SOCK_CLOEXEC,
                libc::NETLINK_ROUTE,
            )
        };
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }

        let mut address: libc::sockaddr_nl = unsafe { mem::zeroed() };
        address.nl_family = libc::AF_NETLINK as _;
        let bound = unsafe {
            libc::bind(
                fd,
                &address as *const libc::sockaddr_nl as *const libc::sockaddr,
                mem::size_of_val(&address) as libc::socklen_t,
            )
        };
        if bound < 0 {
            return Err(io::Error::last_os_error());
        }

        Ok(NetlinkSocket(fd))
    }

    /// Sends a dump request and hands every reply payload to `on_message`
    /// together with its message type, until the kernel reports the end of
    /// the dump.
    fn dump<T>(&self, request: &DumpRequest<T>, mut on_message: impl FnMut(u16, &[u8])) -> io::Result<()> {
        let sent = unsafe {
            libc::send(
                self.0,
                request as *const DumpRequest<T> as *const c_void,
                mem::size_of_val(request),
                0,
            )
        };
        if sent < 0 {
            return Err(io::Error::last_os_error());
        }

        let mut buffer = [0u8; RECV_BUFFER_SIZE];
        loop {
            let received =
                unsafe { libc::recv(self.0, buffer.as_mut_ptr() as *mut c_void, buffer.len(), 0) };
            if received < 0 {
                let error = io::Error::last_os_error();
                if error.kind() == io::ErrorKind::Interrupted {
                    continue;
                }
                return Err(error);
            }
            if received == 0 {
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "netlink socket closed during dump",
                ));
            }
            let received = received as usize;

            // A dump reply is a chain of whole, aligned messages. A message
            // that overruns the received bytes means the reply was truncated.
            let mut offset = 0;
            loop {
                if offset + mem::size_of::<libc::nlmsghdr>() > received {
                    break;
                }
                let header =
                    unsafe { ptr::read_unaligned(buffer.as_ptr().add(offset) as *const libc::nlmsghdr) };
                let length = header.nlmsg_len as usize;
                if length < mem::size_of::<libc::nlmsghdr>() || offset + length > received {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "truncated netlink message",
                    ));
                }

                let payload = &buffer[offset + mem::size_of::<libc::nlmsghdr>()..offset + length];
                match header.nlmsg_type {
                    NLMSG_DONE => return Ok(()),
                    NLMSG_ERROR => return Err(nlmsg_error(payload)),
                    message_type => on_message(message_type, payload),
                }

                offset = align(offset + length);
                // Every message of a multi-part dump sets NLM_F_MULTI; the
                // single reply of a non-dump exchange ends the response here.
                if header.nlmsg_flags & libc::NLM_F_MULTI as u16 == 0 {
                    return Ok(());
                }
            }
        }
    }
}

impl Drop for NetlinkSocket {
    fn drop(&mut self) {
        unsafe { libc::close(self.0) };
    }
}

/// Interprets the start of `payload` as a netlink message of type `T` and
/// returns it together with the remaining attribute bytes.
fn parse_message<T>(payload: &[u8]) -> Option<(T, &[u8])> {
    if payload.len() < mem::size_of::<T>() {
        return None;
    }
    // `T` is a plain-old-data kernel ABI struct without invalid bit patterns.
    let message = unsafe { ptr::read_unaligned(payload.as_ptr() as *const T) };
    Some((message, &payload[mem::size_of::<T>()..]))
}

/// Calls `on_attr` for every `rtattr` in `attrs`, with its type and payload.
fn for_each_attr(attrs: &[u8], mut on_attr: impl FnMut(u16, &[u8])) {
    let mut offset = 0;
    while offset + mem::size_of::<RtAttr>() <= attrs.len() {
        let attr = unsafe { ptr::read_unaligned(attrs.as_ptr().add(offset) as *const RtAttr) };
        let length = attr.rta_len as usize;
        if length < mem::size_of::<RtAttr>() || offset + length > attrs.len() {
            break;
        }

        on_attr(attr.rta_type, &attrs[offset + mem::size_of::<RtAttr>()..offset + length]);
        offset = align(offset + length);
    }
}

/// An `NLMSG_ERROR` reply carries the errno as a negative i32; zero would be
/// an acknowledgement, which dumps never receive.
fn nlmsg_error(payload: &[u8]) -> io::Error {
    let errno = if payload.len() >= 4 {
        i32::from_ne_bytes([payload[0], payload[1], payload[2], payload[3]])
    } else {
        0
    };
    if errno == 0 {
        io::Error::other("netlink request failed with an empty error message")
    } else {
        io::Error::from_raw_os_error(-errno)
    }
}

fn align(len: usize) -> usize {
    (len + ALIGN - 1) & !(ALIGN - 1)
}

/// The `IpAddr` carried by an address attribute, or `None` for other address
/// families than IPv4/IPv6.
fn ip_from_bytes(family: u8, bytes: &[u8]) -> Option<IpAddr> {
    match (family, bytes.len()) {
        (2, 4) => Some(IpAddr::V4(Ipv4Addr::new(
            bytes[0], bytes[1], bytes[2], bytes[3],
        ))),
        (10, 16) => Some(IpAddr::V6(Ipv6Addr::new(
            u16::from_be_bytes([bytes[0], bytes[1]]),
            u16::from_be_bytes([bytes[2], bytes[3]]),
            u16::from_be_bytes([bytes[4], bytes[5]]),
            u16::from_be_bytes([bytes[6], bytes[7]]),
            u16::from_be_bytes([bytes[8], bytes[9]]),
            u16::from_be_bytes([bytes[10], bytes[11]]),
            u16::from_be_bytes([bytes[12], bytes[13]]),
            u16::from_be_bytes([bytes[14], bytes[15]]),
        ))),
        _ => None,
    }
}

/// The string bytes of an `IFLA_IFNAME` / `IFA_LABEL` attribute up to the NUL
/// terminator.
fn name_from_bytes(bytes: &[u8]) -> Option<String> {
    let end = bytes.iter().position(|&byte| byte == 0).unwrap_or(bytes.len());
    String::from_utf8(bytes[..end].to_vec()).ok()
}

/// Maps an `IFLA_OPERSTATE` byte to the `if-addrs` status.
fn oper_status_from(state: Option<u8>) -> IfOperStatus {
    match state {
        Some(1) => IfOperStatus::NotPresent,
        Some(2) => IfOperStatus::Down,
        Some(3) => IfOperStatus::LowerLayerDown,
        Some(4) => IfOperStatus::Testing,
        Some(5) => IfOperStatus::Dormant,
        Some(6) => IfOperStatus::Up,
        _ => IfOperStatus::Unknown,
    }
}
